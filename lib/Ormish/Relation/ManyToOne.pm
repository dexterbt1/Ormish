package Ormish::Relation::ManyToOne;
use Moose;
use namespace::autoclean;
use Carp ();
use Scalar::Util ();

with 'Ormish::Relation::Role';

sub check_supported_type_constraint { # TODO
    # nop for now
}

sub get_proxy_object {
    my ($self, $attr_name, $obj, $obj_mapping) = @_;
    my $t = Scalar::Util::refaddr($obj);
    my $proxy = tie $t, 'Ormish::Relation::ManyToOne::TiedObjectProxy', {
        _attr_name        => $attr_name,
        _object           => $obj,
        _object_mapping   => $obj_mapping,
    };
    return $t;
}

sub requires_proxy { 0 }

1;

__PACKAGE__->meta->make_immutable;

# --------------------

{
    package Ormish::Relation::ManyToOne::TiedObjectProxy;
    use Moose;
    use namespace::autoclean;
    use Carp ();

    has '_attr_name'        => (is => 'rw', isa => 'Str');
    has '_target_obj'       => (is => 'rw', isa => 'Object|Undef');
    has '_object'           => (is => 'rw', isa => 'Object');
    has '_object_mapping'   => (is => 'rw', isa => 'Ormish::Mapping');
    has '_relation'         => (is => 'rw', does => 'Ormish::Relation::Role');

    sub TIESCALAR {
        my ($class, $opts) = @_;
        return $class->new(%$opts);
    }

    sub FETCH {
        my ($self) = @_;
        return $self->_target_obj;
    }

    sub STORE {
        my ($self, $target) = @_;
        $self->_target_obj($target); 
    }


    __PACKAGE__->meta->make_immutable;
}


1;


