use Mojo::Base -base;
use Test::Mojo;
use Test::More;

$ENV{MOJO_NETS_SELF_CONTAINED} = 1;

{
  use Mojolicious::Lite;
  plugin 'NetsPayment';

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
        my $json = $res->error || {};
        $json->{transaction_id} = $res->param('transaction_id');
        $json->{location} = $res->headers->location;
        $self->render(json => $json, status => $res->code);
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
        my $json = $res->error || {};
        $json->{authorization_id} = $res->param('authorization_id');
        $self->render(json => $json, status => $res->code);
      },
    );
  };
}

my $t = Test::Mojo->new;
my (@tx, $url);

$t->app->nets->_ua->on(start => sub { push @tx, pop });

{
  diag 'Step 1';
  @tx = ();
  $t->post_ok('/checkout')
    ->status_is(400)
    ->json_is('/advice', 400)
    ->json_is('/message', 'amount missing in input')
    ->json_is('/transaction_id', undef)
    ;

  @tx = ();
  $t->post_ok('/checkout?amount=100')
    ->status_is(400)
    ->json_is('/advice', 400)
    ->json_is('/message', 'order_number missing in input')
    ->json_is('/transaction_id', undef)
    ;

  @tx = ();
  $t->post_ok('/checkout?amount=100&order_number=42')
    ->status_is(302)
    ->json_is('/advice', undef)
    ->json_is('/message', undef)
    ->json_is('/transaction_id', 'b127f98b77f741fca6bb49981ee6e846')
    ;

  $url = $tx[0]->req->url;
  diag "nets register url=$url";
  is $url->path, '/Netaxept/Register.aspx', '/Netaxept/Register.aspx';
  is $url->query->param('orderNumber'), '42', 'orderNumber=42';
  is $url->query->param('OS'), 'linux', 'OS=linux';
  is $url->query->param('merchantId'), 'dummy_merchant', 'merchantId=dummy_merchant';
  like $url->query->param('redirectUrl'), qr{/checkout\?}, 'redirectUrl=/checkout';
  is $url->query->param('currencyCode'), 'NOK', 'currencyCode=NOK';
  is $url->query->param('token'), 'dummy_token', 'token=dummy_token';
  is $url->query->param('amount'), '10000', 'amount=10000';
  is $url->query->param('environmentLanguage'), 'perl', 'environmentLanguage=perl';
}

{
  $url = Mojo::URL->new($t->tx->res->json->{location});
  diag "nets terminal url=$url";
  is $url->path, '/Terminal/default.aspx', '/Terminal/default.aspx';
  is $url->query->param('transactionId'), 'b127f98b77f741fca6bb49981ee6e846', 'transactionId=b127f98b77f741fca6bb49981ee6e846';
  is $url->query->param('merchantId'), 'dummy_merchant', 'merchantId=dummy_merchant';

  diag 'Step 2';
  $t->get_ok($url)
    ->status_is(200)
    ->element_exists('a.back', 'link back to merchant page')
    ;
}

{
  $url = Mojo::URL->new($t->tx->res->dom->at('a.back')->{href});

  is $url->path, '/checkout', '/checkout';
  is $url->query->param('responseCode'), 'OK', 'responseCode=OK';
  is $url->query->param('transactionId'), 'b127f98b77f741fca6bb49981ee6e846', 'transactionId=b127f98b77f741fca6bb49981ee6e846';

  # params from the original test url
  is $url->query->param('amount'), '100', 'amount=100';
  is $url->query->param('order_number'), '42', 'order_number=42';

  diag 'Step 3 + 4';
  $t->get_ok($url)
    ->status_is(200)
    ->json_is('/authorization_id', '064392')
    ;
}

done_testing;
