{
    package Ormish::Relation::Role;
    use Moose::Role;

    has 'to_class'      => (is => 'ro', isa => 'Str', required => 1);

    requires 'is_collection';

    requires 'get_proxy';

    requires 'check_supported_type_constraint';
}
{
    package Ormish::Relation::Proxy::Role;
    use Moose::Role;

}

1;

__END__
