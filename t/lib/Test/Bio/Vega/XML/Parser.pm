package Test::Bio::Vega::XML::Parser;

use Test::Class::Most
    parent     => 'OtterTest::Class';

sub build_attributes {
    my $test = shift;
    return {
        object_builders => { test => sub { return; } },
    };
}

# Transform base class does not supply required initialise() method.
package Bio::Vega::XML::Parser;

use Test::More;

sub initialize {
    note 'DUMMY Bio::Vega::XML::Parser->initialize().';
    return;
}

1;
