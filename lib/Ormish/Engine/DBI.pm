package Ormish::Engine::DBI;
use Moose;
use SQL::Abstract::More;
use DBIx::Simple;

has 'sql_abstract'  => (is => 'rw', isa => 'SQL::Abstract::More', default => sub { SQL::Abstract::More->new });

sub new_object {
    my ($self, $datastore, $obj) = @_;

    my $db = DBIx::Simple->new($datastore->dbh);

    my $class = ref($obj) || '';
    my $mapping = $datastore->mapping_of_class($class);
    my $table_rows = $mapping->table_rows_of($obj);
    foreach my $table (keys %$table_rows) {
        map {
            my $row = $_;
            my ($stmt, @bind) = $self->sql_abstract->insert( $table, $row );
            $db->query($stmt, @bind)->flat; 
            # handle serial pk
            my $auto_id = $db->last_insert_id(undef, undef, undef, undef);
            if ($mapping->oid->is_db_generated) {
                $mapping->oid->set_object_identity( $obj, $auto_id );
            }
            $datastore->log_debug([ $stmt, \@bind ]);
        } @{$table_rows->{$table}};
    }
    $datastore->idmap_add($obj);

    # FIXME: how do we handle multi-table inheritance
    # FIXME: how do we handle natural keys
    # FIXME: how do we handle composite keys
}


1;
__END__
