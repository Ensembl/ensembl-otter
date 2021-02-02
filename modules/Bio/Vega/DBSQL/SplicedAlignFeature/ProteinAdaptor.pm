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


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=head1 NAME

Bio::Vega::DBSQL::SplicedAlignFeature::ProteinAdaptor - Adaptor for Bio::Vega::SplicedAlignFeature::Protein features

=head1 SYNOPSIS

  $pafa = $vega_dba->get_ProteinSplicedAlignFeatureAdaptor;

  my @features = @{ $pafa->fetch_all_by_Slice($slice) };

  $pafa->store(@features);

=head1 DESCRIPTION

This is an adaptor responsible for the retrieval and storage of
SplicedAlignFeature::Proteins from the database. This adaptor inherits most of its
functionality from the BaseAlignFeatureAdaptor superclass.

=head1 METHODS

=cut


package Bio::Vega::DBSQL::SplicedAlignFeature::ProteinAdaptor;

use strict;
use warnings;

use DBI qw(:sql_types);

use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Vega::SplicedAlignFeature::Protein;

use parent qw(Bio::EnsEMBL::DBSQL::BaseAlignFeatureAdaptor);


=head2 _tables

  Args       : none
  Example    : @tabs = $self->_tables
  Description: PROTECTED implementation of the abstract method inherited from
               BaseFeatureAdaptor.  Returns list of [tablename, alias] pairs
  Returntype : list of listrefs of strings
  Exceptions : none
  Caller     : Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor::generic_fetch
  Status     : Stable

=cut

sub _tables {
  my $self = shift;

  return (['protein_spliced_align_feature', 'psaf'], ['external_db','exdb']);
}


sub _left_join { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines) called from superclass
    return (['external_db',"exdb.external_db_id = psaf.external_db_id"]);
}

=head2 _columns

  Args       : none
  Example    : @columns = $self->_columns
  Description: PROTECTED implementation of abstract superclass method.
               Returns a list of columns that are needed for object creation.
  Returntype : list of strings
  Exceptions : none
  Caller     : Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor::generic_fetch
  Status     : Stable

=cut

sub _columns { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines) called from superclass
  my $self = shift;

  #warning _objs_from_hashref method depends on ordering of this list
  return qw( psaf.protein_spliced_align_feature_id
             psaf.seq_region_id
             psaf.seq_region_start
             psaf.seq_region_end
             psaf.analysis_id
             psaf.seq_region_strand
             psaf.hit_start
             psaf.hit_end
             psaf.hit_name
             psaf.alignment_type
             psaf.alignment_string
             psaf.evalue
             psaf.perc_ident
             psaf.score
             psaf.external_db_id
             psaf.hcoverage
             exdb.db_name
             exdb.db_display_name);
}

=head2 store

  Arg [1]    : list of Bio::Vega::SplicedAlignFeature::Protein @feats
  Example    : $protein_spliced_align_feature_adaptor->store(@feats);
  Description: stores a list of ProteinAlignFeatures in the database
  Returntype : none
  Exceptions : throw if any of the provided features cannot be stored
               which may occur if:
                 * The feature does not have an associated Slice
                 * The feature does not have an associated analysis
                 * The Slice the feature is associated with is on a seq_region
                   unknown to this database
              A warning is given if:
                 * The feature has already been stored in this db
  Caller     : Pipeline
  Status     : Stable

=cut


