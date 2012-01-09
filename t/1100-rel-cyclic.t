{
    package Node;
    use Moose;
    use namespace::autoclean;
    use Set::Object;
    has 'name'      => (is => 'rw', isa => 'Str', required => 1);
    has 'parent'    => (is => 'rw', isa => 'Node|Undef');
    has 'children'  => (is => 'rw', isa => 'Set::Object', default => sub { Set::Object->new });
    __PACKAGE__->meta->make_immutable;

    sub _ORMISH_MAPPING {
        Ormish::Mapping->new(
            for_class       => __PACKAGE__,
            table           => 'node',
            oid             => Ormish::Mapping::OID::Auto->new( attribute => 'id', install_attributes => 1 ),
            attributes      => [qw/ name parent|parent_id=id /],
            relations       => {
                parent          => Ormish::Mapping::Relation::ManyToOne->new( to_class => __PACKAGE__, reverse_relation => 'children' ),
                children        => Ormish::Mapping::Relation::OneToMany->new( to_class => __PACKAGE__, reverse_relation => 'parent' ),    
            },
        );
    }

}

package main;
use strict;
use Test::More qw/no_plan/;
use DBI;
use Ormish;

my $dbh = DBI->connect("DBI:SQLite:dbname=:memory:","","",{ RaiseError => 1, AutoCommit => 0 });
$dbh->do('CREATE TABLE node (id INTEGER PRIMARY KEY, name VARCHAR, parent_id INTEGER NULL,
            FOREIGN KEY (parent_id) REFERENCES node (id))');
$dbh->commit;

my @sql = ();
my $ds = Ormish::DataStore->new( 
    engine          => Ormish::Engine::DBI->new( dbh => $dbh, log_sql => \@sql ), 
);
$ds->register_mapping( Node::_ORMISH_MAPPING );

{
    @sql = ();
    my $root = Node->new( name => '/' );
    $ds->add($root);
    $ds->commit;
    is $root->parent, undef;
    is $root->children->size, 0;
    ok defined($root->id);

    @sql = ();
    $root->children->insert(
        Node->new( name => 'bin' ),
        Node->new( name => 'etc' ),
    );
    $ds->commit;
    is $root->children->size, 2;

    ok 1;

    # TODO: more later

}

ok 1;

__END__
