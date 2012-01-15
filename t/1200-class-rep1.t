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
use YAML;
use lib "$FindBin::Bin/lib";


my $dbh = DBI->connect("DBI:SQLite:dbname=:memory:","","",{ RaiseError => 1, AutoCommit => 0 });
$dbh->do('CREATE TABLE emp1 (id INTEGER PRIMARY KEY, emp_name VARCHAR, emp_start_date DATE)');
$dbh->commit;

my @sql = ();
my $ds1 = Ormish::DataStore->new( 
    engine          => Ormish::Engine::DBI->new( dbh => $dbh, log_sql => \@sql ), 
);

$ds1->register_mapping( 
    [
        Ormish::Mapping->new(
            for_class       => 'My::Employee',
            table           => 'emp1',
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
    my $steve = My::Employee->new(name => 'Steve Jobz', start_date => DateTime->new(year => 1971, month => 4, day => 1));
    $ds1->add($steve);
    $ds1->commit;

    # select
    ($o) = $ds1->query('My::Employee')->where('{name} LIKE ?', 'Steve%')->select_objects->list;
    is $o, $steve;
    is $o->start_date->year, 1971;
    is $o->start_date->month, 4;
    is $o->start_date->day, 1;

    # update
    $steve->name('Steve Jobs');
    $ds1->commit;

    $p = $ds1->query('My::Employee')->fetch( $steve->id );
    is $p, $steve;
    is $p->name, 'Steve Jobs';

    my $raskin = My::Employee->new(name => 'Jef Raskin', start_date => DateTime->new(year => 1978, month => 1, day => 1));
    $ds1->add($raskin);
    $ds1->commit;

    ($o) = $ds1->query('My::Employee')
               ->where('{start_date} > ?', 
                       [ 'start_date', DateTime->new(year => 1975, month => 1, day => 1) ], # hint bind type
                       )
               ->select_objects
               ->list
               ;
    is $o, $raskin;

    # steve died!
    $ds1->delete($steve);
    $ds1->commit;

    ok 1;
    #diag YAML::Dump(\@sql);
    is scalar(@sql), 6, 'complete sql count';

}
