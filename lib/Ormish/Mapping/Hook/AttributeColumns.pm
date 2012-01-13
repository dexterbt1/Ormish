package Ormish::Mapping::Hook::AttributeColumns;
use Moose;
use namespace::autoclean;

with 'Ormish::Mapping::Hook::Role';

has 'attr_to_col'   => (isa => 'HashRef[Str]', is => 'ro', required => 1);
has 'pack'          => (isa => 'CodeRef', is => 'rw', predicate => 'has_pack');
has 'unpack'        => (isa => 'CodeRef', is => 'rw', predicate => 'has_unpack');

sub get_attr_to_col {
    my ($self) = @_;
    return %{$self->attr_to_col};
}

sub after_table_columns_for_select {
    my ($self, $mapping, %tcols) = @_;
    my $table = $mapping->table;
    if (not exists $tcols{$table}) {
        $tcols{$table} = { };
    }
    %{$tcols{$table}} = (%{$tcols{$table}}, map { $_ => 1 } %{$self->attr_to_col});
    return  
}

sub after_object_insert_table_rows {
    my ($self, $mapping, $table_rows, $datastore, $obj) = @_;
    my $table = $mapping->table;
    foreach my $row_spec (@{$table_rows->{$table}}) {
        my ($row, $where) = @$row_spec;
        foreach my $attr_name (keys %{$self->attr_to_col}) {
            next if ($mapping->oid->is_db_generated && exists($mapping->oid_attr_to_col->{$attr_name})); # skip oid columns
            my $attr    = $obj->meta->get_attribute($attr_name);
            my $value   = $attr->get_value($obj);
            my $col     = $self->attr_to_col->{$attr_name};
            $row->{$col} = $self->has_pack ? $self->pack->($value) : $value;
        }
    }
}



1;

__END__
