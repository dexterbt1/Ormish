package Ormish::Mapping::Hook::AttributeColumns;
use Moose;
use Carp ();
use namespace::autoclean;

with 'Ormish::Mapping::Hook::Role';

has 'attr_to_col'   => (isa => 'HashRef[Str]', is => 'ro', required => 1);
has 'pack'          => (isa => 'CodeRef', is => 'rw', predicate => 'has_pack');
has 'unpack'        => (isa => 'CodeRef', is => 'rw', predicate => 'has_unpack');

sub get_attr_to_col {
    my ($self) = @_;
    return $self->attr_to_col;
}

sub table_columns_for_select_hook {
    my ($self, $mapping, $tcols) = @_;
    my $table = $mapping->table;
    if (not exists $tcols->{$table}) {
        $tcols->{$table} = { };
    }
    foreach my $at (keys %{$self->attr_to_col}) {
        $tcols->{$table}->{$at} = 1;
    }
}

sub object_insert_table_rows_hook {
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

sub object_update_table_rows_hook {
    my ($self, $mapping, $table_rows, $datastore, $obj, $obj_oid_attr_values) = @_;
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
        foreach my $oid_attr (keys %$obj_oid_attr_values) {
            if (exists $self->attr_to_col->{$oid_attr}) {
                my $col         = $self->attr_to_col->{$oid_attr};
                $where->{$col}  = $obj_oid_attr_values->{$oid_attr};
            }
        }
    }
}

sub new_object_from_hashref_hook {
    my ($self, $mapping, $datastore, $href, $object_attrs) = @_;
    foreach my $attr (keys %{$self->attr_to_col}) {
        if (exists $object_attrs->{$attr}) {
            Carp::confess("Mapping conflict for class=[".$mapping->for_class."] attribute=[".$attr."]");
        }
        my $col = $self->attr_to_col->{$attr};
        my $value = exists $href->{$col} ? $href->{$col} : undef;
        $object_attrs->{$attr} = $self->has_unpack ? $self->unpack->($value) : $value;
        1;
    }
    1;
}




1;

__END__
