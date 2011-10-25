package Ormish::OID::BaseRole;
use Moose::Role;

# $oid->as_str( \%hashref_or_$object )
#   can return undef
requires 'as_str';

requires 'set_object_identity';

requires 'is_db_generated';

requires 'col_to_values';

requires 'attr_to_col';
requires 'col_to_attr';

requires 'get_column_names';


1;

__END__
