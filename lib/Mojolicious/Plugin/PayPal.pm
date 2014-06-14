package Mojolicious::Plugin::PayPal;

=head1 NAME

Mojolicious::Plugin::PayPal - Make payments using PayPal

=head1 VERSION

0.01

=head1 DESCRIPTION

L<Mojolicious::Plugin::PayPal> is a plugin for the L<Mojolicious> web
framework which allow you to do payments using L<https://www.paypal.com|PayPal>.

This module is EXPERIMENTAL. The API can change at any time. Let me know
if you are using it.

=head1 SYNOPSIS

  use Mojolicious::Lite;

=cut

use Mojo::Base 'Mojolicious::Plugin';
use Mojo::JSON 'j';
use Mojo::UserAgent;
use constant DEBUG => $ENV{MOJO_PAYPAL_DEBUG} || 0;

our $VERSION = '0.01';

=head1 ATTRIBUTES

=head2 base_url

  $str = $self->base_url;

This is the location to PayPal payment solution. Will be set to
L<https://api.paypal.com> if the mojolicious application mode is
"production" or L<https://api.sandbox.paypal.com>.

=head2 client_id

  $str = $self->client_id;

The value used as username when fetching the the access token.
This can be found in "Applications tab" in the PayPal Developer site.

=head2 currency_code

  $str = $self->currency_code;

The currency code. Default is "USD".

=head2 secret

  $str = $self->secret;

The value used as password when fetching the the access token.
This can be found in "Applications tab" in the PayPal Developer site.

=cut

has base_url => 'https://api.sandbox.paypal.com';
has client_id => 'dummy_client';
has currency_code => 'USD';
has token => 'dummy_token';
has _access_token => sub { +{ value => '', expires_in => 0 } };
has _ua => sub { Mojo::UserAgent->new; };

=head1 HELPERS

=head2 paypal

  $self = $c->paypal;
  $c = $c->paypal($method => @args);

Returns this instance unless any args have been given or calls one of the
available L</METHODS> instead. C<$method> need to be without "_payment" at
the end. Example:

  $c->paypal(register => { ... }, sub {
    my ($c, $res) = @_;
    # ...
  });

=head1 METHODS

=head2 register_payment

  $self = $self->register_payment(
    $c,
    {
      amount => $num, # 99.90, not 9990
      redirect_url => $str, # default to current request URL
      # ...
    },
    sub {
      my ($self, $res) = @_;
    },
  );

The L</register_payment> method is used to send the required payment details
to PayPal which will later be approved by the user after being redirected
to the PayPal terminal page.

Useful C<$res> values:

=over 4

=item * $res->code

Set to 302 on success.

=item * $res->param("transaction_id")

Only set on success. An ID identifying this transaction. Generated by PayPal.

=item * $res->headers->location

Only set on success. This holds a URL to the PayPal terminal page, which
you will redirect the user to after storing the transaction ID and other
customer related details.

=back

=cut

sub register_payment {
  my ($self, $c, $args, $cb) = @_;
  my $register_url = $self->_url('/v1/payments/payment');
  my $redirect_url = Mojo::URL->new($args->{redirect_url} = $c->req->url->to_abs);
  my (%body, %headers);

  $args->{amount} or return $self->$cb($self->_error('amount missing in input'));

  %headers = (
    'Content-Type' => 'application/json',
    'Authorization' => $self->_authorization_header,
  );

  %body = (
    intent => "sale",
    redirect_urls => {
      return_url => $redirect_url->to_abs,
      cancel_url => $redirect_url->to_abs,
    },
    payer => {
      payment_method => "paypal",
    },
    transactions => [
      {
        description => $args->{description} || '',
        amount => {
          total => $args->{amount},
          currency => $args->{currency_code} || $self->currency_code,
        },
      },
    ],
  );

  Mojo::IOLoop->delay(
    sub {
      my ($delay) = @_;
      $self->_ua->get($register_url, \%headers, j(\%body), $delay->begin);
    },
    sub {
      my ($delay, $tx) = @_;
      my $res = $tx->res;

      $res->code(0) unless $res->code;

      local $@;
      eval {
        my $json = $res->json;
        my $terminal_url;

        $json->{id} or die "No transaction ID in response from PayPal";

        for my $link (@{ $json->{links} }) {
          my $key = "$link->{rel}_url";
          $key =~ s!_url_url$!_url!;
          $self->param($key => $link->{href});
        }

        $res->param(state => $json->{state});
        $res->param(transaction_id => $json->{id});
        $res->headers->location($self->param('approval_url'));
        $res->code(302);
        1;
      } or do {
        warn "[MOJO_PAYPAL] ! $@" if DEBUG;
        $self->_extract_error($tx, $@);
      };

      $self->$cb($res);
    },
  );

  $self;
}

=head2 register

  $app->plugin(PayPal => \%config);

Called when registering this plugin in the main L<Mojolicious> application.

=cut

sub register {
  my ($self, $app, $config) = @_;

  # self contained
  if (ref $config->{token}) {
    $self->_add_routes($app); # TODO
    $self->_ua->server->app($app);
    $config->{token} = ${ $config->{token} };
  }

  # copy config to this object
  for (grep { $self->$_ } keys %$config) {
    $self->{$_} = $config->{$_};
  }

  $app->helper(
    paypal => sub {
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
}

sub _authorization_header {
  my $self = shift;

  return sprint 'Bearer %s', $self->_access_token
}

sub _error {
  my ($self, $err) = @_;
  my $res = Mojo::Message::Response->new;
  $res->code(400);
  $res->param(message => $err);
  $res->param(source => __PACKAGE__);
  $res;
}

sub _extract_error {
  my ($self, $tx, $e) = @_;
  my $res = $tx->res;
  my $err = ''; # TODO

  $res->code(500);
  $res->param(message => $err // $e);
  $res->param(source => $err ? $self->base_url : __PACKAGE__);
}

sub _url {
  my $url = Mojo::URL->new($_[0]->base_url .$_[1]);
  warn "[MOJO_PAYPAL] URL $url\n" if DEBUG;
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
