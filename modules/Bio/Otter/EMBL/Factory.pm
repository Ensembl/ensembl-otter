### Bio::Otter::EMBL::Factory
#
# Copyright 2004 Genome Research Limited (GRL)
#
# Maintained by Mike Croning <mdr@sanger.ac.uk>
#
# You may distribute this file/module under the terms of the perl artistic
# licence
#
# POD documentation main docs before the code. Internal methods are usually
# preceded with a _
#

=head1 NAME
 
Bio::Otter::EMBL::Factory
 
=head2 Constructor:

my $factory = Bio::Otter::EMBL::Factory->new;

=cut

package Bio::Otter::EMBL::Factory;

use strict;
use Carp;
use Hum::EMBL;
use Hum::EMBL::FeatureSet;
use Hum::EMBL::Location::Exon;
use Hum::EMBL::LocationUtils qw( simple_location locations_from_subsequence
    location_from_homol_block );
use Hum::EmblUtils qw( add_source_FT add_Organism );

Hum::EMBL->import(
    'AC *' => 'Hum::EMBL::Line::AC_star',
    'BQ *' => 'Hum::EMBL::Line::BQ_star',
    );


=head2 new

my $factory = Bio::Otter::EMBL::Factory->new;

=cut
	
sub new {
    my( $pkg ) = @_;
     
    return bless {}, $pkg;
}


=head2 organism_lines
 
?? 

=cut

sub organism_lines {

}


=head2 standard_comments
 
?? 

=cut

sub standard_comments {

}



=head2 get_DBAdaptors

    my ($otter_db, $slice_aptr, $gene_aptr) = get_DBAdaptors();

Providing $self->Dataset has been set, retrieves the cached DBAdaptor
from the Dataset, together with Slice and Gene adaptors.

=cut

sub get_DBAdaptors {
    my ( $self ) = @_;

    my $ds = $self->Dataset
        or confess "Dataset not set";

    #Bio::EnsEMBL::Container    
    my $otter_db = $ds->get_cached_DBAdaptor
        or confess 'Bio::Otter::Lace::DataSet->get_cached_DBAdaptor failed';

    #Bio::EnsEMBL::DBSQL::SliceAdaptor
    my $slice_aptr = $otter_db->get_SliceAdaptor
        or confess "get_SliceAdaptor failed";

    #Bio::EnsEMBL::DBSQL::ProxyGeneAdaptor
    my $gene_aptr  = $otter_db->get_GeneAdaptor
        or confess "get_GeneAdaptor failed";

    return ($otter_db, $slice_aptr, $gene_aptr);
}


sub fake_embl_setup {
    my ( $self, $embl, $acc, @sec ) = @_;
    
    # ID line
    my $id = $embl->newID;
    $id->entryname('fake');
    $id->dataclass('standard');
    $id->molecule('genomic DNA');
    $id->division('hum');
    $id->seqlength(150000);
    $embl->newXX;
    
    # AC line
    my $ac = $embl->newAC;
    if (@sec) {
        $ac->secondaries(@sec);
        # We need the placeholder "ACCESSION"
        # if we don't have an accession
        $ac->primary($acc);
    } else {
        $ac->primary($acc);
    }
    $embl->newXX;

    # AC * line
    my $ac_star = $embl->newAC_star;
    $ac_star->identifier('fake');
    $embl->newXX;

    # DE line
    #$pdmp->add_Description($embl);

    # KW line
    #$pdmp->add_Keywords($embl);

    # Organism
    #add_Organism($embl, $species);
    #$embl->newXX;

    # Reference
    #$pdmp->add_Reference($embl, $seqlength);

    # CC lines
    #$pdmp->add_Headers($embl, $contig_map);
    #$embl->newXX;

    # Feature table header
    $embl->newFH;

    # Feature table source feature
    #my( $libraryname ) = library_and_vector( $project );
    #add_source_FT( $embl, $seqlength, $binomial, $ext_clone,
    #               $chr, $map, $libraryname );



}

=head2 Embl
 
?? 

=cut

sub EMBL {
    my ( $self, $embl ) = @_;
    
    if ($embl) {
        $self->{'_bio_otter_embl_factory_embl'} = $embl;
    }
    return $self->{'_bio_otter_embl_factory_embl'};
}


=head2 contig_length
 
?? 

=cut

sub contig_length {
    my ( $self, $contig_length )  = @_;

    if ($contig_length) {
        $self->{'_bio_otter_embl_factory_contig_length'} = $contig_length;
    }
    return $self->{'_bio_otter_embl_factory_contig_length'};
}


=head2 Slice
 
?? 

=cut