sub store{
  my ($self, @feats) = @_;

  throw("Must call store with features") if( scalar(@feats) == 0 );

  my @tabs = $self->_tables;
  my ($tablename) = @{$tabs[0]};

  my $db = $self->db();
  my $slice_adaptor = $db->get_SliceAdaptor();
  my $analysis_adaptor = $db->get_AnalysisAdaptor();

  my $sth = $self->prepare( qq{
      INSERT INTO $tablename (seq_region_id,
                              seq_region_start,
                              seq_region_end,
                              seq_region_strand,
                              hit_start,
                              hit_end,
                              hit_name,
                              alignment_type,
                              alignment_string,
                              analysis_id,
                              score,
                              evalue,
                              perc_ident,
                              external_db_id,
                              hcoverage)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    }         # 15 arguments
  );

FEATURE:
  foreach my $feat ( @feats ) {
    if( !ref $feat || !$feat->isa("Bio::Vega::SplicedAlignFeature::Protein") ) {
      throw("feature must be a Bio::Vega::SplicedAlignFeature::Protein,"
            . " not a [".ref($feat)."].");
    }

    if($feat->is_stored($db)) {
      warning("SplicedAlignFeature::Protein [".$feat->dbID."] is already stored" .
              " in this database.");
      next FEATURE;
    }

    #sanity check the hstart and hend
    my $hstart  = $feat->hstart();
    my $hend    = $feat->hend();
    $self->_check_start_end_strand($hstart,$hend,1);

    my ($alignment_type, $alignment_string) = $feat->check_fetch_alignment();

    my $hseqname = $feat->hseqname();
    if(!$hseqname) {
      throw("SplicedAlignFeature::Protein must define an hseqname.");
    }

    if(!defined($feat->analysis)) {
      throw("An analysis must be attached to the features to be stored.");
    }

    #store the analysis if it has not been stored yet
    if(!$feat->analysis->is_stored($db)) {
      $analysis_adaptor->store($feat->analysis());
    }

    my $slice = $feat->slice();
    if(!defined($slice) || !($slice->isa("Bio::EnsEMBL::Slice") or $slice->isa('Bio::EnsEMBL::LRGSlice')) ) {
      throw("A slice must be attached to the features to be stored.");
    }

    my $original = $feat;
    my $seq_region_id;
    ($feat, $seq_region_id) = $self->_pre_store($feat);

    $sth->bind_param(  1, $seq_region_id,        SQL_INTEGER);
    $sth->bind_param(  2, $feat->start,          SQL_INTEGER);
    $sth->bind_param(  3, $feat->end,            SQL_INTEGER);
    $sth->bind_param(  4, $feat->strand,         SQL_TINYINT);
    $sth->bind_param(  5, $hstart,               SQL_INTEGER);
    $sth->bind_param(  6, $hend,                 SQL_INTEGER);
    $sth->bind_param(  7, $hseqname,             SQL_VARCHAR);
    $sth->bind_param(  8, $alignment_type,       SQL_LONGVARCHAR );
    $sth->bind_param(  9, $alignment_string,     SQL_LONGVARCHAR );
    $sth->bind_param( 10, $feat->analysis->dbID, SQL_INTEGER);
    $sth->bind_param( 11, $feat->score,          SQL_DOUBLE);
    $sth->bind_param( 12, $feat->p_value,        SQL_DOUBLE);
    $sth->bind_param( 13, $feat->percent_id,     SQL_REAL);
    $sth->bind_param( 14, $feat->external_db_id, SQL_INTEGER);
    $sth->bind_param( 15, $feat->hcoverage,      SQL_DOUBLE);

    $sth->execute();
    my $dbId = $self->last_insert_id("${tablename}_id", undef, $tablename);
    $original->dbID($dbId);
    $original->adaptor($self);
  }

  $sth->finish();
  return;
}


=head2 _objs_from_sth

  Arg [1]    : DBI statement handle $sth
               an exectuted DBI statement handle generated by selecting
               the columns specified by _columns() from the table specified
               by _table()
  Example    : @dna_dna_align_feats = $self->_obj_from_hashref
  Description: PROTECTED implementation of superclass abstract method.
               Creates DnaDnaAlignFeature objects from a DBI hashref
  Returntype : listref of Bio::EnsEMBL::ProteinAlignFeatures
  Exceptions : none
  Caller     : Bio::EnsEMBL::BaseFeatureAdaptor::generic_fetch
  Status     : Stable

=cut

