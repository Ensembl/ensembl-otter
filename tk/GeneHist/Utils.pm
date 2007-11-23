package GeneHist::Utils;

#!/usr/local/bin/perl -w

# Author: ck1@sanger.ac.uk

use vars qw{ @ISA @EXPORT_OK };

@ISA = ('Exporter');
@EXPORT_OK = qw(find_obsolete_gene
                get_all_gsids_via_transSID_of_geneSID
                get_all_gsids_via_geneTransNames_of_gsid
                check_exons_overlap
                convert_unix_time
                uniq
                array_comp
                get_all_sub_nodes
                sid_2_atype
                get_attributes
                );

use strict;


sub find_obsolete_gene {
  my ( $ga, $gsids ) = @_;

  foreach my $gsid ( @$gsids ){
	foreach my $g ( @{$ga->fetch_all_versions_by_stable_id($gsid)} ){
	  return 1 if $g->biotype eq 'obsolete';
	}
  }
}

sub get_all_gsids_via_transSID_of_geneSID {

  # including obsolete ones

  my ($gsid, $ga)= @_;
  my ($g_to_check, $gsid_seen);

  foreach my $gene ( @{$ga->fetch_all_versions_by_stable_id($gsid)} ){
	foreach my $t ( @{$gene->get_all_Transcripts} ){
	  foreach my $g (@{$ga->fetch_by_transcript_stable_id_constraint($t->stable_id)} ){
		my $gsid = $g->stable_id;
		$gsid_seen->{$gsid}++;
		if ( $gsid_seen->{$gsid} == 1 ){
		  push(@$g_to_check, $gsid);
		}
	  }
	}
  }
  return $g_to_check;
}

sub get_all_gsids_via_geneTransNames_of_gsid {

  my ($ga, $gsids) = @_;

  my %query_gsids = map {$_, 1} @$gsids;

  my (@gnames, @tnames, $seen_names);

  # first get gene/trans names by given gsids
  foreach my $gsid ( @$gsids ){
    warn "GSID: $gsid";
	foreach my $g ( @{$ga->fetch_all_versions_by_stable_id($gsid)} ){
 #     warn $g->stable_id;
#      warn $g->version;
#      warn $g->is_current;
#      warn $g->modified_date;

      # find names from all versions, all modified_date
      my $gname = $g->get_all_Attributes('name')->[0]->value;
      $seen_names->{$gname}++;
      push(@gnames, $gname) if $seen_names->{$gname} == 1;

      foreach my $t ( @{$g->get_all_Transcripts} ){
        my $tname = $t->get_all_Attributes("name")->[0]->value;
        $seen_names->{$tname}++;
        push(@tnames, $tname) if $seen_names->{$tname} == 1;
      }
    }
  }

  my ($seen, @Gsids);

  # then get gsids via gene/trans names found above
  foreach ( @gnames ){
	warn "<Follow history via gene name: $_>";
    foreach ( @{$ga->fetch_stable_id_by_name($_, 'gene')} ){
      next if $query_gsids{$_};
      $seen->{$_}++;

      # @Gsids: gsids found recursively via gene/trans names
      # of all versions of the gsids passed into this method
      push(@Gsids, $_) if $seen->{$_} == 1;
    }
  }
  foreach ( @tnames ){
	warn "<Follow history via transcript name: $_>";
    foreach ( @{$ga->fetch_stable_id_by_name($_, 'transcript')} ){
      next if $query_gsids{$_};
      $seen->{$_}++;
      push(@Gsids, $_) if $seen->{$_} == 1;
    }
  }

  # check exon overlap for additional gsids found via gene/trans names
  if ( @Gsids ){
    my @all_gsids = (@$gsids, @Gsids);
	print STDERR "<DIFF: @Gsids: checking exons overlap>\n";
	# check if exons overlaps
    if ( my $ok_gsids = check_exons_overlap($ga, $gsids, \@Gsids) ){
       return $ok_gsids;
    }
    else {
      print STDERR " . . .no verlap - ignore\n";
    }
  }
  return $gsids;
}

