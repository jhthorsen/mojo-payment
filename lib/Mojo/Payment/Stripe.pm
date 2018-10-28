package Mojo::Payment::Stripe;
use Mojo::Base 'Mojo::Payment';

has public_key => sub { $ENV{MOJO_STRIPE_PUBLIC_KEY} || 'pk_test_not_set' };
has secret_key => sub { $ENV{MOJO_STRIPE_SECRET_KEY} || 'sk_test_not_set' };

our @CHARGE_CREATE_PARAMS
  = qw(application_fee customer destination fraud_details on_behalf_of receipt_email source statement_descriptor transfer_group);
our @CHARGE_LIST_PARAMS   = qw(customer ending_before limit starting_after transfer_group);
our @CHARGE_UPDATE_PARAMS = qw(customer description fraud_details receipt_email transfer_group);

sub charge_capture_p {
  my ($self, $charge_id) = @_;
  return $self->_reject('Parameter charge_id missing.') unless $charge_id;
  return $self->ua->post_p($self->_url_for('charges', $charge_id))
    ->then(sub { $self->_handle_res(shift) });
}

sub charge_create_p {
  my ($self, $args) = @_;
  my %form = (
    amount      => $args->{amount},
    currency    => $args->{currency} || $self->default_currency,
    description => $args->{description} || '',
  );

  return $self->_reject('Parameter amount missing.')   unless $form{amount};
  return $self->_reject('Parameter currency missing.') unless $form{currency};

  $form{$_} = $args->{$_} for grep { $args->{$_} } @CHARGE_CREATE_PARAMS;
  $self->_form_metadata($args => \%form);
  $self->_form_shipping($args => \%form);
  $form{amount} *= 100;
  $form{capture} = $args->{capture} ? 'true' : 'false' if exists $args->{capture};

  return $self->ua->post_p($self->_url_for('charges'), form => \%form)
    ->then(sub { $self->_handle_res(shift) });
}

sub charge_list_p {
  my ($self, $args) = @_;
  my $url = $self->_url_for('charges');
  my $q   = $url->query;

  $q->param($_ => $args->{$_}) for grep { $args->{$_} } @CHARGE_LIST_PARAMS;
  $self->_param_created($args, $q);

  return $self->ua->get_p($url)->then(sub { $self->_handle_res(shift) });
}

sub charge_retrieve_p {
  my ($self, $charge_id) = @_;

  return $self->_reject('Parameter charge_id missing.') unless $charge_id;
  return $self->ua->get_p($self->_url_for('charges', $charge_id))
    ->then(sub { $self->_handle_res(shift) });
}

sub charge_update_p {
  my ($self, $charge_id, $args) = @_;
  return $self->_reject('Parameter charge_id missing.') unless $charge_id;

  my %form;
  $form{$_} = $args->{$_} for grep { $args->{$_} } @CHARGE_UPDATE_PARAMS;
  $self->_form_metadata($args => \%form);
  $self->_form_shipping($args => \%form);

  return $self->ua->post_p($self->_url_for('charges', $charge_id), form => \%form)
    ->then(sub { $self->_handle_res(shift) });
}

sub _handle_res {
  my ($self, $tx) = @_;
  return $tx->res->json if $tx->res->code eq '200';
  return $self->_reject($tx->res->json || 'Unknown error.');
}

sub _form_metadata {
  my ($self, $args, $form) = @_;
  $form->{"metadata[$_]"} = $args->{metadata}{$_} for keys %{$args->{metadata} || {}};
}

sub _form_shipping {
  my ($self, $args, $form) = @_;

  # TODO
}

sub _param_created {
  my ($self, $args, $q) = @_;

  if (ref $args->{created} eq 'HASH') {
    $q->param("created[$_]" => $args->{created}{$_}) for keys %{$args->{created}};
  }
  elsif (defined $args->{created}) {
    $q->param(created => $args->{created});
  }
}

sub _tax_info {
  my ($self, $args, $form) = @_;
  my $tax_info = $args->{tax_info} or return;
  $form->{"tax_info[$_]"}{$_} = $tax_info->{$_} for keys %$tax_info;
}

sub _url_for {
  my ($self, @path) = @_;
  my $url = Mojo::URL->new('https://api.stripe.com/v1');
  push @{$url->path}, @path;
  $url->userinfo(sprintf '%s:', $self->secret_key);
}

1;

=encoding utf8

=head1 NAME

Mojo::Payment::Stripe - Payments using stripe.com

=head1 SYNOPSIS

  use Mojo::Payment::Stripe;

  my $stripe = Mojo::Payment::Stripe->new({
    public_key => "pk_test_abc",
    secret_key => "sk_test_xyz",
  });

=head1 DESCRIPTION

L<Mojo::Payment::Stripe> can create payments using L<https://stripe.com/> as
provider.

=head1 ATTRIBUTES

=head2 public_key

  $str = $self->public_key;
  $self = $self->public_key($str);

The public key you find in your stripe dashboard:
L<https://dashboard.stripe.com/account/apikeys>

Default to the C<MOJO_STRIPE_PUBLIC_KEY> environment variable.

=head2 secret_key

  $str = $self->secret_key;
  $self = $self->secret_key($str);

The secret key you find in your stripe dashboard:
L<https://dashboard.stripe.com/account/apikeys>

Default to the C<MOJO_STRIPE_SECRET_KEY> environment variable.

=head1 METHODS

=head2 charge_capture_p

  $promise = $self->charge_capture_p($charge_id, \%args);

See L<https://stripe.com/docs/api/charges/capture> for details.

=head2 charge_create_p

  $promise = $self->charge_create_p(\%args);

See L<https://stripe.com/docs/api/charges/create> for details.

=head2 charge_list_p

  $promise = $self->charge_update_p(\%args);

=head2 charge_retrieve_p

  $promise = $self->charge_update_p($charge_id);

=head2 charge_update_p

  $promise = $self->charge_update_p($charge_id, \%args);

See L<https://stripe.com/docs/api/charges/update> for details.

=head1 SEE ALSO

L<Mojo::Payment>

=cut
