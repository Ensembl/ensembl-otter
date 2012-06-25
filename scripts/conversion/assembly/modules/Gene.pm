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
# Builds Ensembl genes from the Vega genes and stores them in the database.
#
###############################################################################
#use Data::Dumper;
#$Data::Dumper::Maxdepth=2;

sub store_gene {
  my $support = shift;
  my $E_slice = shift;
  my $E_ga = shift;
  my $E_ta = shift;
  my $E_pfa = shift;
  my $V_gene = shift;
  my $E_transcripts = shift;
  my $protein_features = shift;

  # skip gene if it has no transcripts left after mapping
  unless (@{ $E_transcripts }) {
    $support->log("Skipping gene ".$V_gene->stable_id." (no transcripts transfered).\n", 2);
    return;
  }
  $support->log("About to store gene ".$V_gene->stable_id."\n", 2);
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
       -display_id => $V_gene->stable_id,
       -info_text  => 'Added during ensembl-vega production'));

  # make a note of the strands of the transcripts
  my %trans_strands;
  foreach my $E_trans (@{ $E_transcripts }) {
    push @{$trans_strands{$E_trans->seq_region_strand}},$E_trans->stable_id;
  }

  my $gstable_id = $E_gene->stable_id;

  #if there are multiple strands for transripts within the gene then keep those on the strand with the most transcripts.
  if (keys %trans_strands > 1 ) {
    my $compare_lengths = 0;
    $support->log("Multiple strands for transcripts of gene $gstable_id - see which is the most popular strand...\n", 3);
    my $strand_to_keep;
    my $no_trans = 0;
    foreach my $t_strand (keys %trans_strands) {
      if ($strand_to_keep) {
        if (scalar @{$trans_strands{$t_strand}} == $no_trans) {
          $compare_lengths = 1;
        }
        elsif (scalar @{$trans_strands{$t_strand}} > $no_trans) {
          $strand_to_keep = $t_strand;
        }
      }
      else {
        $strand_to_keep = $t_strand;
        $no_trans = scalar @{$trans_strands{$t_strand}};
      }
    }

    if ($compare_lengths) {
      #otherwise set the strand equal to that of the longest transcript
      $support->log("...equal numbers, now compare lengths of transcripts:\n", 3);
      $strand_to_keep = '';
      my $max_length = 1;
      foreach my $E_trans (@{ $E_transcripts }) {
        my $stable_id = $E_trans->stable_id;
        my $length = $E_trans->length;
        my $strand = $E_trans->strand;
        $support->log("Transcript $stable_id on strand $strand has length of $length\n",4);
        if ($strand_to_keep) {
          if ($length > $max_length) {
            $length = $max_length;
            $strand_to_keep = $strand;
          }
        }
        else {
          $max_length = $length;
          $strand_to_keep = $strand;
          $compare_lengths = 1;
        }
      }
    }
    $support->log("Chosen strand $strand_to_keep\n", 3);

    my @trans_to_keep = @{$trans_strands{$strand_to_keep}};
    foreach my $E_trans (@{ $E_transcripts }) {
      if (grep { $_ eq $E_trans->stable_id } @trans_to_keep) {
        $E_gene->add_Transcript($E_trans);
      }
      else {
        $support->log_warning('Not storing transcript '.$E_trans->stable_id." since gene $gstable_id has transcripts on multiple strands and this is not on the chosen one\n", 3);
      }
    }
  }

  else {
    #otherwise just add all transcripts to the gene
    foreach my $E_trans (@{ $E_transcripts }) {
      $E_gene->add_Transcript($E_trans);
    }
  }

  foreach my $gx (@{$V_gene->get_all_DBEntries}) {
    if (my @synys = @{$gx->get_all_synonyms}) {
      $support->log_verbose("Xref synonyms found for ".$V_gene->stable_id."\n");
    }
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
  $support->log_verbose("Storing gene $name\n", 3);
  eval {
    $E_ga->store($E_gene);

    # protein features
    foreach my $transcript (@{ $E_gene->get_all_Transcripts }) {
      if ($transcript->translation and
	    $protein_features->{$transcript->stable_id}) {
	$support->log_verbose("Storing protein features\n", 3);
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
        $xref->get_all_synonyms;
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
        $xref->get_all_synonyms;
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
       -display_id => $transcript->stable_id,
       -info_text  => 'Added during ensembl-vega production');
    $transcript->add_DBEntry($dbe);

    if($transcript->translation) {
      $dbe = Bio::EnsEMBL::DBEntry->new
	(-primary_id => $transcript->translation->stable_id,
	 -version    => $transcript->translation->version,
	 -dbname     => 'Vega_translation',
	 -release    => 1,
	 -display_id => $transcript->translation->stable_id,
         -info_text  => 'Added during ensembl-vega production');
      $transcript->translation->add_DBEntry($dbe);
    }
  }
}

1;
