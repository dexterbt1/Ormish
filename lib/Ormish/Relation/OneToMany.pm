package Ormish::Relation::OneToMany;
use Moose;
use namespace::autoclean;
use Carp ();
use Set::Object ();

with 'Ormish::Relation::Role';

sub check_supported_type_constraint {
    my ($self, $class, $attr_name) = @_;
    my $attr = $class->meta->get_attribute($attr_name);
    $attr->verify_against_type_constraint(Set::Object->new)
        or Carp::confess("Unsupported type constraint for attribute '$attr_name' in class '$class' (expected Set::Object)");
}

sub get_proxy_object {
    my ($self, $attr_name, $obj, $obj_mapping) = @_;
    my $set = Ormish::Relation::OneToMany::SetProxy->new;
    $set->_attr_name($attr_name);
    $set->_object($obj);
    $set->_object_mapping($obj_mapping);
    $set->_relation($self);
    return $set;
}

sub requires_proxy { 1 }

1;

__PACKAGE__->meta->make_immutable;

{
    package Ormish::Relation::OneToMany::SetProxy;
    use Moose;
    use MooseX::NonMoose;
    use MooseX::InsideOut;

    use Scalar::Util ();
    use Carp ();

    extends 'Set::Object';

    has '_attr_name'        => (is => 'rw', isa => 'Str');
    has '_object'           => (is => 'rw', isa => 'Object', weak_ref => 1);
    has '_object_mapping'   => (is => 'rw', isa => 'Ormish::Mapping');
    has '_relation'         => (is => 'rw', does => 'Ormish::Relation::Role');

    for (qw/ union equal /) {
        override $_ => sub {
            Carp::confess("Unimplemented functionality");
        }; 
    }

    # ---

    sub insert {
        my ($self, @thingies) = @_;
        my $o = $self->_object;
        my $ds = Ormish::DataStore::of($o);
        $ds->flush;
        foreach my $t (@thingies) {
            my $t_ds = Ormish::DataStore::of($t);
            my $t_class = ref($t);
            my $t_mapping = $ds->mapping_of_class($t_class);

            if (defined $t_ds) {
                (Scalar::Util::refaddr($t_ds) == Scalar::Util::refaddr($ds))
                    or Carp::confess("Cannot insert object bound in another datastore into OneToMany relation");
                # update
                $ds->add_dirty($o, $self->_attr_name);
            }
            else {
                # insert
                my $t_reverse_rel_attr_name = $self->_object_mapping->get_reverse_relation_attr_name($ds, $self->_attr_name);
                my $attr = $t_class->meta->get_attribute($t_reverse_rel_attr_name);
                $ds->add($t); 
                $attr->set_value($t, $o);
                1;
            }
        }
        return scalar(@thingies);
    }

    no Moose;

    __PACKAGE__->meta->make_immutable;
}

1;

__END__

