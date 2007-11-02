package Gene;

use strict;
use warnings;

#
# Utility methods for the storing of genes
#

use Bio::EnsEMBL::DBEntry;


###############################################################################
# store gene
#
# Builds Ensembl genes from the generated chimp transcripts and stores them
# in the database.
#
###############################################################################
#use Data::Dumper;
#$Data::Dumper::Maxdepth=2;

sub store_gene {
    my $support = shift;
    my $E_slice = shift;
    my $E_ga = shift;
    my $E_pfa = shift;
    my $V_gene = shift;
    my $E_transcripts = shift;
    my $protein_features = shift;

    # skip gene if it has no transcripts left after mapping
    unless (@{ $E_transcripts }) {
        $support->log("Skipping gene ".$V_gene->stable_id." (no transcripts transfered).\n", 2);
        return;
    }

    # create xrefs to reference the Vega transcripts and translations
    create_vega_xrefs($E_transcripts);

    # transfer xrefs from Vega transcripts/translations
    transfer_xrefs($support,$V_gene, $E_transcripts);

    my $E_gene = Bio::EnsEMBL::Gene->new;
    $E_gene->stable_id($V_gene->stable_id);
    $E_gene->slice($E_slice);
    $E_gene->version($V_gene->version);
    $E_gene->created_date($V_gene->created_date);
    $E_gene->modified_date($V_gene->modified_date);
    $E_gene->biotype($V_gene->biotype);
    $E_gene->status($V_gene->status);
    $E_gene->description($V_gene->description);
    $E_gene->source($V_gene->source);
    $E_gene->add_Attributes(@{ $V_gene->get_all_Attributes });

    # add reference to the original Vega gene
    $E_gene->add_DBEntry(Bio::EnsEMBL::DBEntry->new
            (-primary_id => $V_gene->stable_id,
             -version    => $V_gene->version,
             -dbname     => 'Vega_gene',
             -release    => 1,
             -display_id => $V_gene->stable_id));

    # add transcripts to gene
    foreach my $E_trans (@{ $E_transcripts }) {
        $E_gene->add_Transcript($E_trans);
    }

    foreach my $gx (@{$V_gene->get_all_DBEntries}) {
        $E_gene->add_DBEntry($gx);
    }

    if ($V_gene->display_xref) {
        $E_gene->display_xref($V_gene->display_xref);
    }

    # set the analysis on the gene object
    $E_gene->analysis($V_gene->analysis);

    # store the bloody thing
    my $name = $E_gene->stable_id;
    $name .= '/'.$E_gene->display_xref->display_id if($E_gene->display_xref);
    $support->log("Storing gene $name\n", 3);
    eval {
        $E_ga->store($E_gene);

        # protein features
        foreach my $transcript (@{ $E_gene->get_all_Transcripts }) {
            if ($transcript->translation and
                $protein_features->{$transcript->stable_id}) {
                $support->log_verbose("storing protein features\n", 3);
                foreach my $pf (@{ $protein_features->{$transcript->stable_id} }) {
                    $E_pfa->store($pf, $transcript->translation->dbID);
                }
            }
        }
    };
    $support->log_warning("(this might be a fatal error, so please check!) ".$@) if ($@);
    return;
}


sub transfer_xrefs {
	my $support =  shift;
    my $V_gene = shift;
    my $E_transcripts = shift;

    my %E_transcripts;
    my %E_translations;

    foreach my $tr (@$E_transcripts) {
        $E_transcripts{$tr->stable_id} ||= [];
        push @{$E_transcripts{$tr->stable_id}}, $tr;

        my $tl = $tr->translation;

        if($tl) {
            $E_translations{$tl->stable_id} ||= [];
            push @{$E_translations{$tl->stable_id}}, $tl;
        }
    }

    foreach my $tr (@{$V_gene->get_all_Transcripts}) {
        foreach my $E_tr (@{$E_transcripts{$tr->stable_id}}) {
            foreach my $xref (@{$tr->get_all_DBEntries}) {
				unless ($xref->primary_id) {
					$support->log_warning("No primary ID for this transcript xref: ".$xref->display_id." ".$xref->dbname."\n");
				}
                $E_tr->add_DBEntry($xref);
            }

            if ($tr->display_xref) {
                $E_tr->display_xref($tr->display_xref);
				#hack to set primary ID on display_xref (required for storing transcript display_xref)
				$E_tr->display_xref->primary_id($tr->stable_id);
            }
			else {
				$support->log_warning("No display_xref for transcript ".$tr->stable_id." set\n");
			}
        }

        my $tl = $tr->translation;
        if($tl) {
            foreach my $xref (@{$tl->get_all_DBEntries}) {
				unless ($xref->primary_id) {
					$support->log_warning("No primary ID for this translation xref: ".$xref->display_id." ".$xref->dbname."\n");
				}
                foreach my $E_tl (@{$E_translations{$tl->stable_id}}) {
                    $E_tl->add_DBEntry($xref);
                }
            }
        }
    }	
    return;
}


sub create_vega_xrefs {
    my $E_transcripts = shift;
    foreach my $transcript (@{ $E_transcripts }) {
        my $dbe = Bio::EnsEMBL::DBEntry->new
            (-primary_id => $transcript->stable_id,
             -version    => $transcript->version,
             -dbname     => 'Vega_transcript',
             -release    => 1,
             -display_id => $transcript->stable_id);
        $transcript->add_DBEntry($dbe);

        if($transcript->translation) {
            $dbe = Bio::EnsEMBL::DBEntry->new
                (-primary_id => $transcript->translation->stable_id,
                 -version    => $transcript->translation->version,
                 -dbname     => 'Vega_translation',
                 -release    => 1,
                 -display_id => $transcript->translation->stable_id);
            $transcript->translation->add_DBEntry($dbe);
        }
    }
}

1;
