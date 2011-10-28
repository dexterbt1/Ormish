package Ormish::Query::Result::BaseRole;
use Moose::Role;

has 'engine'        => (is => 'rw', does => 'Ormish::Engine::BaseRole', required => 1);
has 'engine_query'  => (is => 'rw', isa => 'Any', required => 1); # engine-specific query, to be passed back later when needed
has 'query'         => (is => 'rw', isa => 'Ormish::Query', required => 1);

requires qw/
    next_row
    next
    as_list
/;

1;

__END__
