package Ormish::Mapping::OID::Auto;
use Moose;
use namespace::autoclean;

use Scalar::Util ();
use Carp ();

with 'Ormish::Mapping::OID::Role';

has 'attribute'     => (is => 'ro', isa => 'Str', required => 1);

sub as_str {
    my ($self, $obj) = @_;
    my $attr_name = $self->attribute;
    if (Scalar::Util::blessed($obj)) {
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
    if (Scalar::Util::blessed($obj)) {
        my $attr = $obj->meta->get_attribute($attr_name);
        return { 
            $attr_name => $attr->get_value($obj),
        };
    }
    return { 
        $attr_name => $obj->{$attr_name},
    };
}

sub do_install_meta_attributes {
    my ($self, $class) = @_;
    ($self->install_attributes)
        or Carp::confess("Cannot install meta attributes when 'install_attributes' is false");
    my $attr_name = $self->attribute;
    (not $class->meta->has_attribute($attr_name))
        or Carp::confess("Cannot override existing attribute '$attr_name' in class '$class'");

    my $make_immutable = 0;
    if ($class->meta->is_immutable) {
        $class->meta->make_mutable;
        $make_immutable = 1;
    }

    $class->meta->add_attribute($attr_name, {
        is => 'rw',
        isa => 'Int|Undef',
    });

    ($make_immutable) && do { $class->meta->make_immutable; };
}

__PACKAGE__->meta->make_immutable;

1;

__END__
