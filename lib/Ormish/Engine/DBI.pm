package Ormish::Engine::DBI;
use Moose;
use namespace::autoclean;

use Scalar::Util qw/blessed/;
use SQL::Abstract::More;
use DBIx::Simple;

use Ormish::Engine::DBI::ResultObjects;
use Ormish::Engine::DBI::ResultRows;

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


# TODO: how do we handle multi-table inheritance
# FIXME: how do we handle natural keys
# FIXME: how do we handle composite keys


sub insert_object {
    my ($self, $datastore, $obj) = @_;

    my $db = $self->dbixs;

    my $class = ref($obj) || '';
    my $mapping = $datastore->mapping_of_class($class);
    my $table_rows = $mapping->object_insert_table_rows($datastore, $obj);
    foreach my $table (keys %$table_rows) {
        foreach my $row_spec (@{$table_rows->{$table}}) {
            my ($row, $where) = @$row_spec;
            my ($stmt, @bind) = $self->sql_abstract->insert( $table, $row );
            $self->execute_raw_query([$stmt, \@bind])->flat; 
            # handle serial pk
            my $auto_id = $db->last_insert_id(undef, undef, undef, undef);
            if ($mapping->oid->is_db_generated) {
                $mapping->oid->set_object_identity( $obj, $auto_id );
            }
        }
    }
    $datastore->clean_dirty_obj($obj);
    $datastore->idmap_add($mapping, $obj);
    $datastore->object_setup_related_collections($mapping, $obj);
}


sub insert_object_undo {
    # nop
}

# ---

sub update_object {
    my ($self, $datastore, $obj, $oid_attr_values) = @_;
    if (not $datastore->obj_is_dirty($obj)) {
        # skip clean
        return;
    }
    
    my $db = DBIx::Simple->new($self->dbh);

    my $class = ref($obj) || '';
    my $mapping = $datastore->mapping_of_class($class);
    my $table_rows = $mapping->object_update_table_rows($datastore, $obj, $oid_attr_values);
    foreach my $table (keys %$table_rows) {
        map {
            my ($row, $where) = @$_;
            my ($stmt, @bind) = $self->sql_abstract->update( $table, $row, $where);
            $self->execute_raw_query([$stmt, \@bind])->flat; 
        } @{$table_rows->{$table}};
    }
    $datastore->clean_dirty_obj($obj);
}

sub update_object_undo {
    # nop
}

# ---

sub delete_object {
    my ($self, $datastore, $obj, $oid_attr_values) = @_;
    my $db = DBIx::Simple->new($self->dbh);

    my $class = ref($obj) || '';
    my $mapping = $datastore->mapping_of_class($class);
    my $table_rows = $mapping->object_update_table_rows($datastore, $obj, $oid_attr_values);
    foreach my $table (keys %$table_rows) {
        map {
            my ($row, $where) = @$_;
            my ($stmt, @bind) = $self->sql_abstract->delete($table, $where);
            $self->execute_raw_query([$stmt, \@bind])->flat; 
        } @{$table_rows->{$table}};
    }
}

sub delete_object_undo {
    # nop
}

# ---

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
    # TODO: support composite oids
    my $db = $self->dbixs;
    my $mapping = $datastore->mapping_of_class($class);
    my @oid_cols = keys %{$mapping->oid_col_to_attr};
    {
        my ($oid_col) = @oid_cols;
        my $where_attr = { 
            $mapping->oid_col_to_attr->{$oid_col} => $oid,
        };
        if (ref($oid) eq 'HASH') {
            $where_attr = $oid;
        }
        my $oid_str = $mapping->oid->as_str($where_attr);
        my $o;
        $o = $datastore->idmap_get($mapping, $oid_str);
        if (defined $o) {
            return $o;
        }

        my $where = { 
            $oid_col => $oid, 
        };
        my ($stmt, @bind) = $self->sql_abstract->select( 
            -from       => [ $mapping->table ],
            -where      => $where,
            -limit      => 1, # for now, limit to the first row
        );
        my $r = $self->execute_raw_query([$stmt, \@bind]);
        my $h = $r->hash;
        return if (not defined $h);

        $o = $datastore->object_from_hashref($mapping, $h);
        return $o;
    }
}


