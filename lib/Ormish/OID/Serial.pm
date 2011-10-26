package Ormish::OID::Serial;
use Moose;
use Scalar::Util qw/blessed/;
use Ormish::OID::BaseRole;
with 'Ormish::OID::BaseRole';

has 'column'        => (is => 'rw', isa => 'Str', required => 1);
has 'attr'          => (is => 'rw', isa => 'Str', lazy => 1, default => 'id');

sub as_str {
    my ($self, $target) = @_;
    my $attr_name = $self->attr;
    if (blessed $target) {
        my $attr = $target->meta->get_attribute($attr_name);
        return $attr->get_value($target);
    }
    my $id_value = $target->{$attr_name};
    return $id_value;
}

sub set_object_identity {
    my ($self, $obj, $auto_id) = @_;
    my $attr = $obj->meta->get_attribute($self->attr);
    $attr->set_value($obj, $auto_id);
}

sub is_db_generated { 
    return 1; # yes!
}

sub get_column_names {
    my ($self) = @_;
    return ($self->column);
}

sub col_to_values {
    my ($self, $obj) = @_;
    my $attr = $obj->meta->get_attribute($self->attr);
    return { 
        $self->column() => $attr->get_value($obj),
    };
}

sub attr_to_col {
    my ($self) = @_;
    return { 
        $self->attr() => $self->column,
    };
}

sub col_to_attr {
    my ($self) = @_;
    return { 
        $self->column() => $self->attr,
    };
}


1;

__END__
