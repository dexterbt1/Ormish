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
my $st = Ormish::Store->new( dbh => $dbh, debug_log => \@sql );

$st->register_mapping( My::Blog::_DEFAULT_MAPPING );

my $blog = My::Blog->new( name => 'Test' );
ok not defined $blog->id;
ok not defined Ormish::Store::of($blog);
is scalar(@sql), 0;

$st->add( $blog );
$st->flush;

ok defined $blog->id;
is Ormish::Store::of($blog), $st;
is scalar(@sql), 1;

#$blog->title('Shiny New Blog');
#$st->flush;
#is scalar(@sql), 2;


#my $blog2 = $st->query('My::Blog')->get(1); # by identity (pk)
#is $blog2->id, $blog->id;

ok 1;


__END__
