package Ormish::Relation::ManyToOne;
use Moose;
use namespace::autoclean;
use Carp ();
use Scalar::Util ();

with 'Ormish::Relation::Role';

sub check_supported_type_constraint {
    my ($self, $class, $attr_name) = @_;
    # strongly impose associations for now (i.e. NULLable FKs)
    # FIXME: inheritance and composition will not require this
    my $attr = $class->meta->get_attribute($attr_name);
    if (not $attr->is_required) {
        $attr->type_constraint->check(undef)
            or Carp::confess("Expected 'Undef' to be included in type constraints of '$attr_name' in class '$class'");
    }
}

sub get_proxy {
    my ($self, $datastore, $attr_name, $obj, $obj_mapping) = @_;
    my $t = Scalar::Util::refaddr($obj);
    my $proxy = tie $t, 'Ormish::Relation::ManyToOne::TiedObjectProxy', {
        _attr_name          => $attr_name,
        _object             => $obj,
        _object_mapping     => $obj_mapping,
        _datastore          => $datastore,
        _relation           => $self,
    };
    return $proxy;
}

sub is_collection { 0 }

1;

__PACKAGE__->meta->make_immutable;

# --------------------

{
    package Ormish::Relation::ManyToOne::TiedObjectProxy;
    use Moose;
    use MooseX::InsideOut;
    use Carp ();
    use Scalar::Util ();

    with 'Ormish::Relation::Proxy::Role';

    has '_attr_name'        => (is => 'rw', isa => 'Str');
    has '_object'           => (is => 'rw', isa => 'Object|HashRef', weak_ref => 1); # in ManyToOne, this is the ONE part
    has '_object_mapping'   => (is => 'rw', isa => 'Ormish::Mapping');
    has '_relation'         => (is => 'rw', does => 'Ormish::Relation::Role');
    has '_datastore'        => (is => 'rw', isa => 'Ormish::DataStore', weak_ref => 1);
    has '_cached_object'    => (is => 'rw', isa => 'Object', weak_ref => 1, predicate => '_has_cached_object');

    sub TIESCALAR {
        my ($class, $opts) = @_;
        return $class->new(%$opts);
    }

    sub FETCH {
        my ($self) = @_;
        my $ds = $self->_datastore;
        my $o = $self->_object;
        if (Scalar::Util::blessed($o)) {
            return $o;
        }
        # here, $o becomes the oid_attr_values
        if ($self->_has_cached_object) {
            return $self->_cached_object;
        }
        my $spec = $o;
        my $out = $ds->query($self->_relation->to_class)->fetch($spec);
        return $out;
    }

    sub STORE {
        Carp::confess("ASSERT: Readonly proxy cannot be altered");
    }


    __PACKAGE__->meta->make_immutable;
}


1;


