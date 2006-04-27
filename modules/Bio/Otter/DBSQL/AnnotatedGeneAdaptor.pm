package Bio::Otter::DBSQL::AnnotatedGeneAdaptor;

use strict;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;

use Bio::Otter::AnnotatedGene;
use Bio::Otter::AnnotatedTranscript;

use Bio::EnsEMBL::DBSQL::GeneAdaptor;

use vars qw(@ISA);

@ISA = qw ( Bio::EnsEMBL::DBSQL::GeneAdaptor);


# This is assuming the otter info and the ensembl genes are in the same database 
# and so have the same adaptor

sub new {
    my ($class,$dbobj) = @_;

    my $self = {};
    bless $self,$class;

    if( !defined $dbobj || !ref $dbobj ) {
        $self->throw("Don't have a db [$dbobj] for new adaptor");
    }

    $self->db($dbobj);

    return $self;
}

=head2 fetch_by_stable_id

 Title   : fetch_by_stable_id
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_stable_id{
   my ($self,$id) = @_;

   if (!defined($id)) {
       $self->throw("Must enter a gene id to fetch an AnnotatedGene");
   }

   # all this just to override this query
   my $sth = $self->prepare(q{
        SELECT gsi1.gene_id
        FROM gene_stable_id gsi1
        LEFT JOIN gene_stable_id gsi2
          ON gsi1.stable_id = gsi2.stable_id
          AND gsi1.version < gsi2.version
        WHERE gsi2.stable_id IS NULL
          AND gsi1.stable_id = ?
        });
   $sth->execute($id);

   my ($dbID) = $sth->fetchrow_array();

   if( !defined $dbID ) {
       $self->throw("No gene with stable id '$id'; cannot fetch");
   }

   my $gene = $self->fetch_by_dbID($dbID);

   return $gene;
    
}

sub fetch_by_stable_id_version {
    my ($self, $stable_id, $version) = @_;

    if (!defined($stable_id)) {
        $self->throw("Must enter a gene id to fetch an AnnotatedGene");
    }

    # all this just to override this query
    my $sth = $self->prepare(
        q{
        SELECT gene_id
        FROM gene_stable_id
        WHERE stable_id = ?
          AND version = ?
        }
    );
    $sth->execute($stable_id, $version);

    my ($dbID) = $sth->fetchrow;

    unless ($dbID) {
        $self->throw("No gene with stable ID '$stable_id' and version '$version'; cannot fetch");
    }

    my $gene = $self->fetch_by_dbID($dbID);

    return $gene;
}

=head2 fetch_by_dbID

 Title   : fetch_by_dbID
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_dbID {
   my ($self,$id) = @_;

   if (!defined($id)) {
       $self->throw("Must enter a gene dbID to fetch an AnnotatedGene");
   }

   my  $gene = $self->SUPER::fetch_by_dbID($id);

   $self->annotate_gene($gene);

   return $gene;
   
}

=head2 annotate_gene

 Title   : annotate_gene
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub annotate_gene {
    my ($self, $gene) = @_;

    # Will this work - let's hope so
    bless $gene, "Bio::Otter::AnnotatedGene";

    my $gene_info_adaptor         = $self->db->get_GeneInfoAdaptor();
    my $current_gene_info_adaptor = $self->db->get_CurrentGeneInfoAdaptor();

    my $infoid = $current_gene_info_adaptor->fetch_by_gene($gene);
    my $info   = $gene_info_adaptor->fetch_by_dbID($infoid);

    $gene->gene_info($info);

    my $ata      = $self->db->get_TranscriptAdaptor();
    #my $gene_time = $info->timestamp
    #  or $self->throw("No timestamp on gene_info");
    #my $window_sec = 60;
    foreach my $tran (@{ $gene->get_all_Transcripts }) {
        $ata->annotate_transcript($tran);
    #    my $info_time = $tran->transcript_info->timestamp
    #      or $self->throw("No timestamp on transcript_info");
    #    if ($info_time < ($gene_time - $window_sec) or $info_time > ($gene_time + $window_sec)) {
    #        $self->throw(sprintf "Time '%s' on transcript_info(%d) of transcript(%d) '%s' version '%d' "
    #          . "does not correspond to gene modfied time '%s' of gene(%d) '%s' version '%d'",
    #          scalar(localtime $info_time), $info->dbID, $tran->dbID,
    #          $tran->stable_id, $tran->version,
    #          scalar(localtime $gene_time),
    #          $gene->dbID, $gene->stable_id, $gene->version,
    #          );
    #    }
    }
}

