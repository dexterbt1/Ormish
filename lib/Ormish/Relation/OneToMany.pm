package Ormish::Relation::OneToMany;
use Moose;
use namespace::autoclean;
use Carp ();

with 'Ormish::Relation::Role';

sub get_proxy_object {
    my ($self, $parent_obj, $parent_obj_mapping) = @_;
    my $set = Ormish::Relation::OneToMany::SetProxy->new;
    $set->parent_object($parent_obj);
    $set->parent_object_mapping($parent_obj_mapping);
    return $set;
}


1;

__PACKAGE__->meta->make_immutable;

{
    package Ormish::Relation::OneToMany::SetProxy;
    use Moose;
    use MooseX::NonMoose;
    use MooseX::InsideOut;

    use Carp ();

    extends 'Set::Object';

    has 'parent_object'         => (is => 'rw', isa => 'Object');
    has 'parent_object_mapping' => (is => 'rw', isa => 'Ormish::Mapping');

    for (qw/ union equal /) {
        override $_ => sub {
            Carp::confess("Unimplemented functionality");
        }; 
    }

    # ---

    sub insert {
        my ($self, @thingies) = @_;
        my $ds = Ormish::DataStore::of($self->parent_object);
        $ds->flush;
        map { 
            $ds->add($_) 
        } @thingies;
        return scalar(@thingies);
    }

    no Moose;

    __PACKAGE__->meta->make_immutable;
}

1;

__END__

