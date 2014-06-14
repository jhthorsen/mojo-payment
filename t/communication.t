use Mojo::Base -base;
use Test::Mojo;
use Test::More;

{
  use Mojolicious::Lite;
  plugin PayPal => { token => \ "dummy" };

  # register a payment and send the visitor to PayPal payment terminal
  post '/checkout' => sub {
    my $self = shift->render_later;
    my %payment = (
      amount => scalar $self->param('amount'),
      order_number => scalar $self->param('order_number'),
    );

    Mojo::IOLoop->delay(
      sub {
        my ($delay) = @_;
        $self->paypal(register => \%payment, $delay->begin);
      },
      sub {
        my ($delay, $res) = @_;
        $self->render(
          json => {
            message => scalar $res->param('message'),
            source => scalar $res->param('source'),
            transaction_id => scalar $res->param('transaction_id'),
            location => $res->headers->location,
          },
          status => $res->code,
        );
      },
    );
  };

  # after redirected back from PayPal payment terminal
  get '/checkout' => sub {
    my $self = shift->render_later;

    Mojo::IOLoop->delay(
      sub {
        my ($delay) = @_;
        $self->paypal(process => {}, $delay->begin);
      },
      sub {
        my ($delay, $res) = @_;
        $self->render(
          json => {
            message => scalar $res->param('message'),
            source => scalar $res->param('source'),
            authorization_id => scalar $res->param('authorization_id'),
          },
          status => $res->code,
        );
      },
    );
  };
}

my $t = Test::Mojo->new;
my (@tx, $url);

$t->app->paypal->_ua->on(start => sub { push @tx, pop });

{
  diag 'Step 1';
  @tx = ();
  $t->post_ok('/checkout')
    ->status_is(400)
    ->json_is('/source', 'Mojolicious::Plugin::PayPal')
    ->json_is('/message', 'amount missing in input')
    ->json_is('/transaction_id', undef)
    ;

  @tx = ();
  $t->post_ok('/checkout?amount=100')
    ->status_is(302)
    ->json_is('/advice', undef)
    ->json_is('/message', undef)
    ->json_is('/transaction_id', 'b127f98b77f741fca6bb49981ee6e846')
    ;

  $url = $tx[0]->req->url;
  diag "paypal register url=$url";
  is $url->path, 'register_url', 'register_url';
}

{
  $url = Mojo::URL->new($t->tx->res->json->{location});
  diag "paypal terminal url=$url";
  is $url->path, 'terminal_url', 'terminal_url';

  diag 'Step 2';
  $t->get_ok($url)
    ->status_is(200)
    ->element_exists('a.back', 'link back to merchant page')
    ->text_is('dl dd:nth-of-type(1)', 'dummy_client', 'terminal dummy_client')
    ->text_is('dl dd:nth-of-type(2)', '100.00 NOK', 'terminal amount')
    ->text_is('dl dd:nth-of-type(3)', 'Some description', 'terminal description')
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
