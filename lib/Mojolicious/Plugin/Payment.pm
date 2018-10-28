package Mojolicious::Plugin::Payment;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::UserAgent;
use Mojo::Payment::Stripe;

our $VERSION = '0.01';

has default_currency => '';
has default_provider => 'stripe';
has providers        => sub { +{} };

has ua => sub {
  $ENV{MOJO_USERAGENT_CACHE_STRATEGY}
    ? Mojo::UserAgent->with_roles('+Cache')->new
    : Mojo::UserAgent->new;
};

sub register {
  my ($self, $app, $config) = @_;

  $self->default_currency($config->{default_currency}) if $config->{default_currency};
  $self->default_provider($config->{default_provider}) if $config->{default_provider};
  $self->providers($config->{providers} || {});

  $app->helper(payment => sub { $self->_helper_payment(@_) });
}

sub _helper_payment {
  my ($self, $c, $provider) = @_;

  $provider ||= $self->default_provider;
  return $self if $provider eq 'self';
  return $c->stash->{"payment.$provider"} if $c->stash->{"payment.$provider"};

  my $class = sprintf 'Mojo::Payment::%s', ucfirst $provider;
  my $attrs = $self->providers->{$provider} || {};
  local $attrs->{default_currency} = $self->default_currency;
  local $attrs->{ua}               = $self->ua;

  return $c->stash->{"payment.$provider"} = $class->new($attrs);
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Payment - Issue payments using Mojo::Payment

=head1 SYNOPSIS

  use Mojolicious::Lite;
  plugin Payment => {
    default_currency => "usd",
    default_provider => "stripe",
    providers        => {
      stripe => {public_key => "pk_test_abc", secret_key => "sk_test_xyz"}
    }
  };

=head1 DESCRIPTION

L<Mojolicious::Plugin::Payment> is a L<Mojolicious> plugin that provides an
easy API for issuing payments using different providers.

=head1 ATTRIBUTES

=head2 default_currency

  $str = $self->default_currency;
  $self = $self->default_currency("usd");

Sets the default currency. This is not specified by default, but you can set
one if you like.

=head2 default_provider

  $str = $self->default_provider;
  $self = $self->default_provider("stripe");

Sets the default provider to use. Defaults to "stripe".

=head2 providers

  $hash_ref = $self->providers;
  $self = $self->providers({stripe => {...}});

Sets the default attributes used when construting an object for a given
provider.

=head2 ua

  $ua = $self->ua;
  $self = $self->ua(Mojo::UserAgent->new);

Holds a L<Mojo::UserAgent> object, used to talk with the providers.

=head1 HELPERS

=head2 payment

  $obj = $c->payment;
  $obj = $c->payment($provider);
  $obj = $c->payment("stripe");
  $self = $c->payment("self");

Returns a L<Mojo::Payment> object using either L</default_provider> or the
provider string passed into the method. A special C<$provider> string "self",
will return the plugin instance, instead of a L<Mojo::Payment> object.

=head1 METHODS

=head2 register

  $self->register($app, \%config);

See L</SYNOPSIS>.

=head1 SEE ALSO

L<Mojo::Payment>.

=cut
