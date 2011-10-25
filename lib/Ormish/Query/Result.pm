package Ormish::Query::ResultRole;
use Moose::Role;

has 'datastore'     => (is => 'rw', isa => 'Ormish::DataStore');
has 'query'         => (is => 'rw', isa => 'Ormish::Query');

requires qw/
    next
    list
/;

1;

__END__
