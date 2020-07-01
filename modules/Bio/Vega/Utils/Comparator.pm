=head1 LICENSE

Copyright [2018-2020] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

## Vega module for comparison of two objects, gene vs gene, transcript vs
## transcript, translation vs translation and exon vs exon

package Bio::Vega::Utils::Comparator;

use strict;
use warnings;
use base 'Exporter';
our @EXPORT_OK = qw{ compare };

use Bio::EnsEMBL::Utils::Exception qw(throw);

sub compare {
    my ($obj1, $obj2) = @_;

    my $changed = 0;

    ## sanity checks:
    if (!$obj1) {
        throw("compare(): Cannot compare NULL to ".$obj2->stable_id." (key=".$obj2->vega_hashkey.")");
    }
    elsif (!$obj2) {
        throw("compare(): Cannot compare ".$obj1->stable_id." (key=".$obj1->vega_hashkey.") to NULL");
    }
    elsif (ref($obj1) ne ref($obj2)) {
        throw("Cannot compare $obj1 to $obj2. Objects have to belong to the same class.");
    }
    elsif ($obj1 == $obj2) {
        # This check prevents saving because we re-use Exons
        # throw(sprintf "Comparing %s to itself. Cached object in DBAdaptor?", ref($obj1));
        return $changed;
    }

    if(!$obj1->can('vega_hashkey')) {
        my $class = ref($obj1);
        throw("I need to run 'vega_hashkey' method on the objects, which is not available for class $class.");
    }
    my $obj1_hash_key= lc $obj1->vega_hashkey;
    my $obj2_hash_key= lc $obj2->vega_hashkey;

    ## First compare the main keys. If failed, try vega_hashkey_sub:
    if ($obj1_hash_key ne $obj2_hash_key) {
        $changed=1;
        warn "*Changes observed\n";
        if ($obj1->isa('Bio::Vega::ContigInfo')) {
            warn "ContigInfo has changed due to change in main key\n";
        } else {
            warn $obj1->stable_id.".".$obj1->version." now has changed main key ".$obj1->vega_hashkey_structure()."\n";
        }
        warn
            " Before-key: $obj1_hash_key\n",
            "  After-key: $obj2_hash_key\n";

    } elsif($obj1->can('vega_hashkey_sub')) { # So exons (which have no vega_hashkey_sub) are excluded:

        my $obj1_hash_sub = $obj1->vega_hashkey_sub;
        my $obj2_hash_sub = $obj2->vega_hashkey_sub;
        my $e_count=0;
        foreach my $subkey (keys %$obj1_hash_sub) {
            unless (exists $obj2_hash_sub->{$subkey}) {
                $e_count++;
                if ($e_count == 1) { # so it is only printed once
                    warn "*Changes observed\n";
                    $changed=1;
                }
                if($obj1->can('stable_id') && $obj1->can('version')) {
                    warn $obj1->stable_id.".".$obj1->version." now has changed or new attrib $subkey\n";
                } else {
                    warn $obj1->slice->name." ContigInfo now has changed or new attrib $subkey\n";
                }
            }
        }
    }
    return $changed;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

