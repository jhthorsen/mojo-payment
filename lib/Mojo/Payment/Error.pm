package Mojo::Payment::Error;
use Mojo::Base 'Mojo::Exception';

has code         => 500;
has decline_code => '';
has details      => sub { +[] };
has doc_url      => '';
has id           => '';
has message      => '';
has param        => '';
has type         => 'unknown';

sub new {
  my $self = shift->Mojo::Base::new(ref $_[0] eq 'HASH' ? shift : {message => shift});

  $self->doc_url(delete $self->{information_link})  if $self->{information_link};     # Paypal
  $self->id(delete $self->{charge})                 if $self->{charge};               # Stripe
  $self->id(delete $self->{debug_id})               if $self->{debug_id};             # Paypal
  $self->message(delete $self->{error_description}) if $self->{error_description};    # Paypal
  $self->type(delete $self->{error})                if $self->{error};                # Paypal
  $self->type(delete $self->{name})                 if $self->{name};                 # Paypal
  $self;
}

sub to_string {
  my $self = shift;
  sprintf '[%s/%s] %s', $self->type, $self->id, $self->message;
}

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

=head2 to_string

=head1 SEE ALSO

L<Mojo::Payment>

=cut
