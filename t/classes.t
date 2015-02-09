#!/usr/bin/env perl

use Test::Otter;
use OtterTest::Class;

BEGIN {
    OtterTest::Class->run_all(1);
}

use OtterTest::Loader qw( t/lib );


# OtterTest::Class::INIT does this now:
# Test::Class->runtests;

1;

# Local Variables:
# mode: perl
# End:

# EOF
