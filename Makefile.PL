use ExtUtils::MakeMaker;
WriteMakefile(
  NAME => 'Mojolicious::Plugin::NetsPayment',
  ABSTRACT_FROM => 'lib/Mojolicious/Plugin/NetsPayment.pm',
  VERSION_FROM => 'lib/Mojolicious/Plugin/NetsPayment.pm',
  AUTHOR => 'Jan Henning Thorsen <jhthorsen@cpan.org>',
  LICENSE => 'perl',
  PREREQ_PM => {
    'EV' => '4.17',
    'IO::Socket::IP' => '0.29',
    'IO::Socket::SSL' => '1.981',
    'Net::SSLeay' => '1.58',
    'URI::_punycode' => '0.04',
    'common::sense' => '3.73',
  },
  BUILD_REQUIRES => {

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
  #MIN_PERL_VERSION => 5.10,
  #EXE_FILES => ['bin/my-app'],
);
