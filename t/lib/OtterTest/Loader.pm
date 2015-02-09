package OtterTest::Loader;

use strict;
use warnings;

use parent 'Test::Class::Load';

sub is_test_class {
    my ( $class, $file, $dir ) = @_;

    # return unless it's a .pm (the default)
    return unless $class->SUPER::is_test_class( $file, $dir );

    # and only allow classes starting with 'Test/Bio'
    return $file =~ m{^${dir}/Test/Bio};
}

1;
