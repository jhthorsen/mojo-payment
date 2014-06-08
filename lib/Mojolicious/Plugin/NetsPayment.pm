package Mojolicious::Plugin::NetsPayment;

=head1 NAME

Mojolicious::Plugin::NetsPayment - Make payments using Nets

=head1 VERSION

0.01

=head1 DESCRIPTION

L<Mojolicious::Plugin::NetsPayment> is a plugin for the L<Mojolicious> web
framework which allow you to do payments using L<http://www.betalingsterminal.no|Nets>.

This module is EXPERIMENTAL. The API can change at any time. Let me know
if you are using it.

=head1 SYNOPSIS

  use Mojolicious::Lite;

  plugin NetsPayment => {
    merchant_id => '...',
    token => '...',
  };

  # register a payment and send the visitor to Nets payment terminal
  post '/checkout' => sub {
    my $self = shift->render_later;
    my %payment = (
      amount => scalar $self->param('amount'),
      order_number => scalar $self->param('order_number'),
    );

    Mojo::IOLoop->delay(
      sub {
        my ($delay) = @_;
        $self->nets(register => \%payment, $delay->begin);
      },
      sub {
        my ($delay, $res) = @_;
        return $self->render(text => "Ooops!", status => $res->code) unless $res->code == 302;
        # store $res->param('transaction_id');
        $self->redirect_to($res->headers->location);
      },
    );
  };

  # after redirected back from Nets payment terminal
  get '/checkout' => sub {
    my $self = shift->render_later;

    Mojo::IOLoop->delay(
      sub {
        my ($delay) = @_;
        $self->nets(process => {}, $delay->begin);
      },
      sub {
        my ($delay, $res) = @_;
        return $self->render(text => $res->error->{message}, status => $res->code) unless $res->code == 200;
        # store $res->param('transaction_id') and $res->param('authorization_id');
        $self->render(text => "yay!");
      },
    );
  };

  app->start;

=head1 ENVIRONMENT VARIABLES

=head2 MOJO_NETS_DEBUG

Get extra debug output to STDERR.

=head2 MOJO_NETS_SELF_CONTAINED

Set this environment variable to a true value and this module will try to
replicate the behavior of Nets. This is especially useful when writing
unit tests.

To mimic Nets behavior, it will add these routes to your application:

=over 4

=item * /nets/Netaxept/Process.aspx

L<http://www.betalingsterminal.no/Netthandel-forside/Teknisk-veiledning/API/Process/>.

=item * /nets/Netaxept/Query.aspx

L<http://www.betalingsterminal.no/Netthandel-forside/Teknisk-veiledning/API/Query/>.

=item * /nets/Netaxept/Register.aspx

L<http://www.betalingsterminal.no/Netthandel-forside/Teknisk-veiledning/API/Register/>.

=item * /nets/Terminal/default.aspx

L<http://www.betalingsterminal.no/Netthandel-forside/Teknisk-veiledning/Terminal/>.

=back

=head1 SEE ALSO

=over 4

=item * Overview

L<http://www.betalingsterminal.no/Netthandel-forside/Teknisk-veiledning/Overview/>

=item * API

L<http://www.betalingsterminal.no/Netthandel-forside/Teknisk-veiledning/API/>

=back

=cut

use Mojo::Base 'Mojolicious::Plugin';
use Mojo::UserAgent;
use constant DEBUG => $ENV{MOJO_NETS_DEBUG} || 0;

our $VERSION = '0.01';

=head1 ATTRIBUTES

=head2 base_url

  $str = $self->base_url;

This is the location to Nets payment solution. Will be set to
L<https://epayment.nets.eu> if the mojolicious application mode is
"production" or L<https://test.epayment.nets.eu> if not.

=head2 currency_code

  $str = $self->currency_code;

The currency code, following ISO 4217. Default is "NOK".

=head2 merchant_id

  $str = $self->merchant_id;

The value for the merchant ID, can be found in the Nets admin gui.

=head2 token

  $str = $self->token;

The value for the merchant ID, can be found in the Nets admin gui.

=cut

has currency_code => 'NOK';
has merchant_id => 'dummy_merchant';
has token => 'dummy_token';
has base_url => 'https://test.epayment.nets.eu';
has _ua => sub { Mojo::UserAgent->new; };

