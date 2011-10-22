package Ormish::Engine::DBI;
use Moose;
use SQL::Abstract::More;
use DBIx::Simple;

has 'sql_abstract'  => (is => 'rw', isa => 'SQL::Abstract::More', default => sub { SQL::Abstract::More->new });

sub insert {
    my ($self, $store, $obj) = @_;
    my $class = ref($obj) || '';
    my $mapping = $store->mapping_of_class($class);

    # FIXME: how do we handle multi-table inheritance
    my $dest_table = $mapping->table;
    my ($stmt, @bind) = $self->sql_abstract->insert(
        $dest_table,
        $mapping->column_values_for($obj),
    );

    my $db = DBIx::Simple->new($store->dbh);
    $db->query($stmt, @bind)->flat; 

    # FIXME: how do we handle multi-table inheritance
    # FIXME: how do we handle natural keys
    # FIXME: how do we handle composite keys
    my $auto_id = $db->last_insert_id(undef, undef, undef, undef);
    $mapping->oid->set_object_identity( $obj, $auto_id );
    return [ $stmt, \@bind ];
}


1;
__END__