sub _build_select {
    my ($self, $datastore, $query, $opt_columns_spec) = @_;
    my @cta = @{$query->meta_result_cta};
    
    my ($stmt, @bind, %user_columns);

    # TODO: add joins later
    # TODO: add multi-table mapping of a class
    {
        my ($class, $table, $alias) = splice(@cta, 0, 3);

        # build query
        # ---
        
        my $from_spec;
        {
            # support single table for now
            my $table_alias = $self->sql_abstract->table_alias($table, $alias);
            $from_spec = [ $query->interpolate_result_qkv($table_alias) ];
        }

        my @columns = ('*');
        if (defined $opt_columns_spec) {
            (ref($opt_columns_spec) eq 'ARRAY')
                or Carp::confess("Cannot use '$opt_columns_spec' as column_spec, expected ARRAYREF");
            @columns = ();
            foreach my $col_spec (@$opt_columns_spec) {
                my ($column, $alias) = split /\|/, $col_spec, 2;
                $column = $query->interpolate_result_qkv($column);
                if (not defined $alias) {
                    $alias = $column;
                }
                $user_columns{$alias} = $column;
                push @columns, $col_spec;
            }
        }
        
        my ($sql_sel, @sql_sel_bind) = $self->sql_abstract->select( -from => $from_spec, -columns => \@columns, );

        my $where_spec = $query->meta_filter_condition;
        my ($sql_where, @sql_where_bind) = ('', );
        if ($where_spec) {
            if (ref($where_spec) eq 'ARRAY') {
                ($sql_where, @sql_where_bind) = @$where_spec;
                if (ref($sql_where) eq 'HASH') {
                    ($sql_where, @sql_where_bind) = $self->sql_abstract->where($sql_where);
                }
                $sql_where =~ s[^\s*WHERE\s*][]i;
            }
            else {
                Carp::confess("Unsupported \$query->where() type");
            }
        }

        my $static_spec = $query->meta_filter_static;
        my ($static_where, @static_where_bind) = ('', );
        if ($static_spec) {
            if (ref($static_spec) eq 'ARRAY') {
                ($static_where, @static_where_bind) = @$static_spec;
                if (ref($static_where) eq 'HASH') {
                    ($static_where, @static_where_bind) = $self->sql_abstract->where($static_where);
                }
                $static_where =~ s[^\s*WHERE\s*][]i;
            }
            else {
                Carp::confess("Unsupported \$query->meta_filter_static() type");
            }
            # attach to where + bind
            if (length($sql_where) > 0) {
                my @all_cond = ($sql_where, $static_where);
                $sql_where = join(' AND ', map { '('.$_.')' } @all_cond );
            }
            else {
                $sql_where = $static_where;
            }
            @sql_where_bind = (@sql_where_bind, @static_where_bind);
        }

        if (length($sql_where) > 0) {
            $sql_where = 'WHERE '.$sql_where;
        }

        my $tmp_stmt = join(' ', $sql_sel, $sql_where ); # more SQL syntax later

        $stmt = $query->interpolate_result_qkv($tmp_stmt);

        @bind = (@sql_sel_bind, @sql_where_bind);
    }
    return ($stmt, \@bind, \%user_columns);

}



sub objects_select {
    my ($self, $datastore, $query) = @_;
    my ($stmt, $bind, undef) = $self->_build_select($datastore, $query);
    # be lazy, query later
    return Ormish::Engine::DBI::ResultObjects->new(
        query               => $query,
        engine              => $self,
        engine_query        => [ $stmt, $bind ],
    );
}


sub rows_select {
    my ($self, $datastore, $query, $opt_columns_spec) = @_;
    my ($stmt, $bind, $user_columns) = $self->_build_select($datastore, $query, $opt_columns_spec);
    # be lazy, query later
    return Ormish::Engine::DBI::ResultRows->new(
        query               => $query,
        engine              => $self,
        engine_query        => [ $stmt, $bind ],
    );
}



# exec SQL, TODO: perhaps refactor this so that the result object doesn't have to know about this
sub execute_raw_query {
    my ($self, $raw_query) = @_;
    $self->debug($raw_query);
    return $self->dbixs->query($raw_query->[0], @{$raw_query->[1]});
}

sub debug {
    my ($self, $info) = @_;
    push @{$self->log_sql}, $info;
}


__PACKAGE__->meta->make_immutable;

1;


__END__