=head1 HELPERS

=head2 nets

  $self = $c->nets;
  $c = $c->nets($method => @args);

Returns this instance unless any args have been given or calls one of the
avaiable L</METHODS> instead. C<$method> need to be without "_payment" at
the end. Example:

  $c->nets(register => { ... }, sub {
    my ($c, $res) = @_;
    # ...
  });

=head1 METHODS

=head2 process_payment

  $self = $self->process_payment(
    $c,
    {
      transaction_id => $str, # default to $c->param("transactionId")
      operation => $str, # default to AUTH
      # ...
    },
    sub {
      my ($self, $res) = @_;
    },
  );

From L<http://www.betalingsterminal.no/Netthandel-forside/Teknisk-veiledning/API/Process/>:

  All financial transactions are encapsulated by the "Process"-call.
  Available financial transactions are AUTH, SALE, CAPTURE, CREDIT
  and ANNUL.

=cut

sub process_payment {
  my ($self, $c, $args, $cb) = @_;
  my $process_url = $self->_url('/Netaxept/Process.aspx');

  $args = { transaction_id => $args } unless ref $args;
  $args->{operation} ||= 'AUTH';
  $args->{transaction_id} ||= $c->param('transactionId') or return $self->$cb($self->_error('transaction_id missing in input'));

  $process_url->query({
    merchantId    => $self->merchant_id,
    token         => $self->token,
    operation     => $args->{operation} || 'AUTH',
    transactionId => $args->{transaction_id},
    $self->_camelize($args),
  });

  Mojo::IOLoop->delay(
    sub {
      my ($delay) = @_;
      $self->_ua->get($process_url, $delay->begin);
    },
    sub {
      my ($delay, $tx) = @_;
      my $res = $tx->res;

      $res->code(0) unless $res->code;

      eval {
        my $body = $res->dom->ProcessResponse;
        my $code = $body->ResponseCode->text;

        $res->param(code => $code);

        if($code eq 'OK') {
          $res->param(transaction_id => $body->TransactionId->text);
          $res->param(authorization_id => $body->AuthorizationId->text);
          $res->code(200);
        }
        else {
          $res->param(message => $body->ResponseText->text);
          $res->param(source => $body->ResponseSource->text);
          $res->code(500) if $res->code == 200;
        }
        1;
      } or do {
        warn "[MOJO_NETS] ! $@" if DEBUG;
        my $err = $res->error || {};
        $res->code(500);
        $res->error({
          advice => $err->{advice} || 0,
          message => $self->_extract_error($tx) || $err->{message} || 'Unknown error',
        });
      };

      $self->$cb($res);
    },
  );

  $self;
}

=head2 query_payment

  $self = $self->query_payment(
    $c,
    {
      transaction_id => $str,
    },
    sub {
      my ($self, $res) = @_;
    },
  );

From L<http://www.betalingsterminal.no/Netthandel-forside/Teknisk-veiledning/API/Query/>:

  To check the status of a transaction at any time, you can use the Query-call.

=cut

