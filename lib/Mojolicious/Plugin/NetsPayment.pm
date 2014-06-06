package Mojolicious::Plugin::NetsPayment;

=head1 NAME

Mojolicious::Plugin::NetsPayment - Make payments using Nets

=head1 VERSION

0.01

=head1 DESCRIPTION

L<Mojolicious::Plugin::NetsPayment> is a plugin for the L<Mojolicious> web
framework which allow you to do payments using L<http://www.betalingsterminal.no|Nets>.

=head1 SYNOPSIS

  use Mojolicious::Lite;

  plugin NetsPayment => {
    merchant_id => '...',
    token => '...',
  };

  # register a payment and send the visitor to Nets payment terminal
  post '/checkout' => sub {
  };

  # after redirected back from Nets payment terminal
  get '/checkout' => sub {
  };

  app->start;

=head1 SEE ALSO

=over 4

=item * Overview

L<http://www.betalingsterminal.no/Netthandel-forside/Teknisk-veiledning/Overview/>

=item * API

L<http://www.betalingsterminal.no/Netthandel-forside/Teknisk-veiledning/API/>

=item * Validation

L<http://www.betalingsterminal.no/Netthandel-forside/Teknisk-veiledning/API/Validation/>

=back

=cut

use Mojo::Base 'Mojolicious::Plugin';
use Mojo::UserAgent;

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

From L<http://www.betalingsterminal.no/Netthandel-forside/Teknisk-veiledning/API/Process/>:

  All financial transactions are encapsulated by the "Process"-call.
  Available financial transactions are AUTH, SALE, CAPTURE, CREDIT
  and ANNUL.

=head2 query_payment

From L<http://www.betalingsterminal.no/Netthandel-forside/Teknisk-veiledning/API/Query/>:

  To check the status of a transaction at any time, you can use the Query-call.

=head2 register_payment

From L<http://www.betalingsterminal.no/Netthandel-forside/Teknisk-veiledning/API/Register/>:

  The purpose of the register call is to send all the data needed to
  complete a transaction to Netaxept servers. The input data is
  organized into a RegisterRequest, and the output data is formatted
  as a RegisterResponse.

NOTE: "amount" in this API need to be a decimal number, which will be duplicated with 100 to match
the Nets documentation.

=head2 register

  $app->plugin(NetsPayment => \%config);

Called when registering this plugin in the main L<Mojolicious> application.

=cut

sub register {
  my ($self, $app, $config) = @_;

  # copy config to this object
  $self->{$_} = $config->{$_} for grep { $self->$_ } keys %$config;

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

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;
