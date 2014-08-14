#! /usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::MockObject;
use Test::MockObject::Extends;

use Bio::Otter::Lace::Client;


sub main {
    plan tests => 1;

    my @tt = qw( designations_tt );
    foreach my $sub (@tt) {
        my $code = __PACKAGE__->can($sub) or die "can't find \&$sub";
        note "begin subtest: $sub";
        subtest $sub => $code;
    }

    return 0;
}

exit main();


sub designations_tt {
    plan tests => 38;

    # contents of designations.txt from 536373af == when 84 went live
    my $BOLC_A = _mock_BOLC();
    my %desigA =
      qw(dev    85
         zeromq 84_zeromq
         test   85
         live   84.04
         82     82.04
         old    83.05
         81     81.06
         80     80
         79     79.07
         78     78.12 );
    $BOLC_A->mock(get_designations => sub { return \%desigA });

    # designate_this doesn't need a real instance of BOLC,
    # iff we feed it all the necessary %test_input
    my $do = sub {
        my ($BOGparams, @arg) = @_;
        $BOGparams->{feature} ||= '';
        push @arg, BOG => _mock_BOG($BOGparams);
        $BOLC_A->designate_this(@arg);
    };

    _check_hash('dev seen from live=84',
                $do->({ head => 'humpub-release-85-dev-66-g9cf15b2' },
                      major => 85),
                major_designation => 'dev',
                descr => 'an unstable developer-edition Otterlace',
                stale => 0,
                latest_this_major => 85,
                current_live => '84.04');

    _check_hash('dev_anyfeat seen from live=84',
                $do->({ head => 'humpub-release-85-dev-95-g2fc4d37',
                        feature => 'anyfeat' },
                      major => 85),
                major_designation => 'dev',
                descr => 'an experimental anyfeat Otterlace',
                stale => 0,
                latest_this_major => undef,
                current_live => '84.04');
    $BOLC_A->logger->ok_pop("was not designated",
                            qr{^No match for .*_anyfeat\$.* against designations\.txt});

    _check_hash('live seen from live=84',
                $do->({ head => 'humpub-release-84-04' }, major => 84),
                major_designation => 'live',
                descr => 'the latest live Otterlace',
                stale => 0,
                latest_this_major => '84.04',
                current_live => '84.04');

    _check_hash('live,stale seen from live=84',
                $do->({ head => 'humpub-release-84-01-7-g96d4f8f' }, major => 84),
                major_designation => 'live',
                descr => "not the current live Otterlace\nIt is 84.01+7ci, latest is 84.04",
                stale => 1);

    _check_hash('old seen from live=84',
                $do->({ head => 'humpub-release-83-05' }, major => 83),
                major_designation => 'old',
                descr => 'the last old Otterlace',
                stale => 0,
                latest_this_major => '83.05',
                current_live => '84.04');

    _check_hash('(prev) seen from live=84',
                $do->({ head => 'humpub-release-81-05' }, major => 81),
                major_designation => '_obsolete',
                descr => 'an obsolete Otterlace.  We are now on 84.04',
                stale => 1,
                latest_this_major => '81.06',
                current_live => '84.04');

    $BOLC_A->logger->ok_pop("no messages");
    _check_hash('(unknown) seen from live=84',
                $do->({ head => 'humpub-release-77-01' }, major => 77),
                major_designation => '_obsolete',
                descr => 'an obsolete Otterlace.  We are now on 84.04',
                stale => 1,
                latest_this_major => '84.04',
                current_live => '84.04');
    $BOLC_A->logger->ok_pop("undesig list",
                            qr{^No match for \S+ against designations\.txt values });

    return;
}

sub _check_hash {
    my ($testname, $hashref, %want) = @_;
    my $ok = 1;
    while (my ($key, $val) = each %want) {
        $ok=0 unless is($hashref->{$key}, $val, "($testname)->\{$key}");
    }
    diag explain $hashref unless $ok;
    return $ok;
}

# A mock logger, which can check its messages
sub _logger {
    my $logger = Test::MockObject->new([]);

    $logger->mock(warn => sub {
                      my ($self, $msg) = @_;
                      push @$self, [ warn => $msg ];
                      return;
                  });

    $logger->mock(ok_pop => sub {
                      my ($self, $testname, @regexp) = @_;
                      foreach my $want_re (@regexp) {
                          my $got = pop @$self;
                          my ($type, $msg) = @{ $got || [ 'nothing' ] };
                          like($msg, $want_re, "$testname (type=$type)");
                      }
                      is(scalar @$self, 0, "$testname: popped all")
                        or diag explain { logged => $self };
                      @$self = ();
                      return;
                  });

    return $logger;
}

sub _mock_BOLC {
    my $logger = _logger();
    return Test::MockObject::Extends->new('Bio::Otter::Lace::Client')->
      mock(logger => sub { $logger });
}

sub _mock_BOG {
    my %param = %{ shift() };
    my $obj = bless \%param, 'Bio::Otter::Git';
    return Test::MockObject::Extends->new($obj)->
      mock(param => sub {
               my ($self, $key) = @_;
               die "$self: no key $key" unless exists $self->{$key};
               return $self->{$key};
           });
}
