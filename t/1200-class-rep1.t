{
    # from the book Pro JPA 2 - Class Rep p.5
    package My::Employee;
    use Moose;
    use namespace::autoclean;
    use DateTime;

    has 'id'            => (is => 'rw', isa => 'Int');
    has 'name'          => (is => 'rw', isa => 'Str');
    has 'start_date'    => (is => 'rw', isa => 'DateTime');

    __PACKAGE__->meta->make_immutable;
}

package main;
use strict;
use Test::More qw/no_plan/;
use DBI;
use DateTime::Format::SQLite;
use Ormish;
use Ormish::Mapping::Hook::AttributeColumns;
use FindBin;
use lib "$FindBin::Bin/lib";


my $dbh = DBI->connect("DBI:SQLite:dbname=:memory:","","",{ RaiseError => 1, AutoCommit => 0 });
$dbh->do('CREATE TABLE emp (id INTEGER PRIMARY KEY, emp_name VARCHAR, emp_start_date DATE)');
$dbh->commit;

my @sql = ();
my $ds = Ormish::DataStore->new( 
    engine          => Ormish::Engine::DBI->new( dbh => $dbh, log_sql => \@sql ), 
);

$ds->register_mapping( 
    [
        Ormish::Mapping->new(
            for_class       => 'My::Employee',
            table           => 'emp',
            oid             => Ormish::Mapping::OID::Auto->new( attribute => 'id' ),
            hooks           => [
                Ormish::Mapping::Hook::AttributeColumns->new(
                    attr_to_col => {
                        id              => 'id', 
                        name            => 'emp_name', 
                    },
                ),
                Ormish::Mapping::Hook::AttributeColumns->new(
                    attr_to_col => {
                        start_date      => 'emp_start_date', 
                    },
                    pack        => sub { DateTime::Format::SQLite->format_date($_[0]) },
                    unpack      => sub { DateTime::Format::SQLite->parse_date($_[0]) },
                ),
            ],
        ),
    ]
);

# ---
{
    # CRUD tests
    ok 1;
    my ($o, $p);

    # insert
    my $steve = My::Employee->new(name => 'Steve Jobz', start_date => DateTime->new(year => 1971, month => 4, day => 1), );
    $ds->add($steve);
    $ds->commit;

    # select
    ($o) = $ds->query('My::Employee')->where('{name} LIKE ?', 'Steve%')->select_objects->list;
    is $o, $steve;
    is $o->start_date->year, 1971;
    is $o->start_date->month, 4;
    is $o->start_date->day, 1;

    # update
    $steve->name('Steve Jobs');
    $ds->commit;

    ($p) = $ds->query('My::Employee')->where('{name} LIKE ?', 'Steve%')->select_objects->list;
    is $p, $steve;
    


    ok 1;
}
