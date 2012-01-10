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
    has 'artist'    => (is => 'rw', isa => 'Music::Artist', required => 1);
    __PACKAGE__->meta->make_immutable;
}

package main;
use strict;
use Test::More qw/no_plan/;
use DBI;
use DBIx::Simple;
use Set::Object;
use Ormish;
use FindBin;
use lib "$FindBin::Bin/lib";


my $dbh = DBI->connect("DBI:SQLite:dbname=:memory:","","",{ RaiseError => 1, AutoCommit => 0 });
$dbh->do('CREATE TABLE artist (id INTEGER PRIMARY KEY, name VARCHAR, UNIQUE (name))');
$dbh->do('CREATE TABLE album (id INTEGER PRIMARY KEY, name VARCHAR, artist_id INTEGER NOT NULL, UNIQUE (name), 
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
            oid             => Ormish::Mapping::OID::Auto->new( attribute => 'id', install_attributes => 1 ),
            relations       => {
                albums          => Ormish::Mapping::Relation::OneToMany->new( to_class => 'Music::Album' ),
            },
        ),
        Ormish::Mapping->new(
            for_class       => 'Music::Album',
            table           => 'album',
            attributes      => [ qw/ name artist:artist_id=id / ],
            oid             => Ormish::Mapping::OID::Auto->new( attribute => 'id', install_attributes => 1 ),
            relations       => {
                artist          => Ormish::Mapping::Relation::ManyToOne->new( to_class => 'Music::Artist' ),
            },
        ),
    ],
);

# ---

{
    @sql = ();
    my $mj = Music::Artist->new( name => 'Michael Jackson' );
    $ds->add($mj);
    $ds->commit;
    isnt $mj->id, undef;

    @sql = ();
    my $bad = Music::Album->new( name => 'Bad', artist => $mj );
    $ds->add($bad);
    $ds->commit;
    ok defined $bad->id;
    like $sql[0][0], qr/^insert/i;

    is $mj->albums->size, 1;

    @sql = ();
    my $thriller = Music::Album->new( name => 'Thriller', artist => $mj );
    $ds->add($thriller);
    $ds->commit;
    is $mj->albums->size, 2;
    
    
    $mj->albums->insert( Music::Album->new( name => 'Dangerous', artist => $mj ) );
    $ds->commit;
    is $mj->albums->size, 3;
    
    @sql = ();
    $mj->albums->insert( Music::Album->new( name => 'Got To Be There', artist => Music::Artist->new( name => 'Unknown' ) ) );
    $ds->commit;
    is scalar(@sql), 2;
    like $sql[0][0], qr/^insert/i;
    like $sql[1][0], qr/^insert/i;
    is $mj->albums->size, 4;

    

    ok 1;
    ok 1;

}


__END__

