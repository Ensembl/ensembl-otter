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

=head1 NAME Bio::Otter::EMBL::Factory

=head2 Description

Factory object used to create Hum::EMBL objects in order to dump EMBL flatfiles
from an Otter finished & annotated genomic sequence database. Uses a variety of
of the Hum::EMBL modules.

First pass a Bio::Otter::Lace::DataSet object by a call to the DataSet method,
then call make_embl with an EMBL accession.

Typical usage:
 
  my $embl_factory = Bio::Otter::EMBL::Factory->new;
  $embl_factory->DataSet($ds);
    
  foreach my $acc (@ARGV) {
        
    my $embl = $embl_factory->make_embl($acc);
    print $embl->compose();

  }
 
=cut

package Bio::Otter::EMBL::Factory;

use strict;
use Carp;
use Hum::EMBL;
use Hum::EMBL::FeatureSet;
use Hum::EMBL::Exon;
use Hum::EMBL::ExonLocation;
use Hum::EMBL::LocationUtils qw( simple_location locations_from_subsequence
    location_from_homol_block );
use Hum::EmblUtils qw( add_Organism add_source_FT species_binomial );

Hum::EMBL->import(
    'AC *' => 'Hum::EMBL::Line::AC_star',
    'BQ *' => 'Hum::EMBL::Line::BQ_star',
    );


=head2 new

Constructor for the class.

    my $factory = Bio::Otter::EMBL::Factory->new;

=cut
	
sub new {
    my( $pkg ) = @_;
     
    return bless {}, $pkg;
}

=head2 comments
 
=cut

#Used
sub comments {
    my ( $self, $value ) = @_;
    
    if ($value) {
        unless (ref($value) eq 'ARRAY') {
            confess "Must pass an array reference";
        }
        unless ($self->{'_bio_otter_embl_factory_comments'}) {
            $self->{'_bio_otter_embl_factory_comments'} = [];
        }
        push(@{$self->{'_bio_otter_embl_factory_comments'}}, $value);
    }
    return $self->{'_bio_otter_embl_factory_comments'};
}

=head2 get_DBAdaptors

Providing $self->DataSet has been set, retrieves the cached DBAdaptor
from the DataSet, together with Slice and Gene adaptors.

    my ($otter_db, $slice_aptr, $gene_aptr
        , $annotated_clone_aptr) = get_DBAdaptors();

=cut

#Used
sub get_DBAdaptors {
    my ( $self ) = @_;

    my $ds = $self->DataSet or confess "DataSet not set";

    #Bio::EnsEMBL::Container    
    my $otter_db = $ds->get_cached_DBAdaptor
        or confess 'Bio::Otter::Lace::DataSet->get_cached_DBAdaptor failed';

    #Bio::EnsEMBL::DBSQL::SliceAdaptor
    my $slice_aptr = $otter_db->get_SliceAdaptor
        or confess "get_SliceAdaptor failed";

    #Bio::EnsEMBL::DBSQL::ProxyGeneAdaptor
    my $gene_aptr  = $otter_db->get_GeneAdaptor
        or confess "get_GeneAdaptor failed";

    my $annotated_clone_aptr = $otter_db->get_CloneAdaptor
        or confess "get_CloneAdaptor failed";

    return ($otter_db, $slice_aptr, $gene_aptr, $annotated_clone_aptr);
}

=head2 embl_setup

Used when creating EMBL annotation, by accessing an Otter database only, i.e.
independent of the Oracle tracking database. (Use humscripts/emblDump if
you want to dump a Sanger project in the tracking db from Otter).

Creates a Hum::EMBL object, and sets many of its attributes based on those
stored in the Hum::EMBL object. Will confess if required attributes have
not been set. Fetches some information from the Otter database, as necessary.

=cut 

