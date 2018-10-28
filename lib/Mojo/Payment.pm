package Mojo::Payment;
use Mojo::Base -base;

use Mojo::Payment::Error;
use Mojo::Promise;
use Mojo::UserAgent;

has default_currency => '';
has ua               => sub {
  $ENV{MOJO_USERAGENT_CACHE_STRATEGY}
    ? Mojo::UserAgent->with_roles('+Cache')->new
    : Mojo::UserAgent->new;
};

sub _reject { Mojo::Payment::Error->throw($_[1]) }

1;

=encoding utf8

=head1 NAME

Mojo::Payment - Base class for Mojo::Payment providers

=head1 SYNOPSIS

See a provider sub class or L<Mojolicious::Plugin::Payment> for synopsis.

=head1 DESCRIPTION

L<Mojo::Payment> is the base class for different payment providers:

=over 2

=item * L<Mojo::Payment::Stripe>

=back

=head1 ATTRIBUTES

=head2 default_currency

  $str = $self->default_currency;
  $self = $self->default_currency("usd");

Sets the default currency. This is not specified by default, but you can set
one if you like.

=head2 ua

  $ua = $self->ua;
  $self = $self->ua(Mojo::UserAgent->new);

Holds a L<Mojo::UserAgent> object, used to talk with the providers.

=head1 AUTHOR

Jan Henning Thorsen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2018, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<Mojolicious::Plugin::Payment>.

=cut
