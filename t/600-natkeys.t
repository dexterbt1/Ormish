{
    package Person;
    use Moose;
    has 'ssn'               => (is => 'rw', isa => 'Str', required => 1);
    has 'name'              => (is => 'rw', isa => 'Str', required => 1);
    
    use Ormish;
    sub _ORMISH_MAPPING {
        return Ormish::Mapping->new( 
            for_class           => __PACKAGE__,
            table               => 'person',
            oid                 => Ormish::OID::Natural->new( attribute => 'ssn' ),
            attributes          => [qw/ 
                ssn|soc_sec_num 
                name 
            /],
        );
    }
    1;
}

package main;
use strict;
use Test::More qw/no_plan/;
use Scalar::Util qw/refaddr/;
use YAML;
use DBI;
use DBIx::Simple;
use Ormish;

my $dbh = DBI->connect("DBI:SQLite:dbname=:memory:","","",{ RaiseError => 1, AutoCommit => 0 });
$dbh->do('CREATE TABLE person (soc_sec_num VARCHAR, name VARCHAR, PRIMARY KEY (soc_sec_num))');
$dbh->commit;

my @sql = ();
my $ds = Ormish::DataStore->new( 
    engine      => Ormish::Engine::DBI->new( dbh => $dbh, log_sql => \@sql ), 
    auto_map    => 1,
);

{
    # insert
    my $o;
    my $p;

    $o = Person->new(ssn => '111-111-1111', name => 'John Doe');
    ok defined $o->ssn;
    ok not defined Ormish::DataStore::of($o);
    $ds->add($o);
    ok defined Ormish::DataStore::of($o);
    $ds->commit;
    diag Dump(\@sql);
    is scalar(@sql), 1;
    
    @sql = ();

    $p = $ds->query('Person')->get('111-111-1111');
    is $p, $o;
    $p->name('John X. Doe');
    $ds->commit;
    diag Dump(\@sql);
    is scalar(@sql), 2;

    @sql = ();

    # change ssn, twice, and still do it correctly
    $p->ssn('111-222-1111');
    $p->ssn('111-222-1234');
    $ds->commit;
    diag Dump(\@sql);
    is scalar(@sql), 1;
    is $p->ssn, '111-222-1234';

    @sql = ();

    # change ssn, twice, and still do it correctly
    $p->ssn('111-222-1111');
    $p->ssn('111-111-1111');
    $ds->rollback;
    is scalar(@sql), 0;
    is $p->ssn, '111-222-1234';
    
}



ok 1;

__END__