{
    package My::Blog;
    use Moose;
    use namespace::autoclean;

    has 'id'            => (is => 'rw', isa => 'Any'); # needed as the object identity
    has 'name'          => (is => 'rw', isa => 'Str', required => 1);
    has 'title'         => (is => 'rw', isa => 'Str');
    has 'tagline'       => (is => 'rw', isa => 'Str');
    has 'posts'         => (is => 'rw', isa => 'Set::Object');
    
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
            #relations       => [
            #    Ormish::Relation::OneToMany->new( attr => 'posts', to_class => 'My::Post' );
            #],
        );
    }
    1;

    __PACKAGE__->meta->make_immutable;
}
#{
#    package My::Post;
#    use Moose;
#    use id              => (is => 'rw', isa => 
#}

package main;
use strict;
use Test::More qw/no_plan/;
use Scalar::Util qw/refaddr/;
use DBI;
use DBIx::Simple;
use Ormish;

my $dbh = DBI->connect("DBI:SQLite:dbname=:memory:","","",{ RaiseError => 1, AutoCommit => 0 });
$dbh->do('CREATE TABLE blog_blog (b_id INTEGER PRIMARY KEY, name VARCHAR, title VARCHAR, c_tag_line VARCHAR)');
$dbh->commit;

my @sql = ();
my $ds = Ormish::DataStore->new( 
    engine      => Ormish::Engine::DBI->new( dbh => $dbh, log_sql => \@sql ), 
    auto_map    => 1,
);


{
    my $blog = My::Blog->new( name => 'ormish-blog' );
    ok not defined $blog->id;
    ok not defined Ormish::DataStore::of($blog);
    is scalar(@sql), 0;

    $ds->add( $blog );
    ok not defined $blog->id;
    is Ormish::DataStore::of($blog), $ds;
    is scalar(@sql), 0;

    $ds->flush; # do actual insert
    ok defined $blog->id;
    is Ormish::DataStore::of($blog), $ds;
    is scalar(@sql), 1;

    $blog->title('The Ormish Blog');
    $blog->tagline('an alternative object-relational persistence for moose objects');
    $ds->commit; # flush (update) and commit!
    is scalar(@sql), 2;

    $blog->tagline('rubbish tagline for now, only to be discarded later');
    $blog->title('The Orcish Blog');
    $ds->rollback;
    is $blog->title, 'The Ormish Blog';
    is $blog->tagline, 'an alternative object-relational persistence for moose objects';

    my $blog2 = My::Blog->new( name => 'foo.bar', title => 'A Proper Title' );
    $ds->add($blog2);
    is Ormish::DataStore::of($blog2), $ds;
    $ds->rollback;
    isnt Ormish::DataStore::of($blog2), $ds;

    @sql = ();

    $ds->add($blog2);
    is scalar(@sql), 0;
    
    my $b1 = $ds->query('My::Blog')->get($blog->id); # by oid
    is $b1, $blog; # string 'eq' comparison
    is refaddr($b1), refaddr($blog);
    is scalar(@sql), 2; # insert + select
    is Ormish::DataStore::of($b1), $ds;

    # update and flush, 
    $b1->title($b1->title);
    $ds->commit;
    {
        # make sure that single object updates affects only the oids concerned
        my $bx = $ds->query("My::Blog")->get($b1->id);
        is $bx, $b1;
        is $b1, $blog;
        isnt $b1, $blog2;
        isnt $b1->title, $blog2->title;
        # and be paranoid, check the db that indeed only 
        my @affected = DBIx::Simple->new($dbh)->query("SELECT * FROM blog_blog WHERE title=?", $b1->title)->arrays();
        is scalar(@affected), 1;
    }

    DBIx::Simple->new($dbh)->query(q{INSERT INTO blog_blog (b_id,name,title,c_tag_line) VALUES (??)},
        123, 'some-random-blog', 'Some Random Blog', '... nothing here, move along',
        );

    my $b2 = $ds->query('My::Blog')->get(123);
    isa_ok $b2, 'My::Blog';
    is Ormish::DataStore::of($b2), $ds;
    is $b2->id, 123;
    is $b2->name, 'some-random-blog';
    is $b2->title, 'Some Random Blog';
    is $b2->tagline, '... nothing here, move along';
    is scalar(@sql), 5;

    $ds->add($b2);
    $ds->commit;
    is scalar(@sql), 5; # no effect, no queries issued

    # --- query result

    my $c;
    my $q;
    my $result;
    my @all;

    # iterator interface

    @sql = ();
    $result = $ds->query('My::Blog')->select; # hold that query until iteration time
    is scalar(@sql), 0;
    while (my $b = $result->next) {
        isa_ok $b, 'My::Blog';
        $c++;
    }
    is $c, 3;
    is scalar(@sql), 1;

    # pull all objects into memory as a list
    $result = $ds->query('My::Blog')->select;
    @all = $result->as_list;
    is scalar(@all), 3;
    isa_ok $all[0], 'My::Blog';
    isa_ok $all[1], 'My::Blog';
    isa_ok $all[2], 'My::Blog';

    # basic where
    $result = $ds->query('My::Blog')->where('{title} LIKE ?', '%blog')->select;
    @all = $result->as_list;
    is scalar(@all), 2;

    # aliases
    $result = $ds->query('My::Blog|b')->where('{b.id} > ?', 0)->select;
    @all = $result->as_list;
    is scalar(@all), 3;
    $ds->commit;

    # use sql abstract + interpolation of query identifiers!
    $result = $ds->query('My::Blog|b')->where({ '{b.id}' => { -in => [ 123 ] } })->select;
    @all = $result->as_list;
    is scalar(@all), 1;
    $ds->commit;

    # lazy and caching behavior of result classes
    @sql = ();
    is scalar(@sql), 0;
    $result = $ds->query('My::Blog|b')->select;
    is scalar(@sql), 0; # lazy
    @all = $result->as_list;
    is scalar(@all), 3;
    isa_ok $all[0], 'My::Blog';
    isa_ok $all[1], 'My::Blog';
    isa_ok $all[2], 'My::Blog';

    is scalar(@sql), 1; # just 1 query
    @all = $result->as_list; # should be cached by now
    is scalar(@all), 3;
    is scalar(@sql), 1; # just 1 query


    # ...

    # delete
    @sql = ();
    is Ormish::DataStore::of($b2), $ds;
    $ds->delete($b2);
    isnt Ormish::DataStore::of($b2), $ds;
    is Ormish::DataStore::of($b2), undef;

    is scalar(@sql), 0;

    $ds->flush;

    is scalar(@sql), 1;
    
    $ds->rollback;
    is Ormish::DataStore::of($b2), $ds;
        
    # aggregations
=pod
    @sql = ();
    my $c;
    my $stats;

    my $dst = $ds;

    # just count
    ($stats) = $dst->query('My::Blog')->select->as_columns({ count => 'COUNT(1)' });

    # or the whole bunch
    ($stats) = $dst->query('My::Blog')->select->as_columns({ count => 'COUNT(1)', min => 'MIN({id})', max => 'MAX({id})' })->as_list;
    is $c->{count}, 3;
    #$c = $dst->query('My::Blog')->select->count;
    #is $c, 3;
    #$c = $dst->query('My::Blog')->select->size;
    #is $c, 3;
=cut
    
}

ok 1;


__END__
:q
