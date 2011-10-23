package Ormish;

use warnings;
use strict;

our $VERSION = '0.1000';

use Ormish::DataStore;
use Ormish::Mapping;
use Ormish::OID::Serial;

1; # End of Ormish

__END__

=head1 NAME

Ormish - an alternative object relational mapper

=head1 SYNOPSIS

    use Ormish;

    my $foo = Ormish->new();
    ...

=head1 AUTHOR

Dexter Tad-y, C<< <dtady at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-ormish at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Ormish>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Ormish


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Ormish>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Ormish>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Ormish>

=item * Search CPAN

L<http://search.cpan.org/dist/Ormish/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2011 Dexter Tad-y.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See http://dev.perl.org/licenses/ for more information.


=cut

