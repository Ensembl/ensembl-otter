package Bio::Otter::Utils::Attribute;

use strict;
use warnings;

use Carp;

use base 'Exporter';
our @EXPORT_OK = qw( get_single_attrib_value );

# Not a method
#

sub get_single_attrib_value {
    my ($obj, $code) = @_;

    my $attr = $obj->get_all_Attributes($code);
    if (@$attr == 1) {
        return $attr->[0]->value;
    }
    elsif (@$attr == 0) {
        return;
    }
    else {
        confess sprintf("Got %d %s Attributes on %s",
            scalar(@$attr), $code, ref($obj));
    }
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
