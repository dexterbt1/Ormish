package Ormish::OID::Serial;
use Moose;
use Ormish::OID::BaseRole;
with 'Ormish::OID::BaseRole';

has 'column'    => (is => 'rw', isa => 'Str', required => 1);
has 'attr'      => (is => 'rw', isa => 'Str', lazy => 1, default => 'id');

sub as_str {
    my ($self, $obj) = @_;
    my $attr = $obj->meta->get_attribute($self->attr);
    return $attr->get_value($obj);
}

sub set_object_identity {
    my ($self, $obj, $auto_id) = @_;
    my $attr = $obj->meta->get_attribute($self->attr);
    $attr->set_value($obj, $auto_id);
}


1;

__END__