=head2 list_current_dbIDs_for_Slice_by_type

  my $id_list = $self->list_current_dbIDs_for_Slice($slice, $gene_type);

Given a slice and a gene type, lists the dbIDs of the genes with exons on the slice.

=cut

sub list_current_dbIDs_for_Slice_by_type {
    my( $self, $slice, $gene_type ) = @_;
    
    $self->throw('Missing gene_type argument') unless $gene_type;
    
    my $tiling_path = $slice->get_tiling_path;
    my $ctg_id_list = join(',', map($_->component_Seq->dbID, @$tiling_path));
    my $sth = $self->db->prepare(qq{
        SELECT gsid.stable_id
          , gsid.version
          , g.gene_id
          , g.type
        FROM gene_stable_id gsid
          , gene g
          , transcript t
          , exon_transcript et
          , exon e
          , assembly a
        WHERE gsid.gene_id = g.gene_id
          AND g.gene_id = t.gene_id
          AND t.transcript_id = et.transcript_id
          AND et.exon_id = e.exon_id
          AND e.contig_id = a.contig_id
          AND a.contig_id in ($ctg_id_list)
          AND a.type = ?
        GROUP BY gsid.stable_id
          , gsid.version
        ORDER BY gsid.version ASC
        });
    $sth->execute($slice->assembly_type);
    
    my $get_max = $self->_max_version_for_stable_sth;
    
    my( %sid_gid );
    while (my ($sid, $version, $gid, $type) = $sth->fetchrow) {
        $get_max->execute($sid);
        my ($max) = $get_max->fetchrow;
        next unless $max == $version;
        $sid_gid{$sid} = [$gid, $type];
    }
    my @gene_id = map $_->[0], grep $_->[1] eq $gene_type, values %sid_gid;
    return [sort {$a <=> $b} @gene_id];
}

=head2 list_current_dbIDs_for_Slice

  my $id_list = $self->list_current_dbIDs_for_Slice($slice);

Given a slice, lists the dbIDs of the genes with exons on the slice.

Note that this will not filter out a gene of the type "obsolete"

=cut

sub list_current_dbIDs_for_Slice {
    my( $self, $slice ) = @_;
    
    my $tiling_path = $slice->get_tiling_path;
    my $ctg_id_list = join(',', map($_->component_Seq->dbID, @$tiling_path));
    
    $self->throw("No contig IDs in slice") unless $ctg_id_list;

    my $sth = $self->db->prepare(qq{
        SELECT gsid.stable_id
          , gsid.version
          , g.gene_id
        FROM gene_stable_id gsid
          , gene g
          , transcript t
          , exon_transcript et
          , exon e
          , assembly a
        WHERE gsid.gene_id = g.gene_id
          AND g.gene_id = t.gene_id
          AND t.transcript_id = et.transcript_id
          AND et.exon_id = e.exon_id
          AND e.contig_id = a.contig_id
          AND a.contig_id in ($ctg_id_list)
          AND a.type = ?
        GROUP BY gsid.stable_id
          , gsid.version
        ORDER BY gsid.version ASC
        });
    $sth->execute($slice->assembly_type);
    
    my $get_max = $self->_max_version_for_stable_sth;

    my( %sid_gid );
    while (my ($sid, $version, $gid) = $sth->fetchrow) {
        $get_max->execute($sid);
        my ($max) = $get_max->fetchrow;
        next unless $max == $version;
        $sid_gid{$sid} = $gid;
    }
    return [sort {$a <=> $b} values %sid_gid];
}


sub list_current_dbIDs_linked_by_accession_for_Slice {
    my ($self, $slice) = @_;

    return $self->list_current_dbIDs_linked_by_accessions(
        $self->list_all_accessions_in_Slice($slice));
}

sub list_all_accessions_in_Slice {
    my ($self, $slice) = @_;
    
    my $tiling_path = $slice->get_tiling_path;
    return [ map $_->component_Seq->clone->embl_id, @$tiling_path ];
}