#Used
sub embl_setup {
    
    my ( $self, $accession, $seq_version ) = @_;

    $self->accession($accession) if $accession;
    $self->sequence_version($seq_version) if $seq_version;

    my $embl = Hum::EMBL->new;    
    my @sec;
    if ($self->secondary_accs) {
        @sec = @{$self->secondary_accs};
    }
    my $entry_name = $self->entry_name or confess "entry_name not set";
    my $data_class = $self->data_class or confess "data_class not set";
    my $mol_type = $self->mol_type or confess "mol_type not set";
    my $ac_star_id = $self->ac_star_id or confess "ac_star_id not set";
    my $clone_lib = $self->clone_lib or confess "clone_lib not set";
    my $clone_name = $self->clone_name or confess "clone_name not set";
    my $comments_ref = $self->comments;
    
    # EMBL Division    
    my $division;
    my ($otter_division, $species) = $self->get_EMBL_division_from_otter_species;
    unless ($division = $self->division) {
        $division = $otter_division;
    }
    confess "division not set" unless $division;

    # Species
    

    my $id = $embl->newID;
    $id->entryname($entry_name);
    $id->dataclass($data_class);
    $id->molecule($mol_type);
    $id->division($division);

    # Sequence length
    my $seq_length;
    unless ($seq_length = $self->seq_length) {
        $seq_length = $self->get_clone_length_from_otter;
    }
    confess "Could not get clone length" unless $seq_length;

    $id->seqlength($seq_length);
    $embl->newXX;
    
    #Chromosome;
    my $chromosome_name;
    unless ($chromosome_name = $self->chromosome_name) {
        $chromosome_name = $self->get_chromosome_name_from_otter;
    }
    confess "Could not get chromosome name" unless $chromosome_name;
    
    # AC line
    my $ac = $embl->newAC;
    if (@sec) {
        $ac->secondaries(@sec);
        $ac->primary($accession);
    } else {
        $ac->primary($accession);
    }
    $embl->newXX;

    # AC * line
    my $ac_star = $embl->newAC_star;
    $ac_star->identifier($ac_star_id);
    $embl->newXX;

    # DE line
    my $description;
    unless ($description = $self->description) {
        $description = $self->get_description_from_otter;
    }
    my $de = $embl->newDE;
    $de->list($description);
    $embl->newXX;
    
    #KW line
    my @keywords;
    if ($self->keywords) {
        push(@keywords, $self->keywords);
    }
    push (@keywords, $self->get_keywords_from_otter);
    if (@keywords) {
        my $kw = $embl->newKW;
        $kw->list(@keywords);
        $embl->newXX;
    }

    #Organism
    add_Organism($embl, $species);
    $embl->newXX;

    # Reference
    #$pdmp->add_Reference($embl, $seqlength);

    # CC lines
    if ($comments_ref) {
        foreach my $comment_para (@{$comments_ref}) {
            $embl->newCC->list(@{$comment_para});
            $embl->newXX;
        }
    }

    #$pdmp->add_Headers($embl, $contig_map);
    #$embl->newXX;

    # Feature table header
    $embl->newFH;

    my $source = $embl->newFT;
    $source->key('source');

    my $loc = $source->newLocation;
    $loc->exons([1, $seq_length]);
    $loc->strand('W');
        
    $source->addQualifierStrings('mol_type',  $mol_type);
    $source->addQualifierStrings('organism',  species_binomial($species));
    $source->addQualifierStrings('chromosome',  $chromosome_name);
    $source->addQualifierStrings('clone',     $clone_name);
    $source->addQualifierStrings('clone_lib', $clone_lib);

    # Feature table source feature
    #my( $libraryname ) = library_and_vector( $project );
    #add_source_FT( $embl, $seqlength, $binomial, $ext_clone,
    #               $chr, $map, $libraryname );
    return $embl;
}

=pod

=head2 EMBL Database Divisions

    Division                Code
    -----------------       ----
    ESTs                    EST
    Bacteriophage           PHG
    Fungi                   FUN
    Genome survey           GSS
    High Throughput cDNA    HTC
    High Throughput Genome  HTG
    Human                   HUM
    Invertebrates           INV
    Mus musculus            MUS
    Organelles              ORG
    Other Mammals           MAM
    Other Vertebrates       VRT
    Plants                  PLN
    Prokaryotes             PRO
    Rodents                 ROD
    STSs                    STS
    Synthetic               SYN
    Unclassified            UNC
    Viruses                 VRL

