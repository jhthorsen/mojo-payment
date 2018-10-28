use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

$ENV{MOJO_USERAGENT_CACHE_STRATEGY} = 'playback';

use Mojolicious::Lite;
plugin Payment =>
  {providers => {stripe => {public_key => 'pk_test_abc', secret_key => 'sk_test_xyz'}}};

my $t       = Test::Mojo->new;
my $payment = $t->app->payment;

isa_ok($payment, 'Mojo::Payment::Stripe');
is $payment->default_currency, '',            'no default_currency';
is $payment->public_key,       'pk_test_abc', 'public_key pk_test_abc';
is $payment->secret_key,       'sk_test_xyz', 'secret_key sk_test_xyz';
is $payment->ua, $t->app->payment('self')->ua, 'ua is passed on';
ok $payment->ua->does('Mojo::UserAgent::Role::Cache'), 'ua does caching';

eval { $t->app->payment('nope') };
like $@, qr{Mojo::Payment::Nope}, 'cannot load nope';

$payment = $t->app->payment('stripe');
isa_ok($payment, 'Mojo::Payment::Stripe');

plugin Payment => {default_currency => 'nok', default_provider => 'invalid'};

eval { $t->app->payment };
like $@, qr{Mojo::Payment::Invalid}, 'cannot load invalid';
$payment = $t->app->payment('stripe');
is $payment->default_currency, 'nok', 'default_currency nok';

done_testing;
