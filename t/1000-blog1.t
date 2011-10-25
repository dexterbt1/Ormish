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
use DBI;
use Ormish;
use Test::More qw/no_plan/;

my $dbh = DBI->connect("DBI:SQLite:dbname=:memory:","","",{ RaiseError => 1, AutoCommit => 0 });
$dbh->do('CREATE TABLE blog_blog (id INTEGER PRIMARY KEY, name VARCHAR, title VARCHAR, tagline VARCHAR)');
$dbh->commit;

my @sql = ();
my $ds = Ormish::DataStore->new( dbh => $dbh, debug_log => \@sql );


{
    my $blog = My::Blog->new( name => 'ormish-blog' );
    ok not defined $blog->id;
    ok not defined Ormish::DataStore::of($blog);
    is scalar(@sql), 0;

    $ds->add( $blog );
    $ds->flush; # insert

    ok defined $blog->id;
    is Ormish::DataStore::of($blog), $ds;
    is scalar(@sql), 1;

    $blog->title('The Ormish Blog');
    $blog->tagline('an alternative object-relational persistence for moose objects');
    $ds->commit; # flush (update) and commit!
    is scalar(@sql), 2;

    #$blog->title('The Orcish Blog');
    #$ds->rollback;
    #my $blog2 = My::Blog->new( name => 'another blog', title => 'A Proper Title' );
    #$ds->add($blog2);
}

ok 1;


#my $blog2 = $st->query('My::Blog')->get(1); # by identity (pk)
#is $blog2->id, $blog->id;

ok 1;


__END__
