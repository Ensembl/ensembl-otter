=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

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

package GeneHist::DataUtils;

# Author: ck1@sanger.ac.uk

use vars qw{ @ISA @EXPORT_OK };

@ISA = ('Exporter');
@EXPORT_OK = qw(
                get_all_gsids_via_geneTransNames_of_gsid
                check_exons_overlap
                convert_unix_time
                uniq
                array_comp
                get_all_sub_nodes
                sid_2_atype
                get_attributes
				pretty_print_xmlcmp
				add_tree_nodes
				build_geneinfo_nodes
				build_transinfo_nodes
				build_geneinfo_tree
				process_query
                get_gsids_by_created_ver_modtime
                get_list_of_obsolete_genes_by_assembly
                add_mlist_items
                show_err_message
                );

use strict;
use warnings;

sub process_query {

	my ($query_str, $otter_db, $mw, $verbose) = @_;
	my $ga = $otter_db->get_GeneAdaptor;

	my $gsids; # list ref

	# first get relevant info of a gene from query
	if ( $query_str =~ /OTT\w{3,3}G\d+/ and
         check_query_exists($otter_db, $mw, $query_str, 'gene') ){
      @$gsids = $query_str;
      print STDERR "[G query]: " if $verbose;
	}
	elsif ( $query_str =~ /OTT\w{3,3}T\d+/ and
            check_query_exists($otter_db, $mw, $query_str, 'trans') ){
      my $genes = $ga->fetch_by_transcript_stable_id_constraint($query_str);
      @$gsids = map { $_->stable_id } @$genes;
      print STDERR "[T query]: " if $verbose;
	}
	else {
      my $Gsids;
      if ( check_query_exists($otter_db, $mw, $query_str, 'name') ){
        if ( $Gsids = $ga->fetch_stable_id_by_name($query_str, 'gene') ){
          push(@$gsids, uniq($Gsids));
          print STDERR "[GN query]: " if $verbose;
        }
        elsif ( $Gsids = $ga->fetch_stable_id_by_name($query_str, 'transcript')) {
          push(@$gsids, uniq($Gsids));
          print STDERR "[TN query]: " if $verbose;
        }
      }
    }
	print STDERR "got @$gsids\n" if $verbose;

	#----------------------------------------------------------------------
	# now get all gsids associate with gene_name and trans names via gsid
	# this should pull out obsolete genes in the history
	#----------------------------------------------------------------------
    print STDERR "[1] GETTING ALL gsids VIA gene/trans NAMES OF @$gsids . . .\n" if $verbose;

	my $found_gsids = get_all_gsids_via_geneTransNames_of_gsid($otter_db, $ga, $gsids, $verbose);
	print STDERR "[5] GENE HISTORY: @$found_gsids\n\n" if $verbose;

    print STDERR "Found @$found_gsids\n";
	return $found_gsids;
}

sub check_query_exists {
  my ($otter_db, $mw, $query, $mode) = @_;
  my $mode_sql = { gene  => [qq{SELECT count(*) FROM gene WHERE stable_id=?}],
				   trans => [qq{SELECT count(*) FROM transcript WHERE stable_id=?}],
                   name  => [
                             qq{SELECT count(*) FROM gene_attrib ga, attrib_type at
                               WHERE ga.value=? AND ga.attrib_type_id=at.attrib_type_id
                               AND (at.code='name' OR at.code='synonym')},
                             qq{SELECT count(*) FROM transcript_attrib ta, attrib_type at
                               WHERE ta.value=? AND ta.attrib_type_id=at.attrib_type_id
                               AND (at.code='name' OR at.code='synonym')}
                             ],
				 };

  foreach my $q ( @{$mode_sql->{$mode}} ){
    my $sth = $otter_db->dbc->prepare($q);
    $sth->execute($query);
    if ( $sth->fetchrow ) {
      return 1;
    }
  }

  gene_not_found_err($mw);
}

