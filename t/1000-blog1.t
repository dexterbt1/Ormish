{
    package My::Blog;
    use Moose;
    has 'id'            => (is => 'rw', isa => 'Any'); # needed to contain the object identity
    has 'name'          => (is => 'rw', isa => 'Str', required => 1);
    has 'title'         => (is => 'rw', isa => 'Str');
    has 'tagline'       => (is => 'rw', isa => 'Str');
    
    use Ormish;
    sub _ORMISH_MAPPING {
        return Ormish::Mapping->new( 
            for_class       => __PACKAGE__,
            table           => 'blog_blog',
            oid             => Ormish::OID::Serial->new( column => 'id', attr => 'id' ),
            attributes      => [qw/name title tagline/],
        );
    }
    1;
}

package main;
use strict;
use Test::More qw/no_plan/;
use Scalar::Util qw/refaddr/;
use DBI;
use DBIx::Simple;
use Ormish;

my $dbh = DBI->connect("DBI:SQLite:dbname=:memory:","","",{ RaiseError => 1, AutoCommit => 0 });
$dbh->do('CREATE TABLE blog_blog (id INTEGER PRIMARY KEY, name VARCHAR, title VARCHAR, tagline VARCHAR)');
$dbh->commit;

my @sql = ();
my $ds = Ormish::DataStore->new( 
    engine      => Ormish::Engine::DBI->new( dbh => $dbh, log_sql => \@sql ), 
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

    my $blog2 = My::Blog->new( name => 'another blog', title => 'A Proper Title' );
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

    DBIx::Simple->new($dbh)->query(q{INSERT INTO blog_blog (id,name,title,tagline) VALUES (??)},
        123, 'SomeRandomBlog', 'Some Random Blog', '... nothing here, move along',
        );

    my $b2 = $ds->query('My::Blog')->get(123);
    isa_ok $b2, 'My::Blog';
    is Ormish::DataStore::of($b2), $ds;
    is $b2->id, 123;
    is $b2->name, 'SomeRandomBlog';
    is $b2->title, 'Some Random Blog';
    is $b2->tagline, '... nothing here, move along';
    is scalar(@sql), 3;

    $ds->add($b2);
    $ds->commit;
    is scalar(@sql), 3;

    
}

ok 1;


__END__