sub _objs_from_sth { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines) called from superclass
  my ($self, $sth, $mapper, $dest_slice) = @_;

  #
  # This code is ugly because an attempt has been made to remove as many
  # function calls as possible for speed purposes.  Thus many caches and
  # a fair bit of gymnastics is used.
  #

  my $sa = $self->db()->get_SliceAdaptor();
  my $aa = $self->db->get_AnalysisAdaptor();

  my @features;
  my %analysis_hash;
  my %slice_hash;
  my %sr_name_hash;
  my %sr_cs_hash;

  my ($protein_spliced_align_feature_id,
      $seq_region_id,
      $seq_region_start,
      $seq_region_end,
      $analysis_id,
      $seq_region_strand,
      $hit_start,
      $hit_end,
      $hit_name,
      $alignment_type,
      $alignment_string,
      $evalue,
      $perc_ident,
      $score,
      $external_db_id,
      $hcoverage,
      $external_db_name,
      $external_display_db_name );

  $sth->bind_columns(\$protein_spliced_align_feature_id,
                     \$seq_region_id,
                     \$seq_region_start,
                     \$seq_region_end,
                     \$analysis_id,
                     \$seq_region_strand,
                     \$hit_start,
                     \$hit_end,
                     \$hit_name,
                     \$alignment_type,
                     \$alignment_string,
                     \$evalue,
                     \$perc_ident,
                     \$score,
                     \$external_db_id,
                     \$hcoverage,
                     \$external_db_name,
                     \$external_display_db_name );

  my $asm_cs;
  my $cmp_cs;
  my $asm_cs_vers;
  my $asm_cs_name;
  my $cmp_cs_vers;
  my $cmp_cs_name;
  if($mapper) {
    $asm_cs = $mapper->assembled_CoordSystem();
    $cmp_cs = $mapper->component_CoordSystem();
    $asm_cs_name = $asm_cs->name();
    $asm_cs_vers = $asm_cs->version();
    $cmp_cs_name = $cmp_cs->name();
    $cmp_cs_vers = $cmp_cs->version();
  }

  my $dest_slice_start;
  my $dest_slice_end;
  my $dest_slice_strand;
  my $dest_slice_length;
  my $dest_slice_sr_name;
  my $dest_slice_sr_id;
  if($dest_slice) {
    $dest_slice_start  = $dest_slice->start();
    $dest_slice_end    = $dest_slice->end();
    $dest_slice_strand = $dest_slice->strand();
    $dest_slice_length = $dest_slice->length();
    $dest_slice_sr_name = $dest_slice->seq_region_name();
    $dest_slice_sr_id  = $dest_slice->get_seq_region_id();
  }

  FEATURE: while($sth->fetch()) {
    #get the analysis object
    my $analysis = $analysis_hash{$analysis_id} ||=
      $aa->fetch_by_dbID($analysis_id);

    #get the slice object
    my $slice = $slice_hash{"ID:".$seq_region_id};

    if(!$slice) {
      $slice = $sa->fetch_by_seq_region_id($seq_region_id);
      $slice_hash{"ID:".$seq_region_id} = $slice;
      $sr_name_hash{$seq_region_id} = $slice->seq_region_name();
      $sr_cs_hash{$seq_region_id} = $slice->coord_system();
    }

    my $sr_name = $sr_name_hash{$seq_region_id};
    my $sr_cs   = $sr_cs_hash{$seq_region_id};
    #
    # remap the feature coordinates to another coord system
    # if a mapper was provided
    #
    if($mapper) {

        if (defined $dest_slice && $mapper->isa('Bio::EnsEMBL::ChainedAssemblyMapper')  ) {
            ( $seq_region_id,  $seq_region_start,
              $seq_region_end, $seq_region_strand )
                =
                $mapper->map( $sr_name, $seq_region_start, $seq_region_end,
                          $seq_region_strand, $sr_cs, 1, $dest_slice);

        } else {

            ( $seq_region_id,  $seq_region_start,
              $seq_region_end, $seq_region_strand )
                =
                $mapper->fastmap( $sr_name, $seq_region_start, $seq_region_end,
                          $seq_region_strand, $sr_cs );
        }

      #skip features that map to gaps or coord system boundaries
      next FEATURE if(!defined($seq_region_id));

 #     #get a slice in the coord system we just mapped to
 #     if($asm_cs == $sr_cs || ($cmp_cs != $sr_cs && $asm_cs->equals($sr_cs))) {
        $slice = $slice_hash{"ID:".$seq_region_id} ||=
          $sa->fetch_by_seq_region_id($seq_region_id);
#      } else {
#        $slice = $slice_hash{"ID:".$seq_region_id} ||=
#          $sa->fetch_by_seq_region_id($asm_cs_name, $sr_name, undef, undef, undef,
#                               $asm_cs_vers);
#      }
    }

    #
    # If a destination slice was provided convert the coords
    # If the dest_slice starts at 1 and is foward strand, nothing needs doing
    #
    if($dest_slice) {
      if($dest_slice_start != 1 || $dest_slice_strand != 1) {
        if($dest_slice_strand == 1) {
          $seq_region_start = $seq_region_start - $dest_slice_start + 1;
          $seq_region_end   = $seq_region_end   - $dest_slice_start + 1;
        } else {
          my $tmp_seq_region_start = $seq_region_start;
          $seq_region_start = $dest_slice_end - $seq_region_end + 1;
          $seq_region_end   = $dest_slice_end - $tmp_seq_region_start + 1;
          $seq_region_strand *= -1;
        }
      }

      #throw away features off the end of the requested slice
      if($seq_region_end < 1 || $seq_region_start > $dest_slice_length ||
        ( $dest_slice_sr_id ne $seq_region_id )) {
        next FEATURE;
      }
      $slice = $dest_slice;
    }

    # Finally, create the new ProteinAlignFeature.
    push(
      @features,
      $self->_create_feature_fast(
        'Bio::Vega::SplicedAlignFeature::Protein', {
          'slice'            => $slice,
          'start'            => $seq_region_start,
          'end'              => $seq_region_end,
          'strand'           => $seq_region_strand,
          'hseqname'         => $hit_name,
          'hstart'           => $hit_start,
          'hend'             => $hit_end,
          'hstrand'          => 1,                  # dna_pep_align features
                                                    # are always hstrand 1
          'score'            => $score,
          'p_value'          => $evalue,
          'percent_id'       => $perc_ident,
          'alignment_type'   => $alignment_type,
          'alignment_string' => $alignment_string,
          'analysis'         => $analysis,
          'adaptor'          => $self,
          'dbID'             => $protein_spliced_align_feature_id,
          'external_db_id'   => $external_db_id,
          'hcoverage'        => $hcoverage,
          'dbname'           => $external_db_name,
          'db_display_name'  => $external_display_db_name
        } ) );

  }

  return \@features;
}



=head2 list_dbIDs

  Arg [1]    : none
  Example    : @feature_ids = @{$protein_spliced_align_feature_adaptor->list_dbIDs()};
  Description: Gets an array of internal ids for all protein align
               features in the current db
  Arg[1]     : <optional> int. not 0 for the ids to be sorted by the seq_region.
  Returntype : listref of ints
  Exceptions : none
  Caller     : ?
  Status     : Stable

=cut

sub list_dbIDs {
   my ($self,$ordered) = @_;

   return $self->_list_dbIDs("protein_spliced_align_feature", undef, $ordered);
}

1;
