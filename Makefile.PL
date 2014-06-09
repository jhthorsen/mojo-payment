use ExtUtils::MakeMaker;
WriteMakefile(
  NAME => 'Mojolicious::Plugin::NetsPayment',
  ABSTRACT_FROM => 'lib/Mojolicious/Plugin/NetsPayment.pm',
  VERSION_FROM => 'lib/Mojolicious/Plugin/NetsPayment.pm',
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
      homepage => 'https://metacpan.org/release/Mojolicious-Plugin-NetsPayment',
      bugtracker => 'https://github.com/jhthorsen/mojolicious-plugin-netspayment/issues',
      repository => 'https://github.com/jhthorsen/mojolicious-plugin-netspayment.git',
    },
  },
  test => {
    TESTS => 't/*.t',
  },
);