sub Slice {
    my ( $self, $slice ) = @_;

    if ($slice) {
        $self->{'_bio_otter_embl_factory_slice'} = $slice;
    }    
    return $self->{'_bio_otter_embl_factory_slice'};
}

=head2 Slice_contig
 
?? 

=cut

sub Slice_contig {
    my ( $self, $slice_contig ) = @_;
    
    if ($slice_contig) {
        $self->{'_bio_otter_embl_factory_slice_contig'} = $slice_contig;
    }
    return $self->{'_bio_otter_embl_factory_slice_contig'};
}

=head2 FeatureSet
 
Holds the Hum::EMBL::FeatureSet object.

=cut

sub FeatureSet {
    my ( $self, $FeatureSet ) = @_;
    
    if ($FeatureSet) {
        $self->{'_bio_otter_embl_factory_feature_set'} = $FeatureSet;
    }
    return $self->{'_bio_otter_embl_factory_feature_set'};
}



    # Get polyA sites
    #$pdmp->addPolyA_toSet($set);
    
    # Get CpG islands
    #$pdmp->addCpG_toSet($set);
    
    # Add the genes and other features into the entry
    #$set->sortByPosition;
    #$set->removeDuplicateFeatures;
    #$set->addToEntry($embl);



=head2 make_embl
 
This is the big one!

=cut

sub make_embl {
    my ( $self, $acc ) = @_;

    confess "Must pass an accession" unless $acc;

    my $ds = $self->Dataset
        or confess "Dataset must be set before calling make_embl";

    my ($otter_db, $slice_aptr, $gene_aptr) = $self->get_DBAdaptors();
    my $embl = Hum::EMBL->new;
    $self->EMBL($embl);
    $self->fake_embl_setup($embl, $acc);

    my $set = 'Hum::EMBL::FeatureSet'->new;
    $self->FeatureSet($set);
    
    foreach my $chr_s_e ($self->fetch_chr_start_end_for_accession($otter_db, $acc)) {

        print "ACC: $acc ";  
        print "Chr: ", $chr_s_e->[0], " Start: "
            , $chr_s_e->[1], " End: ", $chr_s_e->[2], "\n";

        #Get the Bio::EnsEMBL::Slice
        my $slice = $self->Slice($slice_aptr->fetch_by_chr_start_end(@$chr_s_e));
        my $tile_path = $self->get_tiling_path_for_Slice($slice);

        #Bio::EnsEMBL::RawContig
        my $slice_contig = $self->Slice_contig($tile_path->[0]->component_Seq);
        my $contig_length = $self->contig_length($slice_contig->length);

        my $gene_id_list = $gene_aptr->list_current_dbIDs_for_Slice($slice);
        foreach my $gid (@$gene_id_list) {

            my $gene = $gene_aptr->fetch_by_dbID($gid);
            $self->do_Gene($gene);
        }
    }
    
    $self->fake_features;
    
    #Finish up, add the genes and other features into the entry
    $set->sortByPosition;
    $set->removeDuplicateFeatures;
    $set->addToEntry($embl);
    return $embl;
}

#Debugging just to see how features are made
sub fake_features {
    my ( $self ) = @_;
    
    my $set = $self->FeatureSet;
    
    #Hum::EMBL::Line::FT
    my $ft = $set->newFeature;
    my $key = 'mRNA'; # or 'CDS'
    $ft->key($key);
    
    my $loc = Hum::EMBL::Location->new;
    $loc->strand('W');
    $loc->exons([1000, 1024], [1048, 1100], [1112, 1196]);
    $ft->location($loc);
    $ft->addQualifierStrings('gene', "fcuk");
    $ft->addQualifierStrings('standard_name', "assmapper");
    $ft->addQualifierStrings('evidence','NOT_EXPERIMENTAL');
    
    my $ft2 = $set->newFeature;
    my $key2 = 'mRNA'; # or 'CDS'
    $ft2->key($key2);
    my $loc2 = Hum::EMBL::Location->new;
    $loc2->strand('C');
    $loc2->exons([2000, 2024], [2048, 2100], [2112, 2196]);
    $ft2->location($loc2);
    $ft2->addQualifierStrings('gene', "blows_chunks");
    $ft2->addQualifierStrings('standard_name', "badass");
    $ft2->addQualifierStrings('evidence','EXPERIMENTAL');

    my $ft3 = $set->newFeature;
    my $key3 = 'mRNA'; # or 'CDS'
    $ft3->key($key3);
    my $loc3 = Hum::EMBL::Location->new;
    $loc3->strand('C');
    $loc3->exons(34);
    $ft3->location($loc3);
    $ft3->addQualifierStrings('gene', "blows_chunks");
    $ft3->addQualifierStrings('standard_name', "badass");
    $ft3->addQualifierStrings('evidence','EXPERIMENTAL');

    #locations_from_subsequence ??

    #$ft->addQualifier($product);


  #  my $loc = simple_location(6104,7000);
}


