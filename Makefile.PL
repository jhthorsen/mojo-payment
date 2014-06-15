use ExtUtils::MakeMaker;
WriteMakefile(
  NAME => 'Mojolicious::Plugin::PayPal',
  ABSTRACT_FROM => 'lib/Mojolicious/Plugin/PayPal.pm',
  VERSION_FROM => 'lib/Mojolicious/Plugin/PayPal.pm',
  AUTHOR => 'Jan Henning Thorsen <jhthorsen@cpan.org>',
  LICENSE => 'perl',
  PREREQ_PM => {
    'Mojolicious' => '5.00',
  },
  BUILD_REQUIRES => {
    'Test::More' => '0.90',
  },
  META_MERGE => {
    resources => {
      license => 'http://dev.perl.org/licenses/',
      homepage => 'https://metacpan.org/release/Mojolicious-Plugin-PayPal',
      bugtracker => 'https://github.com/jhthorsen/mojolicious-plugin-paypal/issues',
      repository => 'https://github.com/jhthorsen/mojolicious-plugin-paypal.git',
    },
  },
  test => {
    TESTS => 't/*.t',
  },
);
