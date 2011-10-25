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
                        
has 'log_sql'       => (is => 'rw', isa => 'ArrayRef', default => sub { [ ] });
has 'sql_abstract'  => (is => 'rw', isa => 'SQL::Abstract::More', default => sub { SQL::Abstract::More->new });

sub insert_object {
    my ($self, $datastore, $obj) = @_;

    my $db = DBIx::Simple->new($self->dbh);

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

sub debug {
    my ($self, $info) = @_;
    push @{$self->log_sql}, $info;
}


1;
__END__