sub gene_not_found_err {
	my $mw = shift;
	my $font_hl = $mw->fontCreate(-family=>'helvetica', -size=>9);

  $mw->messageBox(-title   => 'Gene not found!',
                  -font    => $font_hl,
                  -message => "Please double check you query and try again.\n".
                            "If this is a software error, please report to anacoders.\nThanks.",
                  -default_button => 'OK' );
}

sub show_err_message {
  my ($parent, $title, $msg) = @_;

  my $font_hl = $parent->fontCreate(-family=>'helvetica', -size=>9);

  $parent->messageBox(-title   => $title,
                      -font    => $font_hl,
                      -message => $msg,
                      -default_button => 'OK' );
}

sub get_list_of_obsolete_genes_by_assembly {

  # dead genes are those whose latest version is obsolete
  my ($otter_db, $ga, $assembly)= @_;

  my $dead_gids = $otter_db->dbc->prepare(qq{
                                             SELECT sr.name, gene_id
                                             FROM gene g, seq_region sr
                                             WHERE sr.name = ?
                                             AND g.seq_region_id=sr.seq_region_id
                                             AND g.biotype='obsolete'
                                           });
  $dead_gids->execute($assembly);

  my $dead_genes;

  while ( my ($assembly, $gid) = $dead_gids->fetchrow ){
    push @$dead_genes, $ga->reincarnate_gene( $ga->fetch_by_dbID($gid) );
  }
  return $dead_genes;
}

sub get_all_gsids_via_geneTransNames_of_gsid {

  my ($otter_db, $ga, $gsids, $verbose) = @_;

  my %query_gsids = map {$_, 1} @$gsids;

  my (@gnames, @tnames, $seen_names);

  # first get gene/trans names by given gsids
  foreach my $gsid ( @$gsids ){
    @gnames = get_all_gname_sym_from_all_ver_of_gene($otter_db, $gsid);

    my @gids;
	foreach my $g ( @{$ga->fetch_all_versions_by_stable_id($gsid)} ){
      push(@gids, $g->dbID);
    }
    @tnames = get_all_tname_sym_from_all_ver_of_gene( $otter_db, join(',',@gids) );
  }
  my ($seen, @Gsids);

  # then get gsids via gene/trans names found above
  foreach ( @gnames ){
	warn "[2] FOLLOW HISTORY VIA GENE NAME: $_" if $verbose;
    foreach ( @{$ga->fetch_stable_id_by_name($_, 'gene')} ){
      next if $query_gsids{$_};
      $seen->{$_}++;

      # @Gsids: gsids found recursively via gene/trans names
      # of all versions of the gsids passed into this method
      push(@Gsids, $_) if $seen->{$_} == 1;
    }
  }
  foreach ( @tnames ){
	warn "[3] FOLLOW HISTORY VIA TRANSCRIPT NAME: $_" if $verbose;
    foreach ( @{$ga->fetch_stable_id_by_name($_, 'transcript')} ){
      next if $query_gsids{$_};
      $seen->{$_}++;
      push(@Gsids, $_) if $seen->{$_} == 1;
    }
  }

  # check exon overlap for additional gsids found via gene/trans names
  if ( @Gsids ){
    my @all_gsids = (@$gsids, @Gsids);
	print STDERR "[4] GOT RELATED GENES: @Gsids: --> CHECKING EXONS OVERLAP\n" if $verbose;
	# check if exons overlaps
    if ( my $ok_gsids = check_exons_overlap($ga, $gsids, \@Gsids) ){
       return $ok_gsids;
    }
    else {
      print STDERR " . . .no verlap - ignore\n" if $verbose;
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
      $g = $ga->reincarnate_gene($g);
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
    #  warn "DIFF $_";
      $to_check{$_} ? ($ref_gsid = 1) : ( $seen->{$_}++ );
    }
    if ($ref_gsid and scalar keys %$seen >= 1 ){
      $ov = 1;
      my @ovg = keys %$seen;
      push(@$query_gsids, @ovg);
    #  print STDERR ". . . @ovg OK\n";
    }
  }
  @$query_gsids = uniq($query_gsids);
  $ov ? return $query_gsids : return 0;
}

