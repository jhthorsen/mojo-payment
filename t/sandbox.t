use Mojo::Base -base;
use Test::Mojo;
use Test::More;

plan skip_all => 'TEST_PAYPAL_SANDBOX=1 is not set' unless $ENV{TEST_PAYPAL_SANDBOX};

{
  use Mojolicious::Lite;
  plugin PayPal => {
    client_id => 'EOJ2S-Z6OoN_le_KS1d75wsZ6y0SFdVsY9183IvxFyZp',
    secret => 'EClusMEUk8e9ihI7ZdVLF5cZ6y0SFdVsY9183IvxFyZp',
  };

  # register a payment and send the visitor to PayPal payment terminal
  post '/checkout' => sub {
    my $self = shift->render_later;
    my %payment = (
      amount => scalar $self->param('amount'),
      description => 'Some description',
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
            payer_id => scalar $res->param('payer_id'),
            transaction_id => scalar $res->param('transaction_id'),
          },
          status => $res->code,
        );
      },
    );
  };
}

my $t = Test::Mojo->new;
my $url;

{
  $t->post_ok('/checkout?amount=100')
    ->status_is(302)
    ->json_is('/advice', undef)
    ->json_is('/message', undef)
    ->json_like('/transaction_id', qr{^PAY-\w+})
    ;

  $url = Mojo::URL->new($t->tx->res->json->{location});
  diag "paypal terminal url=$url";
  is $url->path, '/cgi-bin/webscr', '/cgi-bin/webscr';

  diag 'Step 2';
  $t->get_ok($url)->status_is(200);
}

done_testing;
