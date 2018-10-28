use Mojo::Base -strict;
use Mojo::File 'path';
use Mojo::JSON qw(false true);
use Mojo::Payment::Paypal;
use Test::More;

$ENV{MOJO_USERAGENT_CACHE_STRATEGY} ||= 'playback';
use Mojo::UserAgent::Role::Cache;
Mojo::UserAgent::Role::Cache->cache_driver_singleton->root_dir(path(
  path(__FILE__)->dirname, 'data'));

my $payment = Mojo::Payment::Paypal->new(
  redirect_urls => {
    cancel_url => 'https://example.com/checkout?cancel=1',
    return_url => 'https://example.com/checkout?success=1',
  }
);
my ($err, $res);

eval { sync($payment->charge_capture_p(undef)) };
like $@, qr{Parameter charge_id missing}, 'Parameter charge_id missing';

eval { sync($payment->charge_create_p({amount => undef})) };
like $@, qr{Parameter /transactions/0/amount/total missing}, 'Parameter amount missing';

eval { sync($payment->charge_create_p({amount => 42})) };
like $@, qr{Parameter /transactions/0/amount/currency missing}, 'Parameter currency missing';

eval { sync($payment->charge_retrieve_p(undef)) };
like $@, qr{Parameter charge_id missing}, 'Parameter charge_id missing';

eval { sync($payment->charge_update_p(undef)) };
like $@, qr{Parameter charge_id missing}, 'Parameter charge_id missing';

my $charge = sync($payment->charge_create_p({
  amount      => 42,
  capture     => 0,
  currency    => 'nok',
  description => 'created by mojo-payment',
  email       => 'jhthorsen@cpan.org',
}));

is $charge->{transactions}[0]{description}, 'created by mojo-payment', 'description';

$charge->{description} = 'updated by mojo-payment';
$charge->{transactions}[0]{description} = 'updated by mojo-payment';
$charge = sync($payment->charge_update_p($charge->{id}, $charge));
is $charge->{state},  'created', 'state';
is $charge->{intent}, 'sale',    'intent';
is $charge->{transactions}[0]{amount}{currency}, 'NOK',   'currency';
is $charge->{transactions}[0]{amount}{total},    '42.00', 'amount';
is $charge->{transactions}[0]{description}, 'updated by mojo-payment', 'description';

is +sync($payment->charge_retrieve_p($charge->{id}))->{id}, $charge->{id}, 'charge_retrieve_p';

eval {
  $charge = sync($payment->charge_capture_p($charge->{id}, {payer_id => 'CR87QHB7JTRSC'}));
  is $charge->{state}, 'payed', 'state';
} or do {
  diag $@;
};

my $list = sync($payment->charge_list_p({limit => 2}));
ok $list->{payments}, 'charge_list_p';

done_testing;

sub sync {
  my $p = shift;
  ($err, $res) = (undef, undef);
  $p->then(sub { $res = shift }, sub { $err = shift })->wait;
  die $err if $err;
  return $res;
}
