package Ormish::Relation::ManyToOne;
use Moose;
use namespace::autoclean;
use Carp ();

with 'Ormish::Relation::Role';

sub get_proxy_object {
    my ($self, $parent_obj, $parent_obj_mapping) = @_;
    return;
}


1;