=cut

{
    my %species_division = (
        'human'         => 'HUM',
        'gibbon'        => 'PRI',
        'mouse'         => 'MUS',
        'rat'           => 'ROD',
        'dog'           => 'MAM',

        'fugu'          => 'VRT',
        'zebrafish'     => 'VRT',
        'b.floridae'    => 'VRT',

        'drosophila'    => 'INV',
        
        'arabidopsis'   => 'PLN',
        );

=head2 get_EMBL_division_from_otter_species

=cut

    sub get_EMBL_division_from_otter_species {
        my( $self ) = @_;

        my $ds = $self->DataSet or confess "DataSet not set";
        my $species = $ds->species
            or confess "Could not get species from DataSet";
        
        $species = lc($species);    
        unless ($species_division{lc($species)}) {
            confess "Dont know EMBL_division for: $species";
        }
        return ($species_division{$species}, $species);
    }
}

=head2 add_sequence_from_otter

Gets the Clone dna sequence from the Contig attached to the Clone.
Confesses if there is more than one Contig in the Clone.

=cut

sub add_sequence_from_otter {
    my ( $self, $embl ) = @_;

    my $annotated_clone = $self->annotated_clone();
    my $contigs = $annotated_clone->get_all_Contigs();
    if (@$contigs > 1) {
        confess "More than one contig". $self->accession
            . $self->sequence_version;
    }
    $embl->newXX;
   $embl->newSequence->seq($contigs->[0]->seq);
}


sub references {
    my ( $self, $ref ) = @_;

}


sub CC_paragraphs {
    my ( $self, $CC ) = @_;

}

#Used
sub secondary_accs {
    my ( $self, $value ) = @_;
    
    if ($value) {
        unless (ref($value) =~ /ARRAY/) {
            confess "Must pass an array reference";
        }
        $self->{'_bio_otter_embl_factory_secondary_accs'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_secondary_accs'};
}

#Used
sub accession {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_accession'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_accession'};
}

#Used
sub chromosome_name {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_chromosome_name'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_chromosome_name'};
}

#Used
sub sequence_version {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_sequence_version'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_sequence_version'};
}

#Used
sub description {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_description'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_description'};
}

#Used
sub keywords {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_keywords'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_keywords'};
}

#Used
sub entry_name {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_entry_name'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_entry_name'};
}

#Used
sub data_class {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_data_class'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_data_class'};
}

=head2 mol_type

Get/set method for the embl mol_type. Defaults to 'genomic DNA' unless
set explicitly.

=cut

#Used
sub mol_type {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_mol_type'} = $value;
    } else {
        unless ($self->{'_bio_otter_embl_factory_mol_type'}) {
            $self->{'_bio_otter_embl_factory_mol_type'} = 'genomic DNA';
        }
    }
    return $self->{'_bio_otter_embl_factory_mol_type'};
}

#Used
sub division {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_division'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_division'};
}

#Used
sub seq_length {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_seq_length'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_seq_length'};
}

#Used
sub ac_star_id {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_ac_star_id'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_ac_star_id'};
}

#Used
sub clone_lib {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_clone_lib'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_clone_lib'};
}

#Used
sub clone_name {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_clone_name'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_clone_name'};
}


=head2 Embl

Get/set method for the Hum::EMBL object being constructed by the factory object.
Initially set by the make_embl method.
     
    my $embl = Hum::EMBL->new;
    $embl_factory->EMBL($embl);

    my $embl = $embl_factory->EMBL;

=cut

#Shall we keep this???
sub EMBL {
    my ( $self, $embl ) = @_;
    
    if ($embl) {
        $self->{'_bio_otter_embl_factory_embl'} = $embl;
    }
    return $self->{'_bio_otter_embl_factory_embl'};
}

