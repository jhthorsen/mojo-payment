package Mojo::Payment::Paypal;
use Mojo::Base 'Mojo::Payment';

use JSON::Patch ();

use constant TOKEN_GRACE_TIME => $ENV{MOJO_PAYMENT_PAYPAL_TOKEN_GRACE_TIME} || 30;

our @CHARGE_LIST_PARAMS
  = qw(count end_time start_id payee_id sort_by sort_order start_index start_time);

has client_id => sub { $ENV{MOJO_PAYPAL_CLIENT_ID} || 'client_id_not_set' };
has mode      => sub { $ENV{MOJO_PAYPAL_MODE}      || 'sandbox' };
has redirect_urls  => sub { +{} };
has secret_key     => sub { $ENV{MOJO_PAYPAL_SECRET_KEY} || 'secret_key_not_set' };
has _access_tokens => sub { state $tokens = {} };

sub charge_capture_p {
  my ($self, $charge_id, $args) = @_;
  return $self->_reject('Parameter charge_id missing.') unless $charge_id;

  my %json;
  $json{$_} = $args->{$_} for grep { $args->{$_} } qw(payer_id transactions);

  return $self->_make_req_headers->then(sub {
    return $self->ua->post_p($self->_url(qw(payments payment), $charge_id, 'execute'),
      shift, json => \%json);
  })->then(sub { $self->_handle_res(shift) });
}

sub charge_create_p {
  my ($self, $args) = @_;
  my %json = (
    intent        => (defined $args->{capture} and !$args->{capture}) ? 'sale' : 'authorize',
    note_to_payer => $args->{note_to_payer} // $args->{description} // '',
    payer         => {payment_method => 'paypal'},
    redirect_urls => $args->{redirect_urls},
    transactions  => $args->{transactions},
  );

  $json{redirect_urls} ||= $self->redirect_urls if $self->redirect_urls;

  unless ($json{transactions}) {
    $json{transactions} = [{
      amount =>
        {currency => uc($args->{currency} || $self->default_currency), total => $args->{amount}},
      payee         => {email => $args->{email}, merchant_id => $args->{merchant_id}},
      custom        => $args->{custom} // $args->{description} // '',
      description   => $args->{description} // '',
      note_to_payee => $args->{note_to_payee} // $args->{note_to_payer} // $args->{description}
        // '',
      ($args->{invoice_number}  ? (invoice_number  => $args->{invoice_number})  : ()),
      ($args->{soft_descriptor} ? (soft_descriptor => $args->{soft_descriptor}) : ()),
    }];
  }

  my $i = 0;
  for my $t (@{$json{transactions}}) {
    return $self->_reject("Parameter /transactions/$i/amount/total missing.")
      unless $t->{amount}{total};
    return $self->_reject("Parameter /transactions/$i/amount/currency missing.")
      unless $t->{amount}{currency};
  }
  continue {
    $i++;
  }

  return $self->_make_req_headers->then(sub {
    return $self->ua->post_p($self->_url(qw(payments payment)), shift, json => \%json);
  })->then(sub { $self->_handle_res(shift) });
}

sub charge_list_p {
  my ($self, $args) = @_;
  my $url = $self->_url(qw(payments payment));
  my $q   = $url->query;

  $q->param($_ => $args->{$_}) for grep { $args->{$_} } @CHARGE_LIST_PARAMS;
  $q->param(count => $args->{limit}) if $args->{limit};

  return $self->_make_req_headers->then(sub { $self->ua->get_p($url, shift) })
    ->then(sub { $self->_handle_res(shift) });
}

sub charge_retrieve_p {
  my ($self, $charge_id) = @_;
  return $self->_reject('Parameter charge_id missing.') unless $charge_id;

  return $self->_make_req_headers->then(sub {
    return $self->ua->get_p($self->_url(qw(payments payment), $charge_id), shift);
  })->then(sub { $self->_handle_res(shift) });
}

sub charge_update_p {
  my ($self, $charge_id, $args) = @_;
  return $self->_reject('Parameter charge_id missing.') unless $charge_id;

  # Raw patch
  if (ref $args eq 'ARRAY') {
    return $self->_make_req_headers->then(sub {
      return $self->ua->patch_p($self->_url(qw(payments payment), $charge_id), shift,
        json => $args);
    })->then(sub { $self->_handle_res(shift) });
  }

  # Create patch by diffing input and existing data
  my @patch;
  return $self->charge_retrieve_p($charge_id)->then(sub {
    for my $d (@{JSON::Patch::diff(shift, $args)}) {
      push @patch, $d
        if $d->{op} eq 'add' and $d->{path} =~ m!/transactions/\d+/item_list/shipping_address!;
      push @patch, $d if $d->{op} eq 'replace';
    }
    return $self->_make_req_headers;
  })->then(sub {
    $self->ua->patch_p($self->_url(qw(payments payment), $charge_id), shift, json => \@patch);
  })->then(sub {
    $self->_handle_res(shift);
  });
}

sub _handle_res {
  my ($self, $tx) = @_;
  return $tx->res->json if $tx->res->is_success;
  return $self->_reject($tx->res->json || 'Unknown error.');
}

sub _make_req_headers {
  my $self = shift;

  my $token = $self->_access_tokens->{$self->client_id};
  return Mojo::Promise->new->resolve($token->{headers})
    if $token and time < $token->{expires_at} - TOKEN_GRACE_TIME;

  my @post_args = ($self->_url(qw(oauth2 token)));
  $post_args[0]->userinfo(sprintf '%s:%s', $self->client_id, $self->secret_key);
  push @post_args, {'Accept' => 'application/json', 'Accept-Language' => 'en_US'};
  push @post_args, form => {grant_type => 'client_credentials'};

  return $self->ua->post_p(@post_args)->then(sub {
    my $token = $self->_handle_res(shift);
    $self->_access_tokens->{$self->client_id} = $token;
    $token->{expires_at} ||= time + $token->{expires_in};
    $token->{headers}{'Authorization'} = join ' ', @$token{qw(token_type access_token)};
    $token->{headers}{'Content-Type'} = 'application/json';
    $token->{headers};
  });
}

sub _url {
  my ($self, @path) = @_;
  my $url = Mojo::URL->new(
    $self->mode eq 'sandbox' ? 'https://api.sandbox.paypal.com' : 'https://api.paypal.com');
  push @{$url->path}, 'v1', @path;
  return $url;
}

1;

=encoding utf8

=head1 NAME

Mojo::Payment::Paypal - Payments using paypal.com

=head1 SYNOPSIS

  use Mojo::Payment::Paypal;

  my $paypal = Mojo::Payment::Paypal->new({
    client_id  => "1234",
    secret_key => "s3cret",
    mode       => "live",
  });

=head1 DESCRIPTION

L<Mojo::Payment::Paypal> can create payments using L<https://paypal.com/> as
provider.

=head1 ATTRIBUTES

=head2 client_id

  $str = $self->client_id;
  $self = $self->client_id("1234")

The client ID you find in your paypal dashboard:
L<https://developer.paypal.com/developer/applications/>.

=head2 mode

  $str = $self->mode;
  $self = $self->mode("sandbox");

Should be either "sandbox" or "live". Defaults to "sandbox".

=head2 redirect_urls

  $hash_ref = $self->redirect_urls;
  $self = $self->redirect_urls({cancel_url => "...", return_url => "..."});

Where to redirect after the visitor has been on on the Paypal payment page.

=head2 secret_key

  $str = $self->secret_key;
  $self = $self->secret_key("s3cret")

The client ID you find in your paypal dashboard:
L<https://developer.paypal.com/developer/applications/>.

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
