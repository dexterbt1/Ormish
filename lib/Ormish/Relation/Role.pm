package Ormish::Relation::Role;
use Moose::Role;

has 'to_class'      => (is => 'ro', isa => 'Str', required => 1);

requires 'requires_proxy';

requires 'get_proxy_object';

requires 'check_supported_type_constraint';


1;

__END__
