package Ormish::Engine::BaseRole;
use Moose::Role;

requires 'insert_object';
requires 'insert_object_undo';
requires 'update_object';
requires 'update_object_undo';

requires 'commit';
requires 'rollback';

1;
__END__
