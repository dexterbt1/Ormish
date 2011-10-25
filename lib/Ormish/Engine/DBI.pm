package Ormish::Engine::DBI;
use Moose;
use SQL::Abstract::More;
use DBIx::Simple;
use Ormish::Engine::BaseRole;

with 'Ormish::Engine::BaseRole';

has 'dbh'           => (is          => 'ro', 
                        isa         => 'DBI::db', 
                        required    => 1,
                        trigger     => sub { 
                                        $_[1]->{RaiseError} = 1;
                                        (not $_[1]->{AutoCommit}) or Carp::confess("AutoCommit is not supported");
                                    },
                        );
has 'dbixs'         => (is => 'rw', isa => 'DBIx::Simple', lazy => 1, default => sub { DBIx::Simple->new($_[0]->dbh) });
has 'log_sql'       => (is => 'rw', isa => 'ArrayRef', default => sub { [ ] });
has 'sql_abstract'  => (is => 'rw', isa => 'SQL::Abstract::More', default => sub { SQL::Abstract::More->new });

sub insert_object {
    my ($self, $datastore, $obj) = @_;

    my $db = $self->dbixs;

    my $class = ref($obj) || '';
    my $mapping = $datastore->mapping_of_class($class);
    my $table_rows = $mapping->table_rows_of($obj);
    foreach my $table (keys %$table_rows) {
        map {
            my ($row, $where) = @$_;
            my ($stmt, @bind) = $self->sql_abstract->insert( $table, $row );
            $db->query($stmt, @bind)->flat; 
            # handle serial pk
            my $auto_id = $db->last_insert_id(undef, undef, undef, undef);
            if ($mapping->oid->is_db_generated) {
                $mapping->oid->set_object_identity( $obj, $auto_id );
            }
            $self->debug([ $stmt, \@bind ]);
        } @{$table_rows->{$table}};
    }
    $datastore->idmap_add($obj);

    # FIXME: how do we handle multi-table inheritance
    # FIXME: how do we handle natural keys
    # FIXME: how do we handle composite keys
}

sub insert_object_undo {
    # TODO:
}

# ---

sub update_object {
    my ($self, $datastore, $obj) = @_;
    if (not $datastore->obj_is_dirty($obj)) {
        # skip clean
        return;
    }
    
    my $db = DBIx::Simple->new($self->dbh);

    my $class = ref($obj) || '';
    my $mapping = $datastore->mapping_of_class($class);
    my $table_rows = $mapping->table_rows_of($obj, 1);
    foreach my $table (keys %$table_rows) {
        map {
            my ($row, $where) = @$_;
            my ($stmt, @bind) = $self->sql_abstract->update( $table, $row, $where);
            $db->query($stmt, @bind)->flat; 
            $self->debug([ $stmt, \@bind ]);
        } @{$table_rows->{$table}};
    }
    $datastore->clean_dirty_obj($obj);
}

sub update_object_undo {
    my ($self, $datastore, $obj) = @_;
}



sub commit {
    my ($self) = @_;
    $self->dbh->commit;
}

sub rollback {
    my ($self) = @_;
    $self->dbh->rollback;
}


sub get_object_by_oid {
    my ($self, $datastore, $class, $oid) = @_;
    my $db = $self->dbixs;
    my $mapping = $datastore->mapping_of_class($class);
    my @oid_cols = $mapping->oid->get_column_names;
    if (scalar(@oid_cols) == 1) {
        my ($oid_col) = @oid_cols;
        my ($stmt, @bind) = $self->sql_abstract->select( 
            -from       => [ $mapping->table ],
            -where      => { $oid_col => $oid },
            -limit      => 1,
        );
        my $r = $db->query($stmt, @bind);
        $self->debug([ $stmt, \@bind ]);
        my $h = $r->hash;
        return if (not defined $h);
        return $datastore->get_object_from_hashref($mapping, $h);
    }
}


sub execute_query {
    my ($self, $datastore, $query) = @_;
    my @class_tables = $query->get_result_class_tables;
    my %c2t = @class_tables;
    (scalar(keys %c2t) == 1)
        or Carp::confess("unsupported number of result_types, try 1 for now");
    # TODO: add joins later
    # TODO: add multi-table mapping of a class
    {
        my ($class, $table) = (shift @class_tables, shift @class_tables);
        my ($stmt, @bind) = $self->sql_abstract->select(
            -from           => [ $table ],
        );
        my $r = $self->dbixs->query($stmt, @bind);
        return Ormish::Engine::DBI::QueryResult->new(
            datastore       => $datastore,
            query           => $query,
            dbixs_result    => $r,
        );
    }
}


sub debug {
    my ($self, $info) = @_;
    push @{$self->log_sql}, $info;
}


# ============================================================================

package Ormish::Engine::DBI::QueryResult;
use Moose;
use Carp ();
with 'Ormish::Query::ResultRole';

has 'dbixs_result'      => (is => 'rw', isa => 'DBIx::Simple::Result', required => 1);
has '_cache_result_ct'  => (is => 'rw', isa => 'ArrayRef', default => sub { [ ] });

sub BUILD {
    my ($self) = @_;
    my @result_class_tables = $self->query->get_result_class_tables;
    $self->_cache_result_ct( \@result_class_tables );
}

sub _next_row {
    my ($self) = @_;
    my $row = $self->dbixs_result->hash; 
}

sub next {
    my ($self) = @_;
    my $row = $self->_next_row();
    return if (not $row);
    # for now, build only 1 class 
    my ($class, $table) = @{$self->_cache_result_ct};
    my $mapping = $self->datastore->mapping_of_class($class);
    return $self->datastore->get_object_from_hashref($mapping, $row);
}

sub list {
    my ($self) = @_;
    my @out = ();
    while (my $b = $self->next) {
        push @out, $self->next;
    }
    return @out;
}


1;

__END__
