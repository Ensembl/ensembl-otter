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

   my  $gene = $self->SUPER::fetch_by_stable_id     ($id);

   $self->annotate_gene($gene);
   
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
   my ($self,$gene) = @_;

   #Will this work - let's hope so
   bless $gene,"Bio::Otter::AnnotatedGene";

   my $gene_info_adaptor         = $self->db->get_GeneInfoAdaptor();
   my $current_gene_info_adaptor = $self->db->get_CurrentGeneInfoAdaptor();

   my $infoid = $current_gene_info_adaptor->fetch_by_gene_id($gene->stable_id);
   my $info = $gene_info_adaptor->fetch_by_dbID($infoid);

   $gene->gene_info($info);

   my $transcript_info_adaptor = $self->db->get_TranscriptInfoAdaptor();
   my $ctia                    = $self->db->get_CurrentTranscriptInfoAdaptor;

   foreach my  $tran (@{$gene->get_all_Transcripts}) {
       
       bless $tran, "Bio::Otter::AnnotatedTranscript";

       eval {
	   my $infoid = $ctia->fetch_by_transcript_id($tran->stable_id);
	   my $info = $transcript_info_adaptor->fetch_by_dbID($infoid);
	   
	   $tran->transcript_info($info);
       };
       if ($@) {
	   print "Coulnd't fetch info for " . $tran->stable_id . " [$@]\n";
       }
   }
   
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

sub fetch_by_Slice{
    my ($self,$slice) = @_;

    #my @genes = @{$self->_fetch_by_Slice($slice)};

    my $genes = $slice->get_all_Genes;

    #my @genes = @{$self->SUPER::fetch_all_by_slice($slice)};
    #my @genes = @{$self->_fetch_by_Slice($slice)};


    my %genes;
    foreach my $g (@$genes) {
         my $stable_id = $g->stable_id;
         if (my $other = $genes{$stable_id}) {
             if ($g->version > $other->version) {
                 $genes{$stable_id} = $g;
             } 
         } else {
             $genes{$stable_id} = $g;
         }
    }
    my $latest_genes = [];
    foreach my $g (values %genes) {
        $self->annotate_gene($g);
        push(@$latest_genes, $g);
    }

    # Truncate gene components to Slice
    foreach my $g (@$latest_genes) {
        my $tsct_list = $g->get_all_Transcripts;
        
        for (my $i = 0; $i < @$tsct_list;) {
            my $transcript = $tsct_list->[$i];
            if ($transcript->truncate_to_Slice($slice)) {
                $g->gene_info->truncated_flag(1);
            }
            my $ex_list = $transcript->get_all_Exons;
            if (@$ex_list) {
                $i++;
            } else {
                # This will fail if get_all_Transcripts() ceases to return a ref
                # to the actual list of Transcripts inside the Gene object
                splice(@$tsct_list, $i, 1);
                $g->gene_info->truncated_flag(1);
            }
        }
    }

    return $latest_genes;
}

sub _fetch_by_Slice {
  my ( $self, $slice) = @_;

  my @out;

  my $mapper = $self->db->get_AssemblyMapperAdaptor->fetch_by_type
    ( $slice->assembly_type() );

  $mapper->register_region( $slice->chr_name(),
			    $slice->chr_start(),
			    $slice->chr_end());
  
  my @cids = $mapper->list_contig_ids( $slice->chr_name(),
				       $slice->chr_start(),
				       $slice->chr_end());
  # no contigs found so return
  if ( scalar (@cids) == 0 ) {
    return [];
  }
  
  my $str = "(".join( ",",@cids ).")";
  
  my $sql = "
    SELECT gsi.stable_id,gsi.version,t.gene_id
    FROM   transcript t,exon_transcript et,exon e ,gene_stable_id gsi
    WHERE  e.contig_id in $str 
    AND    et.exon_id = e.exon_id 
    AND    et.transcript_id = t.transcript_id
    AND    gsi.gene_id = t.gene_id";

  my $sth = $self->db->prepare($sql);

  $sth->execute;
  
  my %genes;
  my %versions;

  while( my ($stableid,$version,$geneid) = $sth->fetchrow ) {
      if (!defined($genes{$stableid})) {
	  $genes   {$stableid} = $geneid;
	  $versions{$stableid} = $version;
      } elsif ($versions{$stableid} < $version) {
	  $genes{$stableid} = $geneid;
	  $versions{$stableid} = $version;
          # print "Gene $stableid version now $version\n";
      }
  }
  foreach my $stableid (keys %genes) {
      my $geneid = $genes{$stableid};

      my $version = $versions{$stableid};

      my $gene = $self->fetch_by_dbID( $geneid );
      my $newgene = $gene->transform( $slice );  
      
      push( @out, $newgene );
  }

  #place the results in an LRU cache
  #$self->{'_slice_gene_cache'}{$slice->name} = \@out;
  #print "OUT @out\n";
  return \@out;
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

   #$obj->adaptor(undef);

   #foreach my $tran (@{$obj->get_all_Transcripts}) {
   #    $tran->adaptor(undef);
   #}
   $self->SUPER::store      ($obj);

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
