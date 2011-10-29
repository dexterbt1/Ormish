package Ormish::Relation::Role;
use Moose::Role;

has 'to_class'      => (is => 'ro', isa => 'Str', required => 1);
has 'reverse_rel'   => (is => 'rw', does => 'Ormish::Relation::Role', predicate => 'has_reverse_rel');

requires 'get_proxy_object';


1;

__END__