sub list_current_dbIDs_linked_by_accessions {
    my ($self, $acc_list) = @_;

    my $clone_acc_list = join(',', map "'$_'", @$acc_list);

    my $list_contigs = $self->db->prepare(
        qq{
        SELECT g.contig_id
        FROM clone c
          , contig g
        WHERE c.clone_id = g.clone_id
          AND c.embl_acc IN ($clone_acc_list)
        }
    );
    $list_contigs->execute;
    my $ctg_list = [];
    while (my ($ctg_id) = $list_contigs->fetchrow) {
        push(@$ctg_list, $ctg_id);
    }
    my $ctg_id_list = join(',', @$ctg_list);

    my $sth = $self->db->prepare(
        qq{
        SELECT gsid.stable_id
          , gsid.version
          , g.gene_id
        FROM gene_stable_id gsid
          , gene g
          , transcript t
          , exon_transcript et
          , exon e
        WHERE gsid.gene_id = g.gene_id
          AND g.gene_id = t.gene_id
          AND t.transcript_id = et.transcript_id
          AND et.exon_id = e.exon_id
          AND e.contig_id IN ($ctg_id_list)
        GROUP BY gsid.stable_id
          , gsid.version
        ORDER BY gsid.version ASC
        }
    );
    $sth->execute;

    my $get_max = $self->_max_version_for_stable_sth;

    my (%sid_gid);
    while (my ($sid, $version, $gid) = $sth->fetchrow) {
        $get_max->execute($sid);
        my ($max) = $get_max->fetchrow;
        next unless $max == $version;
        $sid_gid{$sid} = $gid;
    }
    return [ sort { $a <=> $b } values %sid_gid ];
}

=head2 list_current_dbIDs_for_Contig

  my $id_list = $self->list_current_dbIDs_for_Contig($contig);

=cut

sub list_current_dbIDs_for_Contig {
    my( $self, $contig ) = @_;
    
    my $ctg_id = $contig->dbID;
    my $sth = $self->db->prepare(qq{
        SELECT gsid.stable_id
          , gsid.version
          , g.gene_id
        FROM gene_stable_id gsid
          , gene g
          , transcript t
          , exon_transcript et
          , exon e
        WHERE gsid.gene_id = g.gene_id
          AND g.gene_id = t.gene_id
          AND t.transcript_id = et.transcript_id
          AND et.exon_id = e.exon_id
          AND e.contig_id = ?
        GROUP BY gsid.stable_id
          , gsid.version
        ORDER BY gsid.version ASC
        });
    $sth->execute($ctg_id);
        
    my $get_max = $self->_max_version_for_stable_sth;

    my( %sid_gid );
    while (my ($sid, $version, $gid) = $sth->fetchrow) {
        $get_max->execute($sid);
        my ($max) = $get_max->fetchrow;
        next unless $max == $version;
        $sid_gid{$sid} = $gid;
    }
    return [sort {$a <=> $b} values %sid_gid];
}

=head2 list_current_dbIDs

    my $id_list = $self->list_current_dbIDs;

Returns a ref to a list of all the current non-obsolete gene dbIDs.

=cut

sub list_current_dbIDs {
    my( $self ) = @_;
    
    # This is much faster using both stable_id and version
    # in the sort, even though we don't need it, because
    # mysql can use the index instead of a filesort.
    my $sth = $self->db->prepare(q{
        SELECT s.stable_id
          , g.gene_id
          , g.type
        FROM gene g
          , gene_stable_id s
        WHERE g.gene_id = s.gene_id
        ORDER BY s.stable_id ASC
          , s.version ASC
        });
    $sth->execute;

    my( %stable_gid_type );
    while (my ($stable, $gid, $type) = $sth->fetchrow) {
        $stable_gid_type{$stable} = [$gid, $type];
    }

    my $current_gene_id = [];
    foreach my $gid_type (values %stable_gid_type) {
        my ($gid, $type) = @$gid_type;
        next if $type eq 'obsolete';
        push(@$current_gene_id, $gid);
    }
    return $current_gene_id;
}

=head2 Gene_is_current_version

    if ($self->Gene_is_current_version($gene)) {
        ...
    }

Returns TRUE if the gene given is the current
version of that gene, ie: it has the maximum
version in the database of its stable_id.

=cut

