package Ormish::Engine::BaseRole;
use Moose::Role;

requires qw/
    insert_object
    insert_object_undo
    update_object
    update_object_undo

    commit
    rollback

    get_object_by_oid

    query_select

    execute_raw_query
/;

1;
__END__