=head2 do_Gene


=cut

sub do_Gene {
    my ( $self, $gene ) = @_;

    #Bio::Otter::AnnotatedGene, isa Bio::EnsEMBL::Gene
    return if $gene->type eq 'obsolete'; # Deleted genes

    my $contig_length = $self->contig_length;
    my $embl = $self->EMBL;
    my $set = $self->FeatureSet;
    

    #Bio::Otter::AnnotatedTranscript, isa Bio::EnsEMBL::Transcript
    #Transcript here give an mRNA, potentially + a CDS in EMBL record.
    foreach my $transcript (@{$gene->get_all_Transcripts}) {

        my $sid = $transcript->stable_id; #Currently not used
        
        #Do the mRNA fist
        my $all_transcript_Exons = $transcript->get_all_Exons;
        if ($all_transcript_Exons) {
            my $ft = $set->newFeature;
            $ft->key('mRNA');
            my $loc = Hum::EMBL::Location->new;
            $ft->location($loc);
            $loc->strand('W'); #By default, Exons may vary

            my @location_Exons;
            foreach my $exon (@{$all_transcript_Exons}) {

                my $location_Exon = Hum::EMBL::Location::Exon->new;
                $location_Exon->strand($exon->strand);
                
                #Bio::EnsEMBL::RawContig, each exon knows its contig
                my $contig  = $exon->contig;
                my $start   = $exon->start;
                my $end     = $exon->end;

                $location_Exon->start($start);
                $location_Exon->end($end);

                # May be an is_sticky method?
                if ($exon->isa('Bio::Ensembl::StickyExon')) {
                    # Deal with sticy exon
                    warn "STICKY!\n";
                }
                elsif ($contig != $self->Slice_contig()) {
                    # Is not on the Slice
                    my $acc = $contig->clone->embl_id;
                    my $sv  = $contig->clone->embl_version;
                }
                else {
                    # Is on Slice (ie: clone)
                    if ($end < 1 or $start > $contig_length) {
                        carp "Unexpected exon start '$start' end '$end' "
                            . "on contig of length '$contig_length'\n";
                    }
                }
                push(@location_Exons, $location_Exon);
            }
            $loc->exons(@location_Exons);
        }
    }
}


=head2 get_tiling_path_for_Slice

Wraps $slice->get_tiling_path, additionally checking there
is only 1 in component in the retrieved tiling_path

=cut

sub get_tiling_path_for_Slice {
    my ( $self, $slice ) = @_;
    
    my $tile_path = $slice->get_tiling_path;
    
    if (@$tile_path != 1) {
        my $count = @$tile_path;
        confess "Expected 1 component in tiling_path but have $count\n";
    }
    
    return $tile_path;
}

=head2 Dataset
 
Get/set method for the 'Bio::Otter::Lace::Dataset' object
used to access the Otter database.

=cut

sub Dataset {
    my ( $self, $obj ) = @_;
    
    if ($obj) {
        unless ($obj->isa('Bio::Otter::Lace::DataSet')) {
            confess "Must pass a 'Bio::Otter::Lace::DataSet' object\n";
        }
        $self->{'_bio_otter_embl_factory_dataset'} = $obj;
    }
    return $self->{'_bio_otter_embl_factory_dataset'};
}


=head2 fetch_chr_start_end_for_accession

When passed an Otter DBAdaptor and a Clone accession,
Returns an array of arrays of [chr, start, end]

eg. Such as [1, 561232, 672780]

=cut

sub fetch_chr_start_end_for_accession {
    my( $self, $db, $acc ) = @_;
    
    
    my $type = $db->assembly_type;
    
    my $sth = $db->prepare(q{
        SELECT chr.name
          , a.chr_start
          , a.chr_end
        FROM assembly a
          , contig c
          , clone cl
          , chromosome chr
        WHERE c.clone_id = cl.clone_id
          AND c.contig_id = a.contig_id
          AND chr.chromosome_id = a.chromosome_id
          AND cl.embl_acc = ?
          AND a.type = ?
        ORDER BY a.chr_start
        });
    $sth->execute($acc, $type);
    
    my( @chr_start_end );
    while (my ($chr, $start, $end) = $sth->fetchrow) {
        push(@chr_start_end, [$chr, $start, $end]);
    }
    if (@chr_start_end) {
        return @chr_start_end;
    } else {
        die "Clone with accession '$acc' not found on assembly '$type'\n";
    }
}


1;

__END__
 
=head1 NAME - Bio::Otter::EMBL::Factory
 
=head1 AUTHOR
 
Mike Croning B<email> mdr@sanger.ac.uk
 
