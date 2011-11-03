package Ormish::Query::Result::BaseRole;
use Moose::Role;
use MooseX::Role::WithOverloading;

has 'engine'        => (is => 'rw', does => 'Ormish::Engine::BaseRole', required => 1);
has 'engine_query'  => (is => 'rw', isa => 'Any', required => 1); # engine-specific query, to be passed back later when needed
has 'query'         => (is => 'rw', isa => 'Ormish::Query', required => 1);

requires qw/
    next
    list
    first
/;

use overload
    '@{}'           => sub { [ $_[0]->list ] }
    ;


1;

__END__
