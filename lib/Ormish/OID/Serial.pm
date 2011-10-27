package Ormish::OID::Serial;
use Moose;
use namespace::autoclean;

use Scalar::Util qw/blessed/;

use Ormish::OID::BaseRole;
with 'Ormish::OID::BaseRole';

has 'attribute' => (is => 'ro', isa => 'Str', required => 1);

sub as_str {
    my ($self, $obj) = @_;
    my $attr_name = $self->attribute;
    if (blessed $obj) {
        my $attr = $obj->meta->get_attribute($attr_name);
        return $attr->get_value($obj);
    }
    my $id_value = $obj->{$attr_name};
    return $id_value;
}

sub set_object_identity {
    my ($self, $obj, $auto_id) = @_;
    my $attr = $obj->meta->get_attribute($self->attribute);
    $attr->set_value($obj, $auto_id);
}

sub is_db_generated { 
    return 1; # yes!
}

sub get_attributes {
    my ($self) = @_;
    return ($self->attribute);
}

sub attr_values {
    my ($self, $obj) = @_;
    my $attr_name   = $self->attribute;
    if (blessed $obj) {
        my $attr = $obj->meta->get_attribute($attr_name);
        return { 
            $attr_name => $attr->get_value($obj),
        };
    }
    return { 
        $attr_name => $obj->{$attr_name},
    };
}

__PACKAGE__->meta->make_immutable;

1;

__END__
