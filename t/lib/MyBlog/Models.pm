{
    package My::Blog;
    use Moose;
    use namespace::autoclean;
    use Set::Object;

    has 'id'            => (is => 'rw', isa => 'Int|Undef'); # explicit, needed as the object identity
    has 'name'          => (is => 'rw', isa => 'Str', required => 1);
    has 'title'         => (is => 'rw', isa => 'Str');
    has 'tagline'       => (is => 'rw', isa => 'Str');

    has 'posts'         => (is => 'ro', isa => 'Set::Object', default => sub { Set::Object->new() });
    
    sub _ORMISH_MAPPING {
        return Ormish::Mapping->new(  # this assumes you'll be using Ormish later, without "use"ing it right now
            for_class       => __PACKAGE__,
            table           => 'blog_blog',
            attributes      => [qw/
                id|b_id
                name 
                title
                tagline|c_tag_line
            /],
            oid             => Ormish::OID::Serial->new( attribute => 'id' ),
            relations       => {
                posts           => Ormish::Relation::OneToMany->new( to_class => 'My::Post' ),
            },
        );
    }

    __PACKAGE__->meta->make_immutable;
}
{
    package My::Post;
    use Moose;
    use namespace::autoclean;

    has 'title'             => (is => 'rw', isa => 'Str', required => 1);
    has 'content'           => (is => 'rw', isa => 'Str');
    has 'parent_blog'       => (is => 'rw', isa => 'My::Blog');

    sub _ORMISH_MAPPING {
        return Ormish::Mapping->new(  
            for_class       => __PACKAGE__,
            table           => 'blog_post',
            attributes      => [qw/
                title
                content
                parent_blog|parent_blog_id=id
            /],
            oid             => Ormish::OID::Serial->new( attribute => 'id', install_attributes => 1 ),
            relations       => {
                parent_blog     => Ormish::Relation::ManyToOne->new( to_class => 'My::Blog' ),
            },
        );
    }

    __PACKAGE__->meta->make_immutable;
}

1;