=head2 contig_length

Get/set method for the contig_length of the Slice_contig on the tiling path 

=cut

#Shall we keep this???
sub contig_length {
    my ( $self, $contig_length )  = @_;

    if ($contig_length) {
        $self->{'_bio_otter_embl_factory_contig_length'} = $contig_length;
    }
    return $self->{'_bio_otter_embl_factory_contig_length'};
}

=head2 Slice

Get/set method for the Bio::EnsEMBL::Slice object being used to create the
annotation for the EMBL accession. Initially set by make_embl.

=cut

sub Slice {
    my ( $self, $slice ) = @_;

    if ($slice) {
        $self->{'_bio_otter_embl_factory_slice'} = $slice;
    }    
    return $self->{'_bio_otter_embl_factory_slice'};
}

=head2 Slice_contig

Get/set method for Slice_contig (a Bio::EnsEMBL::RawContig object) fetched
from the tiling path.

=cut

sub Slice_contig {
    my ( $self, $slice_contig ) = @_;
    
    if ($slice_contig) {
        $self->{'_bio_otter_embl_factory_slice_contig'} = $slice_contig;
        $self->contig_length($slice_contig->length);
    }
    return $self->{'_bio_otter_embl_factory_slice_contig'};
}

=head2 FeatureSet
 
Get/set method for the Hum::EMBL::FeatureSet object being constructed as part of the
Hum::EMBL object creation. Initially set by the make_embl method.

=cut

sub FeatureSet {
    my ( $self, $FeatureSet ) = @_;
    
    if ($FeatureSet) {
        $self->{'_bio_otter_embl_factory_feature_set'} = $FeatureSet;
    }
    return $self->{'_bio_otter_embl_factory_feature_set'};
}

=head2 make_embl_ft

This is the principal method of the module. When passed an EMBL accession,
a Hum::EMBL object and a sequence version, adds the FT lines to the
Hum::EMBL object.

Brief outline:

c)  Creates a Hum::EMBL::FeatureSet

d)  Calls $embl_factory->fetch_chr_start_end_for_accession to get a list of
    listrefs such as [1, 561232, 672780]

e)  Iterates of the chr_start_ends
    
      Fetches Slice by chr_start_end
      Gets tiling path for fetched slice
      Gets Slice_contig from tiling_path
      Gets a list of dbIDS for the Slice
    
      Iterates over the Gene ids

        Fetches Gene
        Calls $embl_factory->_do_Gene   

f)  Finishes up by calling Hum::EMBL::FeatureSet->sortByPosition
                           Hum::EMBL::FeatureSet->removeDuplicateFeatures
                           Hum::EMBL::FeatureSet->addToEntry

g)  Returns the populated Hum::EMBL object

=cut

sub make_embl_ft {
    my ( $self, $acc, $embl, $sequence_version ) = @_;

    unless ($acc and $embl and $sequence_version) {
        confess "Must pass an accession, Hum::EMBL object and sequence_version";
    }

    my $ds = $self->DataSet
        or confess "DataSet must be set before calling make_embl";

    my ($otter_db, $slice_aptr, $gene_aptr, $annotated_clone_aptr) 
        = $self->get_DBAdaptors();

    my $set = 'Hum::EMBL::FeatureSet'->new;
    
    foreach my $chr_s_e ($self->fetch_chr_start_end_for_accession($otter_db, $acc)) {

        #Get the Bio::EnsEMBL::Slice
        my $slice = $self->Slice($slice_aptr->fetch_by_chr_start_end(@$chr_s_e));
        my $tile_path = $self->get_tiling_path_for_Slice($slice);

        #Bio::EnsEMBL::RawContig
        $self->Slice_contig($tile_path->[0]->component_Seq);
 
        my $gene_id_list = $gene_aptr->list_current_dbIDs_for_Slice($slice);
        foreach my $gid (@$gene_id_list) {

            my $gene = $gene_aptr->fetch_by_dbID($gid);
            $self->_do_Gene($gene, $set);
        }
        
        #PolyA signals and sites for the slice
        $self->_do_polyA($slice, $set);   
    }
    
    #Finish up
    $set->sortByPosition;
    $set->removeDuplicateFeatures;
    $set->addToEntry($embl);
}

