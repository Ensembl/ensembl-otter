=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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


package GeneHist::WidgetUtils;

# Author: ck1@sanger.ac.uk

use vars qw{ @ISA @EXPORT_OK };

@ISA = ('Exporter');
@EXPORT_OK = qw(
                show_err_msg
                refresh_gui
                adjust_scrollbar_width
                add_GH_qry_frm
                add_GH_btn_frm
                add_GH_data_frm
                add_DG_MListbox
                );

use strict;
use warnings;

use Hum::Sort ('ace_sort');

sub adjust_scrollbar_width {
  my ($widget, $size) = @_;
  $widget->Subwidget('xscrollbar')->configure(-width=>$size);
  $widget->Subwidget('yscrollbar')->configure(-width=>$size);
}

sub show_err_msg {
  my ($mw, $font) = @_;
  $mw->messageBox(-title => 'Unsupported tree nodes chosen!',
                  -font  => $font,
                  -message=>'Can only compare 2 versions of V* nodes.',
                  -default_button => 'OK');
}

sub add_GH_qry_frm {

  my ($parent, $font, $get_gene_history) = @_;

  my $query_f = $parent->Frame(-relief => 'groove', -borderwidth => 1)
    -> pack(-side=>'top', -fill=>'x');

  $query_f->Label(-text=>'Search (gene / transcript stable id or gene name / transcript name) ',)
    -> pack(-side=>'left');
  my $query;
  my $entry1 = $query_f->Entry(-textvariable=>\$query, -width=>25, -bg=>'white')->pack(-side=>'left');
  # reset
  $query_f->Button(-text=>'Clear', -font=>$font, -command=>sub {$entry1->delete('0.0', 'end')})->pack(-side=>'left');

  $query_f->Label(-text=>'Dataset (eg, human)')->pack(-side=>'left');

  my $dataset = 'human'; # default
  my $entry2 = $query_f->Entry(-textvariable=>\$dataset, -width => 18, -bg=>'white')->pack(-side=>'left');

  # reset
  $query_f->Button(-text=>'Clear', -font=>$font, -command=>sub {$entry2->delete('0.0', 'end')})->pack(-side=>'left');

  $query_f->Button(-text=>'Submit', -command=>$get_gene_history)->pack(-side=>'left');
  $query_f->Button(-text=>'Quit', -command=>sub{exit}, -foreground=>'#8B2323')->pack(-side=>'right' );

  return ($query_f, $query, $entry1, $entry2);
}

sub add_GH_btn_frm {

  my ($font, $parent, $compare_gene_versions,
      $open_or_close_all_nodes, $open_close_V_nodes,
      $open_close_geneTrans_info_nodes,
      $search_xml) = @_;

  my $btn_f = $parent->Frame(-relief => 'groove', -borderwidth => 1)
    -> pack( -side => 'top', -anchor => 'n', -fill => 'x');

  my $btn_cmp = $btn_f->Button(-text=>'Compare 2 Selected Gene Versions',
                               -font=>$font,
                               -command=>$compare_gene_versions)->pack(-side=>'left');

  my $btn_all_nodes = $btn_f->Button(-text=>'Collapse All Nodes',
                                     -font=>$font,
                                     -command=>$open_or_close_all_nodes)->pack(-side=>'left');

  my $btn_V_nodes   = $btn_f->Button(-text=>'Collapse V Nodes',
                                     -font=>$font,
                                     -command=>$open_close_V_nodes)->pack(-side=>'left');

  my $btn_GT_nodes  = $btn_f->Button(-text=>'Collapse Gene/TransInfo Nodes',
                                     -font=>$font,
                                     -command=>$open_close_geneTrans_info_nodes)->pack(-side=>'left');
  my $srchtxt;
  $btn_f->Label(-text=>'Search in XML: ')-> pack(-side=>'left');
  my $srch_entry    = $btn_f->Entry(-textvariable=>\$srchtxt, -width => 20, -bg=>'white')->pack(-side=>'left');
  $btn_f->Button(-text=>'Clear Search', -command=>sub{$srch_entry->delete('0.0', 'end')}, -font=>$font)->pack(-side=>'left' );

  my $src_btn     = $btn_f->Button(-text=>'Search', -command=>$search_xml, -font=>$font)->pack(-side=>'left' );
  #my $adv_src_btn = $btn_f->Button(-text=>'Refined Search', -command=>\&adv_search_xml, -font=>$font)->pack(-side=>'left' );

  return ($btn_f, $btn_cmp, $btn_all_nodes, $btn_V_nodes, $btn_GT_nodes, $srchtxt, $srch_entry, $src_btn);
}

sub add_GH_data_frm {

  my ($parent, $font) = @_;
  my $data_f = $parent->Frame()->pack();

  #----------------
  #  tree widget
  #----------------

  #my $tree = $tree_f->ScrlTree(-font=>['helvetica','10'])
  my $tree = $data_f->Scrolled('Tree',
                               -font=>$font,
                               -height=>600,
                               -width=>46,
                               -exportselection=>1,
                               -bg=>'#F2F2F2',
                               -selectforeground=>'black',
                               -selectbackground=>'#D6D6D6',
                               # -selectmode=>'multiple', # contiguous selection only
                               -selectmode=>'extended',
                               -wideselection=>1,
                              )->pack(-side=>'left', -fill=>'both', -expand=>1);

  $tree->packAdjust(-side=>'left');

  adjust_scrollbar_width($tree, 10);

  #------------------------------------
  #  frame in frame to hold notebook
  #------------------------------------
  my $xml_f   = $data_f->Frame(-width=>2000, -bg=>'#BFBFBF', -border=>0)->pack(-side=>'left', -fill=>'both', -expand=>1);

  return ($data_f, $tree, $xml_f);
}

sub refresh_gui {
  my ($parent) = @_;
  my $mw = $parent->parent;
  $parent->destroy;
  $parent = undef;
  $parent = $mw->Frame(-relief => 'groove', -borderwidth => 1)
    -> pack(-side=>'top', -fill=>'both', -expand=>1);

  return $parent;
}

sub add_DG_MListbox {

  my ($parent, $font) = @_;

  my $mlist = $parent->Scrolled("MListbox",
                                -borderwidth=>1,
                                -scrollbars => "osoe",
                                -sortable=>1,
                                -resizeable=>1,
                                -selectmode=>"browse",
                                -font=>$font,
                                -height=> 0,
                                -textwidth => 20,
                                -width => 0,
                                -separatorcolor=>'gray',
                               );

  adjust_scrollbar_width($mlist, 10);

  return $mlist;
}

1;