sub Gene_is_current_version {
    my( $self, $gene ) = @_;
    
    my $stable  = $gene->stable_id;
    my $version = $gene->version;
    my $sth = $self->_max_version_for_stable_sth;
    $sth->execute($stable);
    my ($max_version) = $sth->fetchrow;
    
    return $version == $max_version;
}

sub _max_version_for_stable_sth {
    my( $self ) = @_;
    
    return $self->db->prepare(q{
        SELECT MAX(version)
        FROM gene_stable_id
        WHERE stable_id = ?
        });
}

### fetch_by_Slice should have been called fetch_all_by_Slice
### to override fetch_all_by_Slice in GeneAdaptor

sub fetch_all_by_Slice {
    my $self = shift;
    
    return $self->fetch_by_Slice(@_);
}


=head2 fetch_by_Slice

  Arg [1]    : Bio::EnsEMBL::Slice $slice
               the slice to fetch genes from
  Example    : $genes = $gene_adaptor->fetch_by_slice($slice);
  Description: Retrieves all genes which are present on a slice
  Returntype : list of Bio::EnsEMBL::Genes in slice coordinates
  Exceptions : nonetail -
  Caller     : Bio::EnsEMBL::Slice

=cut

sub fetch_by_Slice {
    my ($self, $slice) = @_;
    
    my $latest_gene_id = $self->list_current_dbIDs_for_Slice($slice);
    warn "Found ", scalar(@$latest_gene_id), " current gene IDs\n";
    my $latest_genes = [];
    foreach my $id (@$latest_gene_id) {
        my $gene = $self->fetch_by_dbID($id)->transform($slice);
        
        # Skip any genes that aren't the latest version of that gene
        next unless $self->Gene_is_current_version($gene);
        
        # Skip any genes that are off slice
        next unless $gene->start <= $slice->length and $gene->end >= 1;
        
        push(@$latest_genes, $gene);
    }

    # Truncate gene components to Slice
    for (my $j = 0; $j < @$latest_genes;) {
        my $g = $latest_genes->[$j];
        my $g_info = $g->gene_info;
        my $tsct_list = $g->get_all_Transcripts;
        
        for (my $i = 0; $i < @$tsct_list;) {
            my $transcript = $tsct_list->[$i];
            my( $t_name );
            eval{
                $t_name = $transcript->transcript_info->name;
            };
            if ($@) {
                die sprintf("Error getting name of %s %s (%d):\n$@", 
                    ref($transcript), $transcript->stable_id, $transcript->dbID);
            }
            my $exons_truncated = $transcript->truncate_to_Slice($slice);
            my $ex_list = $transcript->get_all_Exons;
            if (@$ex_list) {
                $i++;
                if ($exons_truncated) {
                    my $remark = Bio::Otter::GeneRemark->new;
                    my $message = "Transcript '$t_name' has $exons_truncated exon";
                    if ($exons_truncated > 1) {
                        $message .= 's that are not in this slice';
                    } else {
                        $message .= ' that is not in this slice';
                    }
                    $remark->remark($message);
                    $g_info->remark($remark);
                    $g_info->truncated_flag(1);
                }
            } else {
                # This will fail if get_all_Transcripts() ceases to return a ref
                # to the actual list of Transcripts inside the Gene object
                splice(@$tsct_list, $i, 1);
                my $remark = Bio::Otter::GeneRemark->new;
                $remark->remark("Transcript '$t_name' has no exons within the slice");
                $g_info->remark($remark);
                $g_info->truncated_flag(1);
            }
        }
        
        # Remove any genes that don't have transcripts left.
        if (@$tsct_list) {
            $j++;
        } else {
            splice(@$latest_genes, $j, 1);
        }
    }

    warn "Returning ", scalar(@$latest_genes), " genes\n";

    return $latest_genes;
}