sub check_exons_overlap {
  my ($ga, $query_gsids, $new_gsids) = @_;

  my %to_check = map {$_, 1} @$query_gsids;

  my ($SE_gsid, $seen_gsid);
  foreach my $gsid (@$query_gsids, @$new_gsids){
	foreach my $g ( @{$ga->fetch_all_versions_by_stable_id($gsid)} ){
	  foreach my $e ( @{$g->get_all_Exons} ){
		my $se_str = $e->start."-".$e->end;
		push(@{$SE_gsid->{$se_str}}, $gsid);
	  }
	}
  }

  my ($ov, $seen);
  foreach my $se_str ( keys %$SE_gsid ){
    my $ref_gsid;
    my $seen;
    foreach ( uniq($SE_gsid->{$se_str}) ){
  #    warn "DIFF $_";
      $to_check{$_} ? ($ref_gsid = 1) : ( $seen->{$_}++ );
    }
    if ($ref_gsid and scalar keys %$seen >= 1 ){
      $ov = 1;
      my @ovg = keys %$seen;
      push(@$query_gsids, @ovg);
      print STDERR ". . . @ovg OK\n";
    }
  }
  @$query_gsids = uniq($query_gsids);
  $ov ? return $query_gsids : return 0;
}

sub convert_unix_time {
  my ($sec, $min, $hr, $day, $mon, $yr) = (localtime(shift))[0..5];
  $yr += 1900;
  $mon += 1;
  return sprintf("%d-%02d-%02d %02d:%02d:%02d", $yr, $mon, $day, $hr, $min, $sec);
}

sub uniq {
  my $ary_ref = shift;
  my $seen;
  map { $seen->{$_}++ } @$ary_ref;
  return keys %$seen;
}

sub array_comp {
  my ( $ary1_ref, $ary2_ref)=@_;
  my( @diff, %count);

  %count=();
  foreach my $e (@$ary1_ref, @$ary2_ref){
    $count{$e}++;
  }
  foreach my $e (keys %count){
    if ($count{$e} != 2){
	  push @diff, $e;
	}
  }

  return @diff;
}
sub sid_2_atype {

  my ($dataset, $stable_id)= @_;

  my ($stable_id_type, $mol);

  if ( $stable_id =~ /OTT.*G/ ) {
	$stable_id_type = "gene_stable_id";
	$mol = "gene";
  } elsif ( $stable_id =~ /OTT.*T/ ) {
	$stable_id_type = "transcript_stable_id";
	$mol = "transcript";
  }

  my $mol_col = $mol."_id";
  my $host = 'otterpipe2';
  my $user = 'ottro';
  my $pass = '';
  my $port = 3303;

  my $dbnames = {
                 human_sp1 => 'ck1_human_new_history',
                # human_sp1 => 'sp1_human_new',
                };

  my $db = $dbnames->{$dataset};


  my $otter_db = new Bio::EnsEMBL::DBSQL::DBConnection(
													   -host   => $host,
													   -user   => $user,
													   -pass   => $pass,
													   -port   => $port,
													   -dbname => $db);

  my $qry = $otter_db->prepare(qq{
								  SELECT sr.name
								  FROM $stable_id_type sid, $mol m, seq_region sr, assembly a
								  WHERE sid.stable_id = ?
								  AND sid.$mol_col=m.$mol_col
								  AND m.seq_region_id=sr.seq_region_id
								  AND sr.seq_region_id=a.asm_seq_region_id
								  AND sr.coord_system_id=2
								 });

  $qry->execute($stable_id);
  return $qry->fetchrow
}

sub get_all_sub_nodes {

  my $tree = shift;
  my @nodes = $tree->info('children');

  my @all_sub_nodes;
  foreach my $n ( @nodes ){
    if ( $n =~ /G\d+/){
      push(@all_sub_nodes, $n);
      foreach my $sn ( $tree->info('children', $n)){
		push(@all_sub_nodes, $sn);
		foreach my $ssn ( $tree->info('children', $sn) ){
		  push(@all_sub_nodes, $ssn);
		  push(@all_sub_nodes, "$ssn.TransInfo") if $ssn =~ /OTT/;
		}
	  }
	}
  }
  #warn "@all_sub_nodes";
  return @all_sub_nodes;
}

sub get_attributes {
 my ($gORt, $code) = @_;

 my $attrib;

 foreach my $at ( @{$gORt->get_all_Attributes($code)} ){
   push(@$attrib, $at->value) if $at->value;
 };

 @$attrib = 'NA' unless $attrib->[0];

 return $attrib;
}


1;
