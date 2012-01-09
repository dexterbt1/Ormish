package Ormish::Engine::Role;
use Moose::Role;

requires qw/
    insert_object
    update_object
    delete_object

    commit
    rollback

    get_object_by_oid

    objects_select
    
    rows_select

    execute_raw_query
/;

1;
__END__
