use strict;
use Test::More qw/no_plan/;
use Scalar::Util qw/refaddr/;
use DBI;
use DBIx::Simple;
use Ormish;
use FindBin;
use lib "$FindBin::Bin/lib";
use MyBlog::Models;

my $dbh = DBI->connect("DBI:SQLite:dbname=:memory:","","",{ RaiseError => 1, AutoCommit => 0 });
MyBlog::Models->deploy_schema($dbh);

my @sql = ();
my $ds = Ormish::DataStore->new( 
    engine          => Ormish::Engine::DBI->new( dbh => $dbh, log_sql => \@sql ), 
    auto_register   => 1,
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
    is scalar(@sql), 1;
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
    
    my $b1 = $ds->query('My::Blog')->fetch($blog->id); # by oid
    is $b1, $blog; # string 'eq' comparison
    is refaddr($b1), refaddr($blog);
    is scalar(@sql), 1; # insert only, fetch retrieves from the identitymap
    is Ormish::DataStore::of($b1), $ds;

    # update and flush, 
    $b1->title($b1->title);
    $ds->commit;
    {
        # make sure that single object updates affects only the oids concerned
        my $bx = $ds->query("My::Blog")->fetch($b1->id);
        is $bx, $b1;
        is $b1, $blog;
        isnt $b1, $blog2;
        isnt $b1->title, $blog2->title;
        # and be paranoid, check the db that indeed only 
        my @affected = DBIx::Simple->new($dbh)->query("SELECT * FROM blog_blog WHERE title=?", $b1->title)->arrays();
        is scalar(@affected), 1;
    }

    # quick and dirty insert for now, ideally the dbh should not be shared, to avoid race conditions / conflicts
    DBIx::Simple->new($dbh)->query(q{INSERT INTO blog_blog (b_id,name,title,c_tag_line) VALUES (??)},
        123, 'some-random-blog', 'Some Random Blog', '... nothing here, move along',
        );

    @sql = ();
    my $b2 = $ds->query('My::Blog')->fetch(123);
    is scalar(@sql), 1;
    isa_ok $b2, 'My::Blog';
    is Ormish::DataStore::of($b2), $ds;
    is $b2->id, 123;
    is $b2->name, 'some-random-blog';
    is $b2->title, 'Some Random Blog';
    is $b2->tagline, '... nothing here, move along';
    is scalar(@sql), 1;

    $ds->add($b2);
    is scalar(@sql), 1; # no effect, no queries issued
    $ds->commit;
    is scalar(@sql), 1; # no effect, no queries issued

    # --- query result

    my $c;
    my $q;
    my $result;
    my @all;

    # iterator interface

    @sql = ();
    $result = $ds->query('My::Blog')->select_objects; # hold that query until iteration time
    is scalar(@sql), 0;
    while (my $b = $result->next) {
        isa_ok $b, 'My::Blog';
        $c++;
    }
    is $c, 3;
    is scalar(@sql), 1;

    # pull all objects into memory as a list
    $result = $ds->query('My::Blog')->select_objects;
    @all = $result->list;
    is scalar(@all), 3;
    isa_ok $all[0], 'My::Blog';
    isa_ok $all[1], 'My::Blog';
    isa_ok $all[2], 'My::Blog';

    # basic where
    $result = $ds->query('My::Blog')->where('{title} LIKE ?', '%blog')->select_objects;
    @all = $result->list;
    is scalar(@all), 2;

    # aliases
    $result = $ds->query('My::Blog|b')->where('{b.id} > ?', 0)->select_objects;
    @all = $result->list;
    is scalar(@all), 3;
    $ds->commit;

    # use sql abstract + interpolation of query identifiers!
    $result = $ds->query('My::Blog|b')->where({ '{b.id}' => { -in => [ 123 ] } })->select_objects;
    @all = $result->list;
    is scalar(@all), 1;
    $ds->commit;

    # lazy and caching behavior of result classes
    @sql = ();
    is scalar(@sql), 0;
    $result = $ds->query('My::Blog|b')->select_objects;
    is scalar(@sql), 0; # lazy
    @all = $result->list;
    is scalar(@all), 3;
    isa_ok $all[0], 'My::Blog';
    isa_ok $all[1], 'My::Blog';
    isa_ok $all[2], 'My::Blog';

    is scalar(@sql), 1; # just 1 query
    @all = $result->list; # should be cached by now
    is scalar(@all), 3;
    is scalar(@sql), 1; # just 1 query

    # overloaded dereferencing as arrayref @{}
    @all = @$result; # should be cached by now
    is scalar(@sql), 1; # just 1 query
    is scalar(@all), 3;

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
        
    # aggregation
    @sql = ();
    my $c;
    my $stats;

    my $dst = $ds;

    # just count
    ($stats) = $dst->query('My::Blog')->select_rows('COUNT(1)|c')->list;
    is $stats->{c}, 3;
    is scalar(@sql), 1;
    @sql = ();

    # or the whole bunch, and aliased
    ($stats) = $dst->query('My::Blog|b')->select_rows('COUNT(1)|count', 'MIN({b.id})|min', 'MAX({b.id})|max_id')->list;
    is $stats->{count}, 3;
    is $stats->{min}, 1;
    is $stats->{max_id}, 123;
    is scalar(@sql), 1;
    $ds->commit;
    
}

{
    # --- relation tests
    @sql = ();

    my $b = $ds->query('My::Blog')->fetch(1); # reuse existing, should have been cached as the ds is not yet dead
    isa_ok $b, 'My::Blog';
    is scalar(@sql), 0;
    isa_ok $b->posts, 'Set::Object';

    my $fp = My::Post->new( title => 'first post!' ); 

    $b->posts->insert( $fp );
    is scalar(@sql), 0; # lazy insert

    $ds->commit;
    is scalar(@sql), 1; 
    isnt $fp->id, undef;
    is $fp->parent_blog, $b;

    @sql = ();
    my $b2 = $ds->query('My::Blog')->fetch(123); 
    isa_ok $b2, 'My::Blog';
    $fp->parent_blog($b2);
    $ds->commit;
    is scalar(@sql), 1;


}



ok 1;


__END__

