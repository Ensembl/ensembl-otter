package Test::Bio::Vega::Transform;

use Test::Class::Most
    parent     => 'OtterTest::Class';

sub build_attributes {
    my $test = shift;
    return {
        object_builders => { test => sub { return; } },
    };
}

# Transform base class does not supply required initialise() method.
package Bio::Vega::Transform;

use Test::More;

sub initialize {
    note 'DUMMY Bio::Vega::Transform->initialize().';
    return;
}

1;
