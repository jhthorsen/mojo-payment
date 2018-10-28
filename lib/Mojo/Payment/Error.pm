package Mojo::Payment::Error;
use Mojo::Base 'Mojo::Exception';

has charge       => '';
has code         => 500;
has decline_code => '';
has doc_url      => '';
has message      => '';
has param        => '';
has type         => 'unknown';

sub new { shift->Mojo::Base::new(ref $_[1] eq 'HASH' ? shift : {message => shift}) }

1;

=encoding utf8

=head1 NAME

Mojo::Payment::Error - Payment errors

=head1 DESCRIPTION

L<Mojo::Payment::Error> is a sub class of L<Mojo::Exception> providing details
about a payment issue.

=head1 ATTRIBUTES

=head2 charge

=head2 code

=head2 decline_code

=head2 doc_url

=head2 message

=head2 param

=head2 type

=head1 METHODS

=head2 new

=head1 SEE ALSO

L<Mojo::Payment>

=cut