sub query_payment {
  my ($self, $c, $args, $cb) = @_;
  my $query_url = $self->_url('/Netaxept/Query.aspx');

  $args = { transaction_id => $args } unless ref $args;
  $args->{transaction_id} or return $self->$cb($self->_error('transaction_id missing in input'));

  $query_url->query({
    merchantId    => $self->merchant_id,
    token         => $self->token,
    transactionId => $args->{transaction_id},
  });

  Mojo::IOLoop->delay(
    sub {
      my ($delay) = @_;
      $self->_ua->get($query_url, $delay->begin);
    },
    sub {
      my ($delay, $tx) = @_;
      my $res = $tx->res;

      $res->code(0) unless $res->code;

      eval {
        my $body = $res->dom->QueryResponse;

        $res->param(
            amount          => $body->Amount->text / 100,
            amount_captured => $body->AmountCaptured->text,
            amount_credited => $body->AmountCredited->text,
            annulled        => $body->Annulled->text,
            authorized      => $body->Authorized->text,
            currency_code   => $body->Currency->text,
            fee             => $body->Fee->text / 100,
            order_number    => $body->OrderNumber->text,
            total           => $body->Total->text / 100,

            authorization_id      => eval { $body->AuthorizationId->text },
            customer_address1     => eval { $body->Address1->text },
            customer_address2     => eval { $body->Address2->text },
            customer_country      => eval { $body->Country->text },
            customer_email        => eval { $body->Email->text },
            customer_first_name   => eval { $body->FirstName->text },
            customer_ip           => eval { $body->IP->text },
            customer_last_name    => eval { $body->LastName->text },
            customer_number       => eval { $body->CustomerNumber->text },
            customer_phone_number => eval { $body->PhoneNumber->text },
            customer_postcode     => eval { $body->Postcode->text },
            eci                   => eval { $body->ECI->text },
            expiry_date           => eval { $body->ExpiryDate->text },
            issuer_country        => eval { $body->IssuerCountry->text },
            issuer_id             => eval { $body->IssuerId->text },
            order_description     => eval { $body->OrderDescription->text },
            pan                   => eval { $body->MaskedPan->text },
            payment_method        => eval { $body->PaymentMethod->text },
            status                => eval { $body->AuthenticatedStatus->text },
        );
        1;
      } or do {
        warn "[MOJO_NETS] ! $@" if DEBUG;
        my $err = $res->error || {};
        $res->code(500);
        $res->error({
          advice => $err->{advice} || 0,
          message => $self->_extract_error($tx) || $err->{message} || 'Unknown error',
        });
      };

      $self->$cb($res);
    },
  );

  $self;
}

=head2 register_payment

  $self = $self->register_payment(
    $c,
    {
      amount => $num, # 99.90, not 9990
      order_number => $str,
      redirect_url => $str, # default to current request URL
      # ...
    },
    sub {
      my ($self, $res) = @_;
    },
  );

From L<http://www.betalingsterminal.no/Netthandel-forside/Teknisk-veiledning/API/Register/>:

  The purpose of the register call is to send all the data needed to
  complete a transaction to Netaxept servers. The input data is
  organized into a RegisterRequest, and the output data is formatted
  as a RegisterResponse.

NOTE: "amount" in this API need to be a decimal number, which will be duplicated with 100 to match
the Nets documentation.

There are many more options that can be passed on to L</register_payment>.
Look at L<http://www.betalingsterminal.no/Netthandel-forside/Teknisk-veiledning/API/Register/>
for a complete list. CamelCase arguments can be given in normal form. Examples:

  # NetsDocumentation   | perl_argument_name
  # --------------------|----------------------
  # currencyCode        | currency_code
  # customerPhoneNumber | customer_phone_number

=cut

sub register_payment {
  my ($self, $c, $args, $cb) = @_;
  my $register_url = $self->_url('/Netaxept/Register.aspx');

  $args->{amount}       or return $self->$cb($self->_error('amount missing in input'));
  $args->{order_number} or return $self->$cb($self->_error('order_number missing in input'));
  local $args->{amount} = $args->{amount} * 100;
  local $args->{redirect_url} ||= $c->req->url->to_abs;

  $register_url->query({
    currencyCode        => $self->currency_code,
    merchantId          => $self->merchant_id,
    token               => $self->token,
    environmentLanguage => 'perl',
    OS                  => $^O || 'Mojolicious',
    $self->_camelize($args),
  });

  Mojo::IOLoop->delay(
    sub {
      my ($delay) = @_;
      $self->_ua->get($register_url, $delay->begin);
    },
    sub {
      my ($delay, $tx) = @_;
      my $res = $tx->res;

      $res->code(0) unless $res->code;

      eval {
        my $id = $res->dom->RegisterResponse->TransactionId->text;
        my $terminal_url = $self->_url('/Terminal/default.aspx')->query({merchantId => $self->merchant_id, transactionId => $id});

        $res->headers->location($terminal_url);
        $res->param(transaction_id => $id);
        $res->code(302);
        1;
      } or do {
        warn "[MOJO_NETS] ! $@" if DEBUG;
        my $err = $res->error || {};
        $res->code(500);
        $res->error({
          advice => $err->{advice} || 0,
          message => $self->_extract_error($tx) || $err->{message} || 'Unknown error',
        });
      };

      $self->$cb($res);
    },
  );

  $self;
}