sub get_all_gname_sym_from_all_ver_of_gene {
  my ($otter_db, $gsid) = @_;
  my $qry = $otter_db->dbc->prepare(qq{
                                       SELECT DISTINCT ga.value
                                       FROM gene g, gene_attrib ga, attrib_type at
                                       WHERE g.stable_id=?
                                       AND g.gene_id=ga.gene_id
                                       AND ga.attrib_type_id=at.attrib_type_id
                                       AND at.code in ('name', 'synonym')
                                     });
  my @names;
  $qry->execute($gsid);
  while ( my $val = $qry->fetchrow){
    push(@names, $val);
  }

  return @names;
}

sub get_all_tname_sym_from_all_ver_of_gene {
  my ($otter_db, $gids) = @_;

  my $qry = $otter_db->dbc->prepare(qq{
                                       SELECT distinct ta.value
                                       FROM gene g, transcript t, transcript_attrib ta, attrib_type at
                                       WHERE g.gene_id in ($gids)
                                       AND g.gene_id=t.gene_id
                                       AND t.transcript_id=ta.transcript_id
                                       AND ta.attrib_type_id=at.attrib_type_id
                                       AND at.code in ('name', 'synonym')
                                     });
  my @names;
  $qry->execute();
  while ( my $val = $qry->fetchrow() ){
    push(@names, $val);
  }

  return @names;
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
sub sid_2_atype_UNSAFE { # implementation is not safe (e.g. Gorilla has OTTGORT00000000037), but also is apparently not called from anywhere

  my ($dataset, $stable_id)= @_;

  my ($mol);

  if ( $stable_id =~ /OTT.*G/ ) {
	$mol = "gene";
  } elsif ( $stable_id =~ /OTT.*T/ ) {
	$mol = "transcript";
  }

  my $mol_col = $mol."_id";
  my $host = 'otterpipe2';
  my $user = 'ottro';
  my $pass = '';
  my $port = 3323;

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
								  FROM $mol m, seq_region sr, assembly a
								  WHERE m.stable_id = ?
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

  return @all_sub_nodes;
}

sub get_gsids_by_created_ver_modtime {
  my ($ga, $gsids) = @_;

  my $created_ver_modtime_g = {};
  foreach my $gsid ( @$gsids ){

    foreach my $gene ( @{$ga->fetch_all_versions_by_stable_id($gsid)} ){
      $gene = $ga->reincarnate_gene($gene);
      # some genes have same created_time, modified_date
      # eg, OTTHUMG00000045274, OTTHUMG00000045276
      push(@{$created_ver_modtime_g->{$gene->created_date}->{$gene->version}->{$gene->modified_date}}, $gene);
    }
  }
  return $created_ver_modtime_g;
}

sub get_attributes {
 my ($gORt, $code) = @_;

 my $attrib;

 foreach my $at ( @{$gORt->get_all_Attributes($code)} ){
   push(@$attrib, $at->value) if $at->value;
 };

 @$attrib = 'NA' unless $attrib->[0];

 return join(', ', @$attrib);
}

sub build_geneinfo_tree {

	my ($tree, $top, $curr_gene, $gver, $mod_count) = @_;

	my $mtime       = convert_unix_time($curr_gene->modified_date);
	my $trans_count = scalar @{$curr_gene->get_all_Transcripts};
	my $exon_count  = scalar @{$curr_gene->get_all_Exons};
	my $desc = $curr_gene->description;
	$desc = 'NA' unless $desc;

	my $gname          = get_attributes($curr_gene,'name');
	my $gsyms          = get_attributes($curr_gene,'synonym');
	my $gremark        = get_attributes($curr_gene,'remark');
	my $g_annot_remark = get_attributes($curr_gene,'hidden_remark');

	my $space = "-" x 5;
	my $snode = "V$gver"."-$mod_count"."GeneInfo";
	my $gver_mod = "$gver"."-$mod_count";

	$tree->add($top.".V$gver_mod", -text=>"V$gver_mod (T: $trans_count, E: $exon_count, $mtime)", -data=>$curr_gene);
	$tree = build_geneinfo_nodes($tree, $curr_gene, $top.".V$gver_mod", $space, $desc, $gname, $gsyms, $gremark, $g_annot_remark);
	$tree = build_transinfo_nodes($tree, $curr_gene, $top.".V$gver_mod", $space);
	return $tree;
}

sub build_geneinfo_nodes {
  my ($tree, $gene, $heirarchy, $space, $desc, $gname, $gsyms, $gremark, $g_annot_remark) = @_;

  my $asm = $gene->slice->seq_region_name;

  $heirarchy .= '.GeneInfo';
  my @nodes = (
			   ["$heirarchy", "GeneInfo"],
			   ["$heirarchy.Assembly", "Assembly $space $asm"],
			   ["$heirarchy.GeneName", "GeneName $space $gname"],
			   ["$heirarchy.Synonym",  "Synonym $space $gsyms"],
			   ["$heirarchy.GeneType", "GeneType $space ".$gene->status],
			   ["$heirarchy.Desc",     "Desc  $space $desc"],
			   ["$heirarchy.Remark",   "Remark $space $gremark"],
			   ["$heirarchy.Annot_Remark",   "Annot_Remark $space $g_annot_remark"]
			   );
  return add_tree_nodes($tree, \@nodes);
}

sub build_transinfo_nodes {

  my ($tree, $gene, $heirarchy, $space) = @_;

  my $tsid_t;
  foreach my $t ( @{$gene->get_all_Transcripts} ) {
    push(@{$tsid_t->{$t->length}}, $t);
  }

  # sort transcript by length, longest first
  foreach my $len ( sort {$b<=>$a} keys %$tsid_t ) {

    foreach my $t ( @{$tsid_t->{$len}} ) {

      my $tsid = $t->stable_id;

      # get evidences and remark
      my $ta = $t->adaptor->db->get_TranscriptAdaptor();
      my ($evid, $evidence);
      eval { $evid = $ta->fetch_evidence($t) };
      $evid ? ($evidence = scalar @$evid):($evidence = 0);

      my $tname          = get_attributes($t,'name');
      my $tsyms          = get_attributes($t,'synonym');
      my $tremark        = get_attributes($t,'remark');
      my $t_annot_remark = get_attributes($t,'hidden_remark');

      my @nodes = (
                   ["$heirarchy.$tsid", $t->stable_id],
                   ["$heirarchy.$tsid.TransInfo", 'TransInfo'],
                   ["$heirarchy.$tsid.TransInfo.Length",       "Length $space ".$t->length." bp"],
                   ["$heirarchy.$tsid.TransInfo.TransName",    "TransName $space $tname"],
                   ["$heirarchy.$tsid.TransInfo.ExonCount",    "ExonCount $space ".scalar @{$t->get_all_Exons}],
                   ["$heirarchy.$tsid.TransInfo.Annotator",    "Annotator $space ".$t->transcript_author->name],
                   ["$heirarchy.$tsid.TransInfo.Biotype",      "Biotype $space ".$t->biotype],
                   ["$heirarchy.$tsid.TransInfo.TransRemark",  "Remark $space $tremark"],
                   ["$heirarchy.$tsid.TransInfo.TransAnnotRemark",  "Annot_Remark $space $t_annot_remark"],
                   ["$heirarchy.$tsid.TransInfo.Evidence",     "Evidence $space ".$evidence]
                  );
      # *not_found tags
      foreach ( "mRNA_start_NF", "mRNA_end_NF", "cds_start_NF", "cds_end_NF" ) {
        if (my $attr = $t->get_all_Attributes("$_")->[0]) {
          push(@nodes, ["$heirarchy.$tsid.TransInfo.$_", "$_ $space ".$attr->value]);
        }
      }
      $tree = add_tree_nodes($tree, \@nodes);
    }
  }

  return $tree;
}

sub add_tree_nodes {
  my ( $tree, $nodes, $data) = @_;

  foreach my $node (@$nodes){
	  my $hierarchy = $node->[0];
	  my $val       = $node->[1];
	  $tree->add($hierarchy, -text=>$val, -data=>$data);
  }
  return $tree;
}

sub pretty_print_xmlcmp {
	my ($pagetxt, @xmlcmp)= @_;

	# greyout (tags) /highlight (data) of XML
	$pagetxt->tagConfigure('greyout', -foreground=>'#616161');
	$pagetxt->tagConfigure('highlight', -foreground=>'#8B0000');

	foreach my $line ( @xmlcmp ){

		if ( $line =~ /locus|transcript|evidence_set|evidence|exon_set|exon/ ){
			$pagetxt->insert('end', $line, 'greyout');
		}
		# identical in left and right
		elsif ( $line =~ /(^\s+<.*>)(.*)(<\/.*>\s+)(<.*>)(.*)(<\/.*>)/ ){
			$pagetxt->insert('end', $1, 'greyout');
			$pagetxt->insert('end', $2, 'highlight');
			$pagetxt->insert('end', $3, 'greyout');
			$pagetxt->insert('end', $4, 'greyout');
			$pagetxt->insert('end', $5, 'highlight');
			$pagetxt->insert('end', "$6\n", 'greyout');
		}
		# diff in left and right (|)
		elsif ( $line =~ /(^\s+<.*>)(.*)(<\/.*>\s+)(\|)(\s+<.*>)(.*)(<\/.*>)/ ){
			$pagetxt->insert('end', $1, 'greyout');
			$pagetxt->insert('end', $2, 'highlight');
			$pagetxt->insert('end', $3, 'greyout');
			$pagetxt->insert('end', $4, 'greyout');
			$pagetxt->insert('end', $5, 'greyout');
			$pagetxt->insert('end', $6, 'highlight');
			$pagetxt->insert('end', "$7\n", 'greyout');
		}
		# new in left (<)
		elsif ( $line =~ /(^\s+<.*>)(.*)(<\/.*>\s+)(<\s+)/ ){
			$pagetxt->insert('end', $1, 'greyout');
			$pagetxt->insert('end', $2, 'highlight');
			$pagetxt->insert('end', $3, 'greyout');
			$pagetxt->insert('end', $4);
		}
		# new in right (>)
		elsif ( $line =~ /(\s+>\s+)(<.*>)(.*)(<\/.*>)/ ){
			$pagetxt->insert('end', $1);
			$pagetxt->insert('end', $2, 'greyout');
			$pagetxt->insert('end', $3, 'highlight');
			$pagetxt->insert('end', "$4\n", 'greyout');
		}
	}

	return $pagetxt;
}


sub add_mlist_items {
  my ($og) = @_;

  my $gsid     = $og->stable_id;
  my $gid      = $og->dbID;
  my $gname    = get_attributes($og,'name');
  my $Syms     = get_attributes($og,'synonym');
  my $created  = convert_unix_time($og->created_date);
  my $modified = convert_unix_time($og->modified_date);

  my $t_len;
  foreach my $t ( @{$og->get_all_Transcripts} ){
    push(@{$t_len->{$t->length}}, $t->stable_id);
  }

  my $tsids = join(', ', map { @{$t_len->{$_}} } sort {$a<=>$b} keys %$t_len);

  return [$gsid, $gid, $gname, $Syms, $created, $modified, $tsids];
}



1;
