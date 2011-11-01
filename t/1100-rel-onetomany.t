{
    package Music::Artist;
    use Moose;
    use namespace::autoclean;
    use Set::Object;
    has 'name'      => (is => 'rw', isa => 'Str', required => 1);
    has 'albums'    => (is => 'rw', isa => 'Set::Object', default => sub { Set::Object->new });
    __PACKAGE__->meta->make_immutable;
}
{
    package Music::Album;
    use Moose;
    use namespace::autoclean;
    has 'name'      => (is => 'rw', isa => 'Str', required => 1);
    has 'artist'    => (is => 'rw', isa => 'Music::Artist');
    __PACKAGE__->meta->make_immutable;
}

package main;
use strict;
use Test::More qw/no_plan/;
use Test::Exception;
use Scalar::Util qw/refaddr/;
use DBI;
use DBIx::Simple;
use Ormish;
use FindBin;
use lib "$FindBin::Bin/lib";


my $dbh = DBI->connect("DBI:SQLite:dbname=:memory:","","",{ RaiseError => 1, AutoCommit => 0 });
$dbh->do('CREATE TABLE artist (id INTEGER PRIMARY KEY, name VARCHAR)');
$dbh->do('CREATE TABLE album (id INTEGER PRIMARY KEY, name VARCHAR, artist_id INTEGER, 
            FOREIGN KEY (artist_id) REFERENCES artist (id))');
$dbh->commit;

my @sql = ();
my $ds = Ormish::DataStore->new( 
    engine          => Ormish::Engine::DBI->new( dbh => $dbh, log_sql => \@sql ), 
);

$ds->register_mapping( 
    [
        Ormish::Mapping->new(
            for_class       => 'Music::Artist',
            table           => 'artist',
            attributes      => [ qw/ name / ],
            oid             => Ormish::OID::Serial->new( attribute => 'id', install_attributes => 1 ),
            relations       => {
                albums          => Ormish::Relation::OneToMany->new( to_class => 'Music::Album' ),
            },
        ),
        Ormish::Mapping->new(
            for_class       => 'Music::Album',
            table           => 'album',
            attributes      => [ qw/ name artist|artist_id=id / ],
            oid             => Ormish::OID::Serial->new( attribute => 'id', install_attributes => 1 ),
            relations       => {
                artist          => Ormish::Relation::ManyToOne->new( to_class => 'Music::Artist' ),
            },
        ),
    ],
);

# ---
{
    @sql = ();
    my $mj = Music::Artist->new( name => 'Michael Jackson' );
    $mj->albums->insert( 
        Music::Album->new( name => 'Thriller' ),
        Music::Album->new( name => 'Off The Wall' ),
    );
    $ds->add($mj); # adds 3
    $ds->commit;
    is scalar(@sql), 3;

    @sql = ();
    my @albums = $mj->albums->members;
    is scalar(@albums), 2;
    ok 1;
}




ok 1;


__END__