=head2 store

 Title   : store
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub store{
   my ($self,$obj) = @_;

   if (!defined($obj)) {
       $self->throw("Must enter an AnnotatedGene object to the store method");
   }
   if (!$obj->isa("Bio::Otter::AnnotatedGene")) {
       $self->throw("Object must be an AnnotatedGene object. Currently [$obj]");
   }

   if (!defined($obj->gene_info)) {
      $self->throw("Annotated Gene must have a gene info object");
   }

   my $gene_info_adaptor = $self->db->get_GeneInfoAdaptor();
   my $current_g_info_ad = $self->db->get_CurrentGeneInfoAdaptor;

   $self->SUPER::store($obj);

   $self->db->get_StableIdAdaptor->store_by_type($obj->stable_id,'gene');
   $gene_info_adaptor->store($obj->gene_info);
   $current_g_info_ad->store($obj);

   foreach my $exon (@{$obj->get_all_Exons}) {
       $self->db->get_StableIdAdaptor->store_by_type($exon->stable_id,'exon');
   }
   # Now let's store all the transcript info

   my $transcript_info_adaptor = $self->db->get_TranscriptInfoAdaptor();
   my $current_tran_info_adapt  =$self->db->get_CurrentTranscriptInfoAdaptor();

   foreach my $tran (@{$obj->get_all_Transcripts}) {
       $self->db->get_StableIdAdaptor->store_by_type($tran->stable_id,'transcript');
       if (defined($tran->translation)) {
         $self->db->get_StableIdAdaptor->store_by_type($tran->translation->stable_id,'translation');
       }
       $transcript_info_adaptor->store($tran->transcript_info);
       $current_tran_info_adapt->store($tran);
   }
 
   #transcripts now need annotated transcript adaptors as well
    
   my $trans_adaptor = $self->db->get_TranscriptAdaptor();
    
   foreach my $trans (@{$obj->get_all_Transcripts}) {
     $trans->adaptor($trans_adaptor);
   }
 
   $obj->adaptor($self);
}

sub attach_to_Slice {
    my ($self,$gene,$slice) = @_;


    #my $anal = $self->db->get_AnalysisAdaptor()->fetch_by_logic_name('otter');

    my $aga  = $self;
    my $ea   = $self->db->get_ExonAdaptor;
    my $ta   = $self->db->get_TranscriptAdaptor;
    
    my $time = time;
    
    $gene->adaptor($aga);

    if (!defined($gene->created)) {
	$gene->created($time);
    }

    if (!defined($gene->version)) {
	$gene->version(1);
    }

    $gene->modified($time);
    
    foreach my $tran (@{$gene->get_all_Transcripts}) {
	$tran->adaptor($ta);
	
	if (!defined($tran->created)) {
	    $tran->created($time);
	}
	if (!defined($tran->version)) {
	    $tran->version(1);
	}

	$tran->modified($time);
    }

    my $count = 1;
    
    my %transformed_exons;
    
    foreach my $exon (@{$gene->get_all_Exons}) {
	$exon->contig($slice);
	$exon->adaptor($ea);
	$exon->dbID(undef);

        # print "exon coords = " . $exon->start . " " . $exon->end ."\n";
	
	if (!defined($exon->created)) {
	    $exon->created($time);
	}
	if (!defined($exon->version)) {
	    $exon->version(1);
	}
	$exon->modified($time);
	
	$transformed_exons{$exon} = $exon->transform;
	
	$count++;
    }

    foreach my $trans (@{$gene->get_all_Transcripts}) {
       my @new_transcript_exons;
       foreach my $exon (@{$trans->get_all_Exons}) {
           push @new_transcript_exons,$transformed_exons{$exon};
       }

       $trans->flush_Exons;

       foreach my $exon (@new_transcript_exons) {
          $trans->add_Exon($exon);
       }

       if (defined($trans->translation)) {
         $trans->translation->adaptor($self->db->get_TranslationAdaptor);
         $trans->translation->start_Exon($transformed_exons{$trans->translation->start_Exon});
         $trans->translation->end_Exon  ($transformed_exons{$trans->translation->end_Exon});
       }
    }
}

sub fetch_all_by_DBEntry {
  my $self = shift;
  my $external_id = shift;
  my @genes = ();
  my @ids = ();

  my $sth = $self->prepare("SELECT DISTINCT( oxr.ensembl_id )
                   FROM xref x, object_xref oxr
                  WHERE oxr.xref_id = x.xref_id
                    AND x.display_label = '$external_id'
                    AND oxr.ensembl_object_type='Gene'");

  $sth->execute();

   while( ($a) = $sth->fetchrow_array ) {
       push(@ids,$a);
   }

  foreach my $gene_id ( @ids ) {
    my $gene = $self->fetch_by_dbID( $gene_id );
    if( $gene ) {
      push( @genes, $gene );
    }
  }
  return \@genes;
}

1;
