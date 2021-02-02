=head1 LICENSE

Copyright [2018-2021] EMBL-European Bioinformatics Institute

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

package Bio::Vega::Utils::History;

use strict;
use warnings;
use base 'Exporter';
our @EXPORT_OK = qw{ history };

use Bio::EnsEMBL::Utils::Exception qw(throw);
use Bio::Vega::Utils::Attribute    qw(get_name_Attribute_value);

sub history{
  my ($genes, $short) = @_;
  my $c=0;
  my $printarray;
  my $stable_version;push @$stable_version,"stable_id.version";
  my $slice_name;push @$slice_name,"slice_name";
  my $gene_name;push @$gene_name,"gene_name";
  my $gene_start;push @$gene_start,"gene_start";
  my $gene_end;push @$gene_end,"gene_end";
  my $gene_strand;push @$gene_strand,"gene_strand";
  my $gene_biotype;push @$gene_biotype,"gene_biotype";
  my $gene_status;push @$gene_status,"gene_status";
  my $gene_source;push @$gene_source,"gene_source";
  my $gene_description;push @$gene_description,"gene_description";
  my $transcript_count;push @$transcript_count,"transcript_count";
  my $attribute_count;push @$attribute_count,"attribute_count";
  my $remark;push @$remark,"remark";
  my $hidden_remark;push @$hidden_remark,"hidden_remark";
  my $synonym;push @$synonym,"synonym";
  my $alltxs;
  my $allexons;
  foreach my $gene (@$genes){
      my $s_v=$gene->stable_id.".".$gene->version;
      push @$stable_version,$s_v;
      push @$slice_name,$gene->slice->name;
      my $attribs     = $gene->get_all_Attributes;
      my $attrib_count = @$attribs ;
      push @$attribute_count,$attrib_count;
      my $gn = get_name_Attribute_value($gene);
      push @$gene_name,$gn if $gn;
      push @$gene_start,$gene->start;
      push @$gene_end,$gene->end;
      push @$gene_strand,$gene->strand;
      push @$gene_biotype,$gene->biotype;
      push @$gene_status,$gene->status;
      push @$gene_source,$gene->source;
      push @$gene_description,$gene->description;
      my $trans      = $gene->get_all_Transcripts;
      my $tran_count = @$trans;
      foreach my $t (@$trans){
          if (!exists $alltxs->{$t->stable_id}){
              $alltxs->{$t->stable_id}=[];
          }
          my $exons=$t->get_all_Exons;
          foreach my $e (@$exons){
              if (!exists $allexons->{$e->stable_id}){
                  $allexons->{$t->stable_id}->{$e->stable_id}=[];
              }
          }
      }
      push @$transcript_count,$tran_count;
      my $remarks = $gene->get_all_Attributes('remark');
      my $string="";
      if (defined $remarks) {
          foreach my $rem (@$remarks){
              $string=$string.$rem."--";
          }
          push @$remark,$string;
      }
      $string="";
      my $hidden_remarks = $gene->get_all_Attributes('hidden_remark');
      if (defined $hidden_remarks) {
          foreach my $rem (@$hidden_remarks){
              $string=$string.$rem."--";
          }
          push @$hidden_remark,$string;
      }
      $string="";
      my $synonyms = $gene->get_all_Attributes('synonym');
      if (defined $synonyms) {
          foreach my $syn (@$synonyms){
              $string=$string.$syn."--";
          }
          push @$synonym,$string;
      }
  }
  $printarray=[
      $stable_version,$slice_name,$gene_name,$gene_start,$gene_end,
      $gene_strand,$gene_biotype,$gene_status,$gene_source,$gene_description,
      $transcript_count,$attribute_count,$remark,$hidden_remark,$synonym,
      ];

  my $j=0;
  foreach my $g (@$genes){
      my $txs=$g->get_all_Transcripts;
      foreach my $t (@$txs){
          if (exists $alltxs->{$t->stable_id}){
              $alltxs->{$t->stable_id}->[$j]=$t;
              foreach my $e (@{$t->get_all_Exons}){
                  if (exists $allexons->{$t->stable_id}->{$e->stable_id}){
                      $allexons->{$t->stable_id}->{$e->stable_id}->[$j]=$e;
                  }

              }
          }
      }
      $j++;##genecount
  }
  my $gene_count=scalar(@$genes);
  while (my ($key, $ta) = each %{$alltxs}) {
      my $tsv;
      my $t_s_v_ref;push @$t_s_v_ref,"trans-stable-version";
      my $s_s_v_ref;push @$s_s_v_ref,"translation-stable-version";
      my $t_start_ref;push @$t_start_ref,"transcript_start";
      my $t_slice_name;push @$t_slice_name,"tran_slice_name";
      my $t_end;push @$t_end,"tran-end";
      my $t_strand;push @$t_strand,"tran-strand";
      my $t_biotype; push @$t_biotype,"tran-biotype";
      my $t_status;push @$t_status,"tran-status";
      my $t_exon_count; push @$t_exon_count,"tran-exon-count";
      my $t_desc;push @$t_desc,"tran-description";
      my $t_name;push @$t_name,"tran-name";
      my $t_att_count;push @$t_att_count,"tran-att-count";
      my $t_msnf;push @$t_msnf,"tran-msNF";
      my $t_menf;push @$t_menf,"tran-meNF";
      my $t_csnf;push @$t_csnf,"tran-csNF";
      my $t_cenf;push @$t_cenf,"tran-ceNF";
      my $t_evi_count;push @$t_evi_count,"tran_evi_count";
      my $t_remarks;push @$t_remarks,"tran-remarks";
      my $t_hidden_remarks;push @$t_hidden_remarks,"tran-hid-remarks";
      my $t_evidence;push @$t_evidence,"tran-evidence";

      for (my $i=0;$i<$gene_count;$i++){
          if ($ta->[$i]){
              $tsv=$ta->[$i]->stable_id;
              push @$t_s_v_ref ,$ta->[$i]->stable_id.".".$ta->[$i]->version;
              push @$t_start_ref,$ta->[$i]->start;
              push @$t_slice_name,$ta->[$i]->slice->name;
              push @$t_end,$ta->[$i]->end;
              my $t=$ta->[$i];
              my $exonsvstring="";
              my $strand     = $t->strand;
              my $biotype    = $t->biotype;
              my $status     = $t->status;
              my $exons      = $t->get_all_Exons;
              my $exon_count = @$exons;
              foreach my $ex (@$exons){
                  $exonsvstring=$exonsvstring.$ex->stable_id;
              }
              my $description = $t->description;
              my $attribs     = $t->get_all_Attributes;
              my $attrib_count = @$attribs ;
              my $transcript_name = $t->get_all_Attributes('name') ;
              my $mRNA_start_NF = $t->get_all_Attributes('mRNA_start_NF') ;
              my $mRNA_end_NF = $t->get_all_Attributes('mRNA_end_NF') ;
              my $cds_start_NF = $t->get_all_Attributes('cds_start_NF') ;
              my $cds_end_NF = $t->get_all_Attributes('cds_end_NF') ;
              my $evidence= $t->evidence_list();
              my $evidence_count=0;
              my $evistring="";
              my $remarks;
              my $remstring="";
              my $hidden_remarks;
              my $translation=$t->translation;
              my $trans_sv_string="";
              if ($translation){
                  $trans_sv_string=$trans_sv_string.$translation->stable_id.".".$translation->version;
              }
              if (defined $evidence) {
                  $evidence_count= scalar(@$evidence);
                  $evistring="";
                  foreach my $evi (@$evidence){
                      my $e=$evi->name."-".$evi->type;
                      $evistring=$evistring.$e."--";
                  }
              }
              $remarks = $t->get_all_Attributes('remark');
              if (defined $remarks) {
                  foreach my $rem (@$remarks){
                      $remstring=$remstring.$rem->value."--";
                  }
              }
              my $hremstring="";
              $hidden_remarks = $t->get_all_Attributes('hidden_remark');
              if (defined $hidden_remarks) {
                  foreach my $rem (@$remarks){
                      $hremstring=$hremstring.$rem->value."--";
                  }
              }
              my ($msNF,$meNF,$csNF,$ceNF,$tn);
              if (defined $mRNA_start_NF){
                  $msNF=$mRNA_start_NF->[0]->value;
              }
              else {
                  $msNF='';
              }
              if (defined $mRNA_end_NF){
                  $meNF=$mRNA_end_NF->[0]->value;
              }
              else {
                  $meNF='';
              }
              if (defined $cds_start_NF){
                  $csNF=$cds_start_NF->[0]->value;
              }
              else {
                  $csNF='';
              }
              if (defined $cds_end_NF){
                  $ceNF=$cds_end_NF->[0]->value;
              }
              else {
                  $ceNF='';
              }
              if (defined $transcript_name) {
                  $tn=$transcript_name->[0]->value;
              }
              push @$t_strand,$strand;
              push @$t_biotype,$biotype;
              push @$t_status,$status;
              push @$t_exon_count,$exon_count;
              push @$t_desc,$description;
              push @$t_name,$tn;
              push @$t_att_count,$attrib_count;
              push @$t_msnf,$msNF;
              push @$t_menf,$meNF;
              push @$t_csnf,$csNF;
              push @$t_cenf,$ceNF;
              push @$t_evi_count,$evidence_count;
              push @$t_evidence,$evistring;
              push @$t_remarks,$remstring;
              push @$t_hidden_remarks,$hremstring;
              push @$s_s_v_ref,$trans_sv_string;


          }
          else {
              push @$t_s_v_ref ,"-";
              push @$s_s_v_ref,"-";
              push @$t_start_ref,"-";
              push @$t_slice_name,"-";
              push @$t_end,"";
              push @$t_strand,"-";
              push @$t_biotype,"-";
              push @$t_status,"-";
              push @$t_exon_count,"-";
              push @$t_desc,"-";
              push @$t_name,"-";
              push @$t_att_count,"-";
              push @$t_msnf,"-";
              push @$t_menf,"-";
              push @$t_csnf,"-";
              push @$t_cenf,"-";
              push @$t_evi_count,"-";
              push @$t_evidence,"-";
              push @$t_hidden_remarks,"-";

          }
      }
      if (exists $allexons->{$tsv}){
          my $thisexons=$allexons->{$tsv};
          while (my ($ekey, $exarray) = each %{$thisexons}) {
              my $trial; push @$trial,"exon-stable-version";
              my $exon_slice_name; push @$exon_slice_name,"exon-slice-name";
              my $exon_start; push @$exon_start,"exon-start";
              my $exon_end; push @$exon_end,"exon-end";
              my $exon_strand; push @$exon_strand,"exon-strand";
              my $exon_phase; push @$exon_phase,"exon-phase";
              my $exon_end_phase; push @$exon_end_phase,"exon-end-phase";
              for (my $k=0;$k<$gene_count;$k++){
                  if ($exarray->[$k]){
                      my $trye=$exarray->[$k];
                      push @$trial,$trye->stable_id.".".$trye->version;
                      push @$exon_slice_name,$trye->slice->name;
                      push @$exon_start,$trye->start;
                      push @$exon_end,$trye->end;
                      push @$exon_strand,$trye->strand;
                      push @$exon_phase,$trye->phase;
                      push @$exon_end_phase,$trye->end_phase;

                  }
                  else {
                      push @$trial,"-";
                      push @$exon_slice_name,"-";
                      push @$exon_start,"-";
                      push @$exon_end,"-";
                      push @$exon_strand,"-";
                      push @$exon_phase,"-";
                      push @$exon_end_phase,"-";
                  }
              }
              push @$printarray,$trial;
              push @$printarray,$exon_slice_name;
              push @$printarray,$exon_start;
              push @$printarray,$exon_end;
              push @$printarray,$exon_strand;
              push @$printarray,$exon_phase;
              push @$printarray,$exon_end_phase;
#              undef $trial;
          }
      }
      push @$printarray,$t_s_v_ref;
      push @$printarray,$s_s_v_ref;
      push @$printarray,$t_slice_name;
      push @$printarray,$t_start_ref;
      push @$printarray,$t_end;
      push @$printarray,$t_strand;
      push @$printarray,$t_biotype;
      push @$printarray,$t_status;
      push @$printarray,$t_exon_count;
      push @$printarray,$t_desc;
      push @$printarray,$t_name;
      push @$printarray,$t_att_count;
      push @$printarray,$t_msnf;
      push @$printarray,$t_menf;
      push @$printarray,$t_csnf;
      push @$printarray,$t_cenf;
      push @$printarray,$t_evi_count;
      unless ($short){
          push @$printarray,$t_evidence;
          push @$printarray,$t_remarks;
          push @$printarray,$t_hidden_remarks;
      }
  }


  my %hash;
  foreach my $a (@$printarray){
      my $sc=0;
      foreach my $x (@$a){
          if (!exists $hash{$sc}){
              $hash{$sc}=length($x) if defined $x;
              $hash{$sc}=0 unless($x);
          }
          else {
              my $l;
              $l=0 unless ($x);
              if (defined $x){
                  $l=length($x);
                  if ($l>$hash{$sc}){
                      $hash{$sc}=$l;
                  }
              }
          }
          $sc++;
      }
  }

  foreach my $a (@$printarray){
      my $sc=0;
      my $len;
      foreach my $x(@$a){
          if ($x){
              $len=length($x);
          }
          else {
              $len=0;
          }
          my $spacelen=$hash{$sc};
          my $space=$spacelen-$len;
          if ($x){
              if ($short){
                  print STDOUT $x.(' ' x $space)."|";
              }
              else {
                  print STDOUT $x.(' ' x $space)."\t";
              }
          }
          else {
              if ($short){
                  print STDOUT (' ' x $space)."|";
              }
              else {
                  print STDOUT (' ' x $space)."\t";
              }

          }
          $sc++;
      }
      print STDOUT "\n";
  }

  return;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

