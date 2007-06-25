## Vega module for comparison of two objects, gene vs gene, transcript vs transcript, translation vs translation and exon vs exon

package Bio::Vega::Utils::Comparator;

use strict;
use warnings;
use base 'Exporter';
our @EXPORT_OK = qw{ compare };

use Bio::EnsEMBL::Utils::Exception qw(throw);

sub compare{
    my ($obj1,$obj2) = @_;

      ## sanity checks:
    if(!$obj1) {
        throw("compare(): Cannot compare NULL to ".$obj2->stable_id." (key=".$obj2->hashkey.")");
    } elsif(!$obj2) {
        throw("compare(): Cannot compare ".$obj1->stable_id." (key=".$obj1->hashkey.") to NULL");
    } elsif(ref($obj1) ne ref($obj2)) {
        throw("Cannot compare $obj1 to $obj2. Objects have to belong to the same class.");
    }

    my $class = ref($obj1);
    if(!$obj1->can('hashkey')) {
        throw("I need to run 'hashkey' method on the objects, which is not available for class $class.");
    }
    my $obj1_hash_key=$obj1->hashkey;
    my $obj2_hash_key=$obj2->hashkey;

    ## First compare the main keys. If failed, try hashkey_sub:
    my $changed=0;
    if ($obj1_hash_key ne $obj2_hash_key) {
        $changed=1;
        print STDERR "*Changes observed\n";
        if ($class->isa('Bio::Vega::ContigInfo')) {
            print STDERR "ContigInfo has changed due to change in main key\n";
        } else {
            print STDERR $obj1->stable_id.".".$obj1->version." now has changed main key ".$obj1->hashkey_structure()."\n";
        }
        print STDERR "Before-key: $obj1_hash_key\nAfter-key: $obj2_hash_key\n";

    } elsif($obj1->can('hashkey_sub')) { # So exons (which have no hashkey_sub) are excluded:

        my $obj1_hash_sub = $obj1->hashkey_sub;
        my $obj2_hash_sub = $obj2->hashkey_sub;
        my $e_count=0;
        foreach my $subkey (keys %$obj1_hash_sub) {
            unless (exists $obj2_hash_sub->{$subkey}) {
                $e_count++;
                if ($e_count == 1) { # so it is only printed once
                    print STDERR "*Changes observed\n";
                    $changed=1;
                }
                if($obj1->can('stable_id') && $obj1->can('version')) {
                    print STDERR $obj1->stable_id.".".$obj1->version." now has changed or new attrib $subkey\n";
                } else {
                    print STDERR $obj1->slice->name." ContigInfo now has changed or new attrib $subkey\n";
                }
            }
        }
    }
    return $changed;
}

1;