=head2 get_clone_length_from_otter

Gets the length of the clone sequence DNA from Otter. Checks
there is only one contig in the clone, otherwise confesses.

=cut

#Used
sub get_clone_length_from_otter {
    my ( $self ) = @_;
    
    my $annotated_clone = $self->annotated_clone();
    my $contigs = $annotated_clone->get_all_Contigs();
    if (@$contigs > 1) {
        confess "Can't work clone length for ". $self->accession
            . $self->sequence_version;
    }
    my $length = length($contigs->[0]->seq);
    return $length;
}

=head2 get_chromosome_name_from_otter

Gets the chromosome name from Otter by fetching the SequenceSet,
all and CloneSequences for it, then inspecting the first one.
Confesses if nothing is returned.

=cut

sub get_chromosome_name_from_otter {
    my ( $self ) = @_;
    
    my $ds = $self->DataSet or confess "DataSet not set";
    my $ss = $self->SequenceSet or confess "SequencSet not set";
    
    $ds->fetch_all_CloneSequences_for_SequenceSet($ss);
    
    my $name = $ss->CloneSequence_list->[0]->chromosome->name
        or confess "Cloud not get chromosome name from Otter\n";
    return $name;
}

=head2  _cache_annotated_clone

Internal method, to fetch clone from Otter using accession and
sequence version attributes. Confess if these have not
previously set.

=cut

sub _cache_annotated_clone {
    my ( $self ) = @_;
    
    my $accession = $self->accession or confess "accession not set";
    my $seq_version = $self->sequence_version
        or confess "sequence_version not set";
        
    my ($otter_db, $slice_aptr, $gene_aptr, $annotated_clone_aptr) 
        = $self->get_DBAdaptors();

    my $annotated_clone = $annotated_clone_aptr->fetch_by_accession_version(
        $accession, $seq_version)
        or confess "Could not fetch AnnotatedClone by accession_version"
        . "acc: $accession sv: $seq_version";
        
    $self->{'_bio_otter_embl_factory_annotated_clone'} = $annotated_clone;
}

=head2 annotated_clone

Returns the AnnotatedClone object point by accession and sequence_version.
If it is not already in memory, it is retrieved and stored with
_cache_annotated_clone

=cut

sub annotated_clone {
    my ( $self ) = @_;
    
    unless ($self->{'_bio_otter_embl_factory_annotated_clone'}) {
        $self->_cache_annotated_clone();
    }
    return $self->{'_bio_otter_embl_factory_annotated_clone'};
}

=head2 get_description_from_otter

Given an accession and sequence version, fetches thean Otter AnnotatedClone.
Gets the CloneRemark objects from the CloneInfo object and returns the
text of the one containing the description.

Warns if no CloneRemarks are fetched for the clone, returning undef.

=cut

sub get_description_from_otter {
	my ( $self ) = @_;
    
    my $annotated_clone = $self->annotated_clone();
    my $clone_info = $annotated_clone->clone_info
        or confess "could not get: CloneInfo object";
        
    my @clone_remarks = $clone_info->remark
        or warn "No CloneRemarks for annotated clone " . $self->accession
            . "." . $self->sequence_version;
    
    my ($description_txt);
    foreach my $clone_remark (@clone_remarks) {

        my $txt = $clone_remark->remark;
        if ($txt =~ s/^EMBL_dump_info.DE_line- //) {
            $description_txt = $txt;
            last;
        }
    }
    return($description_txt);
}

=head2 get_keywords_from_otter

Given an accession and sequence version, fetches thean Otter AnnotatedClone.
Gets the Keyword objects from the CloneInfo object and returns their text
as a list.

