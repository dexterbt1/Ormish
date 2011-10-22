package Ormish::OID::BaseRole;
use Moose::Role;

# can return undef
requires 'as_str';

requires 'set_object_identity';

1;

__END__
