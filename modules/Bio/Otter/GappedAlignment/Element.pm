
### Bio::Otter::GappedAlignment::Element

package Bio::Otter::GappedAlignment::Element;

use strict;
use warnings;

use Readonly;

use Bio::Otter::GappedAlignment::ElementTypes;

use base 'Bio::Otter::GappedAlignment::ElementI';

Readonly my %TYPE_CLASS => {
    $T_MATCH       => 'Match',
    $T_CODON       => 'Codon',
    $T_GAP         => 'Gap',
    $T_NON_EQUIV   => 'NER',
    $T_5P_SPLICE   => 'SS_5P',
    $T_3P_SPLICE   => 'SS_3P',
    $T_INTRON      => 'Intron',
    $T_SPLIT_CODON => 'SplitCodon',
    $T_FRAMESHIFT  => 'Frameshift',
};

sub _module_name {
    my ($self, $type) = @_;
    return __PACKAGE__ . '::' . $TYPE_CLASS{$type};
}

# Load all element subtype modules
#
foreach my $class (keys %TYPE_CLASS) {
    my $module = __PACKAGE__->_module_name($class);
    eval "require $module" or die "Couldn't load $module"; ## no critic (ProhibitStringyEval)
}

sub new {
    my ($pkg, $type, $query_length, $target_length) = @_;
    die "missing element type"  unless $type;
    die "unknown element type"  unless $TYPE_CLASS{$type};
    die "missing query_length"  unless defined $query_length;
    die "missing target_length" unless defined $target_length;

    my $class = $pkg->_module_name($type);

    return $class->new($query_length, $target_length);
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::Element

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
