{
    package My::Blog;
    use Moose;
    has 'id'            => (is => 'rw', isa => 'Any'); # needed to contain the object identity
    has 'name'          => (is => 'rw', isa => 'Str', required => 1);
    has 'title'         => (is => 'rw', isa => 'Str');
    has 'tagline'       => (is => 'rw', isa => 'Str');
    
    use Ormish;
    sub _DEFAULT_MAPPING {
        return Ormish::Mapping->new( 
            for_class       => __PACKAGE__,
            table           => 'blog_blog',
            oid             => Ormish::OID::Serial->new( column => 'id', attr => 'id' ),
            attributes      => [qw/name title tagline/],
            # ---
            # reader          => Ormish::Mapping::Read::Table->new( from => 'blog_blog' ),
            # writer          => Ormish::Mapping::Write::Table->new( to => 'blog_blog' ),
            # ---
            # reader          => Ormish::Mapping::Read::MultiTable( from => [qw//]
            # writer          => Ormish::Mapping::Write::MultiTable( to => { 'table1' => [ ], 'table2' => [ ] } )
        );
    }
    1;
}

package main;
use strict;
use DBI;
use Ormish;
use Test::More qw/no_plan/;

my $dbh = DBI->connect("DBI:SQLite:dbname=:memory:","","",{ RaiseError => 1 });
$dbh->do('CREATE TABLE blog_blog (id INTEGER PRIMARY KEY, name VARCHAR, title VARCHAR, tagline VARCHAR)');

my @sql = ();
my $ds = Ormish::DataStore->new( dbh => $dbh, debug_log => \@sql );

$ds->register_mapping( My::Blog::_DEFAULT_MAPPING );

{
    my $blog = My::Blog->new( name => 'Test' );
    ok not defined $blog->id;
    ok not defined Ormish::DataStore::of($blog);
    is scalar(@sql), 0;

    $ds->add( $blog );
    $ds->flush;

    ok defined $blog->id;
    is Ormish::DataStore::of($blog), $ds;
    is scalar(@sql), 1;

    $blog->title('Shiny New Blog');
    $ds->flush;
    is scalar(@sql), 2;
}

ok 1;


#my $blog2 = $st->query('My::Blog')->get(1); # by identity (pk)
#is $blog2->id, $blog->id;

ok 1;


__END__