Warns if no Keyword objects are fetched for the clone, returning undef.

=cut 

sub get_keywords_from_otter {
	my ( $self ) = @_;
    
    my $annotated_clone = $self->annotated_clone();
    my $clone_info = $annotated_clone->clone_info
        or confess "could not get: CloneInfo object";
        
    my @keywords = $clone_info->keyword
        or warn "No CloneRemarks for annotated clone " . $self->accession
            . "." . $self->sequence_version;

    my @keywords_txt;
    foreach my $keyword (@keywords) {
        push (@keywords_txt, $keyword->name);
    }
    
    unless (@keywords_txt) {
        return;
    }
    
    return(@keywords_txt);
}


=head2 _do_polyA

Internal method called by make_embl to add lines of the type:

FT   polyA_site      156874
FT   polyA_signal    156832..156837
FT   polyA_site      complement(170534)
FT   polyA_signal    complement(170549..170554)

These are stored in Otter as SimpleFeatures on the Slice

=cut

sub _do_polyA {
    my ( $self, $slice, $set ) = @_;
    
    my $polyA_signal_feats = $slice->get_all_SimpleFeatures('polyA_signal');
    my $polyA_site_feats = $slice->get_all_SimpleFeatures('polyA_site');

    foreach my $polyA_signal (@$polyA_signal_feats) {

        my $ft = $set->newFeature;
        $ft->key('polyA_signal');

        my $loc = Hum::EMBL::Location->new;
        if ($polyA_signal->strand == 1) {
            $ft->location(simple_location($polyA_signal->start, $polyA_signal->end));
        } elsif ($polyA_signal->strand == -1) {
            $ft->location(simple_location($polyA_signal->end, $polyA_signal->start));
        } else {
            confess "Bad strand: ", $polyA_signal->strand;
        }
    }

    foreach my $polyA_site (@$polyA_site_feats) {
        
        my $ft = $set->newFeature;
        $ft->key('polyA_site');
        
        my $loc = Hum::EMBL::Location->new;
        $ft->location($loc);
        
        if ($polyA_site->strand == 1) {
            $loc->exons($polyA_site->end);
            $loc->strand('W');
        } elsif ($polyA_site->strand == -1) {
            $loc->exons($polyA_site->start);
            $loc->strand('C');
        } else {
            confess "Bad strand: ", $polyA_site->strand;
        }
    }
}


=head2 _do_Gene

Internal method to add FT lines to the Hum::EMBL object being built, according
to the passed gene object, and Hum::EMBL::FeatureSet

For each Transcript in the Gene object mRNA and CDS lines are added.

The mRNA is built up by iterating over all Exons ($transcript->get_all_Exons),
the CDS by Exons fetched with $transcript->get_all_translateable_Exons

For each mRNA, or CDS a Hum::EMBL::ExonLocation object is created to which
a number of Hum::EMBL::Exon objects are added (by _add_exons_to_exonlocation).

By checking if the Contig the Exon is located on is the same as the
Slice_contig, we determine whether the Exon is on the Slice (ie: clone)
or the adjacent one (in which case accession.sequence_version) needs to be
added to the newFeature being built up. At least one Exon must be on the
mRNA/CDS for it to be added.

Currently flags a warning, if StickyExon(s) are found.

=cut