=head2 register

  $app->plugin(NetsPayment => \%config);

Called when registering this plugin in the main L<Mojolicious> application.

=cut

sub register {
  my ($self, $app, $config) = @_;

  # copy config to this object
  $self->{$_} = $config->{$_} for grep { $self->$_ } keys %$config;
  $self->_add_routes($app) if $ENV{MOJO_NETS_SELF_CONTAINED};

  $app->helper(
    nets => sub {
      my $c = shift;
      return $self unless @_;
      my $method = shift .'_payment';
      $self->$method($c, @_);
      return $c;
    }
  );
}

sub _add_routes {
  my ($self, $app) = @_;
  my $r = $app->routes;
  my $payments = $self->{payments} ||= {}; # just here for debug purposes, may change without warning

  $self->base_url('/nets');

  $r->get('/nets/Netaxept/Process.aspx')->to(cb => sub {
    shift->render('nets/Netaxept/Process', format => 'aspx');
  });
  $r->get('/nets/Netaxept/Query.aspx')->to(cb => sub {
    shift->render('nets/Netaxept/Query', format => 'aspx');
  });
  $r->get('/nets/Netaxept/Register.aspx')->to(cb => sub {
    my $self = shift;
    my $txn_id = 'b127f98b77f741fca6bb49981ee6e846';
    $payments->{$txn_id} = $self->req->query_params->to_hash;
    $self->render('nets/Netaxept/Register', txn_id => $txn_id, format => 'aspx');
  });
  $r->get('/nets/Terminal/default.aspx')->to(cb => sub {
    my $self = shift;
    my $txn_id = $self->param('transactionId') || 'missing';
    $self->render('nets/Terminal/default', format => 'aspx', payment => $payments->{$txn_id});
  });

  push @{ $app->renderer->classes }, __PACKAGE__;
}

sub _camelize {
  my ($self, $args) = @_;
  map { my $k = $_; s/_([a-z])/\U$1/g; ($_ => $args->{$k}); } keys %$args;
}

sub _error {
  my ($self, $err) = @_;
  my $res = Mojo::Message::Response->new;
  return $res->error({ message => $err, advice => 400 })->code(400);
}

sub _extract_error {
  my ($self, $tx) = @_;
  local $@;
  eval { $_[0]->res->dom->Exception->Error->Message->text };
}

sub _url {
  my $url = Mojo::URL->new($_[0]->base_url .$_[1]);
  warn "[MOJO_NETS] URL $url\n" if DEBUG;
  $url;
}

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;

__DATA__
@@ layouts/nets.aspx.ep
<!DOCTYPE html>
<html>
<head>
  <title>Nets terminal</title>
</head>
<body>
%= content
</body>
</html>

@@ nets/Netaxept/Process.aspx.ep
<?xml version="1.0" ?>
<ProcessResponse xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <Operation>AUTH</Operation>
  <ResponseCode>OK</ResponseCode>
  <AuthorizationId>064392</AuthorizationId>
  <TransactionId>b127f98b77f741fca6bb49981ee6e846</TransactionId>
  <ExecutionTime>2009-12-16T11:17:54.633125+01:00</ExecutionTime>
  <MerchantId>9999997</MerchantId>
</ProcessResponse>

@@ nets/Netaxept/Query.aspx.ep
<?xml version="1.0" ?>
<TODO/>

@@ nets/Netaxept/Register.aspx.ep
<?xml version="1.0" ?>
<RegisterResponse xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <TransactionId><%= $txn_id %></TransactionId>
</RegisterResponse>

@@ nets/Terminal/default.aspx.ep
% layout 'nets';
<h1>Netaxept</h1>
<p>This is a dummy terminal. Obviously.</p>
<dl>
  <dt>Merchant</dt><dd><%= $payment->{merchantId} %></dd>
  <dt>Amount</dt><dd><%= sprintf '%.02f', $payment->{amount} / 100 %> <%= $payment->{currencyCode} %></dd>
  <dt>Order number</dt><dd><%= $payment->{orderNumber} %></dd>
</dl>
<p>
  %= link_to 'Complete payment', url_for($payment->{redirectUrl})->query({ transactionId => param('transactionId'), responseCode => 'OK' }), class => 'back'
</p>
