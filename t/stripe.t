use Mojo::Base -strict;
use Mojo::File 'path';
use Mojo::JSON qw(false true);
use Mojo::Payment::Stripe;
use Test::More;

plan skip_all => 'MOJO_STRIPE_SECRET_KEY=sk_test_xyz' unless $ENV{MOJO_STRIPE_SECRET_KEY};

$ENV{MOJO_USERAGENT_CACHE_STRATEGY} ||= 'playback';
use Mojo::UserAgent::Role::Cache;
Mojo::UserAgent::Role::Cache->cache_driver_singleton->root_dir(path(
  path(__FILE__)->dirname, 'data'));

my $payment = Mojo::Payment::Stripe->new;
my ($err, $res);

eval { sync($payment->charge_capture_p(undef)) };
like $@, qr{Parameter charge_id missing}, 'Parameter charge_id missing';

eval { sync($payment->charge_create_p({amount => undef})) };
like $@, qr{Parameter amount missing}, 'Parameter amount missing';

eval { sync($payment->charge_create_p({amount => 42})) };
like $@, qr{Parameter currency missing}, 'Parameter currency missing';

eval { sync($payment->charge_retrieve_p(undef)) };
like $@, qr{Parameter charge_id missing}, 'Parameter charge_id missing';

eval { sync($payment->charge_update_p(undef)) };
like $@, qr{Parameter charge_id missing}, 'Parameter charge_id missing';

my $url   = $payment->_url_for('tokens');
my $token = $payment->ua->post(
  $url,
  form => {
    'card[number]'    => '4242424242424242',
    'card[cvc]'       => '123',
    'card[exp_month]' => '12',
    'card[exp_year]'  => '2019',
  }
)->res->json->{id};

note "token=$token";

my $charge = sync($payment->charge_create_p({
  amount        => 42,
  capture       => 0,
  currency      => 'nok',
  description   => 'created by mojo-payment',
  receipt_email => 'jhthorsen@cpan.org',
  source        => $token,
}));

is $charge->{description}, 'created by mojo-payment', 'description';

$charge
  = sync($payment->charge_update_p($charge->{id}, {description => 'updated by mojo-payment'}));
is $charge->{captured}, false, 'captured';
is $charge->{currency},      'nok',                     'currency';
is $charge->{description},   'updated by mojo-payment', 'description';
is $charge->{receipt_email}, 'jhthorsen@cpan.org',      'receipt_email';
is $charge->{source}{object}, 'card', 'source';

{
  local $TODO = 'Not sure if it will capture with test secret';
  $charge = sync($payment->charge_capture_p($charge->{id}));
  is $charge->{captured}, true, 'captured';
}

is +sync($payment->charge_retrieve_p($charge->{id}))->{id}, $charge->{id}, 'charge_retrieve_p';

my $list = sync($payment->charge_list_p({limit => 2}));
is $list->{object}, 'list', 'list';
ok $list->{has_more}, 'has_more';
is @{$list->{data}}, 2, 'got one charge';
is $list->{data}[0]{object}, 'charge', 'list has charge object';

done_testing;

sub sync {
  my $p = shift;
  ($err, $res) = (undef, undef);
  $p->then(sub { $res = shift }, sub {$err})->wait;
  die $err if $err;
  return $res;
}