sub _do_Gene {
    my ( $self, $gene, $set ) = @_;

    #Bio::Otter::AnnotatedGene, isa Bio::EnsEMBL::Gene
    return if $gene->type eq 'obsolete'; # Deleted genes

    #Bio::Otter::AnnotatedTranscript, isa Bio::EnsEMBL::Transcript
    #Transcript here give an mRNA, potentially + a CDS in EMBL record.
    foreach my $transcript (@{$gene->get_all_Transcripts}) {

        my $transcript_info = $transcript->transcript_info;
 
        #Do the mRNA
        my $all_transcript_Exons = $transcript->get_all_Exons;
        if ($all_transcript_Exons) {
            
            my $mRNA_exonlocation = Hum::EMBL::ExonLocation->new;
            
            #This will only return true if one or more Exons are on the Slice.
            if ($self->_add_exons_to_exonlocation($mRNA_exonlocation
                , $all_transcript_Exons)) {
                    
                my $ft = $set->newFeature;
                if ($gene->type !~ /pseudo/i) {
                    $ft->key('mRNA');
                } else {
                    $ft->key('CDS');
                }
                $ft->location($mRNA_exonlocation);
                $mRNA_exonlocation->start_not_found($transcript_info->mRNA_start_not_found);
                $mRNA_exonlocation->end_not_found($transcript_info->mRNA_end_not_found);
            
                $self->_add_gene_qualifiers($gene, $ft);
                
                if ($gene->type !~ /pseudo/i) {
                    $self->_supporting_evidence($transcript_info, $ft, 'EST', 'cDNA');
                } else {
                    $self->_supporting_evidence($transcript_info, $ft, 'Protein');
                }
            }
        } else {
            warn "No mRNA exons\n";
        }
        
        #Do the CDS, if it has a translation
        if ($transcript->translation) {

            my $all_CDS_Exons = $transcript->get_all_translateable_Exons;
            if ($all_CDS_Exons) {
            
                my $CDS_exonlocation = Hum::EMBL::ExonLocation->new;
                if ($self->_add_exons_to_exonlocation($CDS_exonlocation
                    , $all_CDS_Exons)) {
            
                    my $ft = $set->newFeature;
                    $ft->key('CDS');
                    $ft->location($CDS_exonlocation);
                    $CDS_exonlocation->start_not_found($transcript_info->cds_start_not_found);
                    $CDS_exonlocation->end_not_found($transcript_info->cds_end_not_found);

                    $self->_add_gene_qualifiers($gene, $ft);
                    $self->_supporting_evidence($transcript_info, $ft, 'Protein');
                    $ft->addQualifierStrings('standard_name', $transcript->translation->stable_id);
                }
            } else {
                warn "No CDS exons\n";
            }
        }
        
        #If gene->type =~ /pseudo/i
        
    }
}

=head2 _supporting_evidence

Internal method called by  _do_Gene. Passed a transcript_info object
(Bio::Otter::TranscriptInfo), and a feature object (Hum::EMBL::Line::FT)
and one or more evidence types, adds these to the feature object.

Evidence types understood: 'EST', 'cDNA' and 'Protein'.

Lines added to the EMBL entry generated will look like:

FT                   /note="match: ESTs: Em:BQ776835.1"
FT                   /note="match: cDNAs: Em:AK094249.1"
FT                   /note="match: proteins: Sw:P26367"

=cut

sub _supporting_evidence {
    my ( $self, $transcript_info, $ft, @evidence_types ) = @_;

    my %evidence_hash;
    foreach my $evidence ($transcript_info->evidence) {
        
        foreach my $evidence_type (@evidence_types) {
        
            if ($evidence->type eq $evidence_type) {
                $evidence_hash{$evidence_type} .= $evidence->name .' ';
                last;
            }
        }
    }
    
    foreach my $evidence_type (keys(%evidence_hash)) {
        
        chop ($evidence_hash{$evidence_type});
        if ($evidence_type eq 'EST') {
            $evidence_hash{$evidence_type} = 'match: ESTs: ' . $evidence_hash{$evidence_type};
        } elsif ($evidence_type eq 'cDNA') {
            $evidence_hash{$evidence_type} = 'match: cDNAs: ' . $evidence_hash{$evidence_type};
        } elsif ($evidence_type eq 'Protein') {
            $evidence_hash{$evidence_type} = 'match: proteins: ' . $evidence_hash{$evidence_type};
        } else {
            confess "Unrecognised evidence_type: $evidence_type";
        }
        $ft->addQualifierStrings('note', $evidence_hash{$evidence_type});
    }
}

=head2 _add_gene_qualifiers

