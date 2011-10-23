package Ormish::OID::BaseRole;
use Moose::Role;

# can return undef
requires 'as_str';

requires 'set_object_identity';

requires 'is_db_generated';

requires 'col_to_values';


1;

__END__