Internal method called  by _do_gene. 

Passed a Gene object (Bio::Otter::AnnotatedGene) and a Feature
(Hum::EMBL::Line::FT)

FT                   /gene="PAX6"
FT                   /product="paired box gene 6 (aniridia, keratitis)"
FT                   /pseudo

by checking the Gene and Gene->gene_info properties.

=cut 

sub _add_gene_qualifiers {
    my ( $self, $gene, $ft ) = @_;

    my $gene_info = $gene->gene_info; #Bio::Otter::GeneInfo object

    if ($gene_info->known_flag) {
        $ft->addQualifierStrings('gene', $gene_info->name->name);
    }
    if ($gene->description) {
        $ft->addQualifierStrings('product', $gene->description);
    }
    if ($gene->type =~ /pseudo/i) {
        $ft->addQualifierStrings('pseudo');
    }            
} 


=head2 _add_exons_to_exonlocation

Internal method called by _do_gene. See the latter for doumentation.

Returns a count of how many exons are actually on the Slice (i.e. clone)
or undef if none are.

=cut

sub _add_exons_to_exonlocation {
    my ( $self, $exonlocation, $exons ) = @_;
    
    my (@hum_embl_exons , $exons_on_slice);
    foreach my $exon (@$exons) {

        my $hum_embl_exon = Hum::EMBL::Exon->new;
        $hum_embl_exon->strand($exon->strand);

        #Bio::EnsEMBL::RawContig, each exon knows its contig
        my $contig  = $exon->contig;
        my $start   = $exon->start;
        my $end     = $exon->end;

        my $slice_contig = $self->Slice_contig;
        my $contig_length = $self->contig_length;
        
        $hum_embl_exon->start($start);
        $hum_embl_exon->end($end);

        # May be an is_sticky method?
        if ($exon->isa('Bio::Ensembl::StickyExon')) {
            # Deal with sticy exon
            warn "STICKY!\n";
        }
        elsif ($contig->dbID != $slice_contig->dbID) {
            # Is not on the Slice
            my $acc = $contig->clone->embl_id;
            my $sv  = $contig->clone->embl_version;
            $hum_embl_exon->accession_version("$acc.$sv");
        }
        else {
            # Is on Slice (ie: clone)
            if ($end < 1 or $start > $contig_length) {
                carp "Unexpected exon start '$start' end '$end' "
                    . "on contig of length '$contig_length'\n";
            } else {
                $exons_on_slice++;
            }
        }
        push(@hum_embl_exons, $hum_embl_exon);
    }
    $exonlocation->exons(@hum_embl_exons);

    #Set the start and end for the Hum::EMBL::ExonLocation
    $exonlocation->start($hum_embl_exons[0]->start);
    $exonlocation->end($hum_embl_exons[-1]->end);
    return $exons_on_slice;
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

=head2 SequenceSet
 
Get/set method for the Bio::Otter::Lace::SequenceSet object
used to access the Otter database.

=cut

#Used 
sub SequenceSet {
    my ( $self, $obj ) = @_;
    
    if ($obj) {
        unless ($obj->isa('Bio::Otter::Lace::SequenceSet')) {
            confess "Must pass a 'Bio::Otter::Lace::SequenceSet' object\n";
        }
        $self->{'_bio_otter_embl_factory_SequenceSet'} = $obj;
    }
    return $self->{'_bio_otter_embl_factory_SequenceSet'};
}

=head2 DataSet
 
Get/set method for the Bio::Otter::Lace::DataSet object
used to access the Otter database.

=cut

#Used 
sub DataSet {
    my ( $self, $obj ) = @_;
    
    if ($obj) {
        unless ($obj->isa('Bio::Otter::Lace::DataSet')) {
            confess "Must pass a 'Bio::Otter::Lace::DataSet' object\n";
        }
        $self->{'_bio_otter_embl_factory_DataSet'} = $obj;
    }
    return $self->{'_bio_otter_embl_factory_DataSet'};
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
 
