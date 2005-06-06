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

Factory object used by:

/humscripts/emblDump

embDump uses the factory object to make the FT lines for the supplied
Hum::EMBL object (using the 'make_embl_ft' method). The EMBL entry
constructed and populated by other modules using information retrieved
from the Oracle Tracking database.

and 

/ensembl-otter/scripts/lace/otter_embl_dump_generic

otter_embl_dump_generic does not access the tracking database, so embl
entries can be dumped from any (potentially external) project. It uses
the 'embl_setup' method to construct and populate the Hum::EMBL object,
which is later used by'make_embl_ft'. Where Factory attributes are not
set specifically by the otter_embl_dump_generic script, where possible
they are fetched from the Otter database.

Note, many of the object attributes only need to be set if using the
'embl_setup' method of the module; they are not neccesary for
'make_embl_ft'.

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
use Hum::EmblUtils qw( add_Organism add_source_FT );
use Hum::Species;

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
 
For each block of CC lines, pass a reference to an array of the text
lines. Each block will be separated by an XX line.

=cut

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

=head2 reference

To add a reference of the type:

RN   [1]
RP   1-146328
RA   McMurray A.;
RT   ;
RL   Submitted (13-JUL-2004) to the EMBL/Genbank/DDBJ databases.
RL   Wellcome Trust Sanger Institute, Hinxton, Cambridgeshire, CB10 1SA, UK.
RL   E-mail enquiries: vega@sanger.ac.uk
RL   Clone requests: clonerequest@sanger.ac.uk

Pass a reference to an array of four elements:

    $reference_ref = ['1',  ' 1-146328', 'McMurray A.', \@text]

=cut

sub references {
    my ( $self, $value ) = @_;

    if ($value) {
        unless (ref($value) eq 'ARRAY' and scalar(@$value == 4)) {
            confess "Must pass an array reference pointing to 4 elements";
        }
        unless ($self->{'_bio_otter_embl_factory_references'}) {
            $self->{'_bio_otter_embl_factory_references'} = [];
        }
        push(@{$self->{'_bio_otter_embl_factory_references'}}, $value);
    }
    return $self->{'_bio_otter_embl_factory_references'};
}

=head2 get_DBAdaptors

Providing $self->DataSet has been set, retrieves the cached DBAdaptor
from the DataSet, together with Slice, Gene and Clone adaptors.

    my ($otter_db, $slice_aptr, $gene_aptr
        , $annotated_clone_aptr) = get_DBAdaptors();

=cut

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
not been set. Fetches information from the Otter database, as necessary.

=cut 

sub embl_setup {
    my ( $self ) = @_;

    my $accession   = $self->accession;
    my $seq_version = $self->sequence_version;

    my $embl = Hum::EMBL->new;    
    my @sec;
    if ($self->secondary_accs) {
        @sec = @{$self->secondary_accs};
    }
    my $entry_name = $self->entry_name or confess "entry_name not set";
    my $data_class = $self->data_class or confess "data_class not set";
    my $mol_type = $self->mol_type or confess "mol_type not set";
    my $clone_lib = $self->clone_lib;
    my $clone_name = $self->clone_name;
    my $comments_ref = $self->comments;
    my $references_ref = $self->references;
    
    # EMBL Division, species    
    my( $division );
    my $species = $self->get_Hum_Species;
    unless ($division = $self->division) {
        $division = $species->division;
    }
    confess "division not set" unless $division;
    
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
    $ac->primary($accession);
    if (@sec) {
        $ac->secondaries(@sec);
    }
    $embl->newXX;

    # SV line
    my $sv = $embl->newSV;
    $sv->accession($accession);
    $sv->version($seq_version);
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

    # Organism
    ### should change this argument to just pass $species itself.
    ### (Need to change in Hum::ProjectDump::EMBL too!)
    add_Organism($embl, $species->name);
    $embl->newXX;

    # Reference
    if ($references_ref) {
        foreach my $reference (@{$references_ref}) {
            my $ref = $embl->newReference;
            $ref->number($reference->[0]);
            $ref->positions($reference->[1]);
            $ref->authors($reference->[2]);
            $ref->locations(@{$reference->[3]});
        $embl->newXX;
        }
    }
    
    # CC lines
    if ($comments_ref) {
        foreach my $comment_para (@{$comments_ref}) {
            $embl->newCC->list(@{$comment_para});
            $embl->newXX;
        }
    }

    # Feature table header
    $embl->newFH;

    my $source = $embl->newFT;
    $source->key('source');

    my $loc = $source->newLocation;
    $loc->exons([1, $seq_length]);
    $loc->strand('W');
        
    $source->addQualifierStrings('mol_type',  $mol_type);
    $source->addQualifierStrings('organism',  $species->binomial);
    $source->addQualifierStrings('chromosome',  $chromosome_name);
    $source->addQualifierStrings('clone',     $clone_name) if $clone_name;
    $source->addQualifierStrings('clone_lib', $clone_lib) if $clone_lib;

    return $embl;
}


sub get_Hum_Species {
    my( $self ) = @_;

    my $ds = $self->DataSet or confess "DataSet not set";
    my $species_name = $ds->species
        or confess "Could not get species from DataSet";

    my $species = Hum::Species->fetch_Species_by_name($species_name)
        or confess "Can't fetch Hum::Species object for '$species_name'";
    return $species;
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

=head2 secondary_accs

Get/set method for secondary accessions. Expects and returns an
array reference.

=cut 

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

=head2 accession

Get/set method for the accession of the clone.

=cut

sub accession {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_accession'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_accession'};
}

=head2 chromosome_name

Get/set method for the name of the chromosome to which the clone
belongs.

=cut

sub chromosome_name {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_chromosome_name'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_chromosome_name'};
}

=head2 sequence_version

Get/set method for the sequence version of the clone.

=cut

sub sequence_version {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_sequence_version'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_sequence_version'};
}

=head2 desciption

Get/set method for the EMBL DE line description.

=cut

sub description {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_description'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_description'};
}


=head2 keywords

Get/set method for the EMBL KW line description. Expects a string of
the keywords separated by spaces.

=cut

sub keywords {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_keywords'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_keywords'};
}

=head2 entry_name

Get/set method for the EMBL entry name (shown in the ID line).
Generally the same as the accession.

=cut

sub entry_name {
    my ( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_bio_otter_embl_factory_entry_name'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_entry_name'};
}

=head2 data_class

Get/set method for the EMBL data class. Generally set to
'standard'.

=cut

sub data_class {
    my ( $self, $value ) = @_;

    if ($value) {
        $self->{'_bio_otter_embl_factory_data_class'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_data_class'};
}

=head2 mol_type

Get/set method for the EMBL mol_type. Defaults to 'genomic DNA' unless
set explicitly.

=cut

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


=head2 division

Get/set method for the EMBL divison.

=cut

sub division {
    my ( $self, $value ) = @_;

    if ($value) {
        $self->{'_bio_otter_embl_factory_division'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_division'};
}


=head2 division

Get/set method for the EMBL divison.

=cut

sub seq_length {
    my ( $self, $value ) = @_;

    if ($value) {
        $self->{'_bio_otter_embl_factory_seq_length'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_seq_length'};
}


=head2 clone_lib

Get/set method for the clone library name.

=cut

sub clone_lib {
    my ( $self, $value ) = @_;

    if ($value) {
        $self->{'_bio_otter_embl_factory_clone_lib'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_clone_lib'};
}

=head2 contig_length

Get/set method for the contig_length.

=cut

sub contig_length {
    my ( $self, $value ) = @_;

    if ($value) {
        $self->{'_bio_otter_embl_factory_contig_length'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_contig_length'};
}

=head2 clone_name

Get/set method for the clone name.

=cut

sub clone_name {
    my ( $self, $value ) = @_;

    if ($value) {
        $self->{'_bio_otter_embl_factory_clone_name'} = $value;
    }
    return $self->{'_bio_otter_embl_factory_clone_name'};
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

        #Bio::EnsEMBL::RawContig: turn slice coords. into RawContig coord
        my $slice_contig = $tile_path->[0]->component_Seq;
        $self->Slice_contig($slice_contig);

        my $gene_id_list = $gene_aptr->list_current_dbIDs_for_Slice($slice);
        foreach my $gid (@$gene_id_list) {

            my $gene = $gene_aptr->fetch_by_dbID($gid);
            my $type = $gene->type;
            
            # Don't dump deleted or non-Havana genes
            next if $type eq 'obsolete';
            next if $type =~ /^[A-Z]+:/;
            
            $self->_do_Gene($gene, $set);
        }

        #PolyA signals and sites for the slice
        $self->_do_polyA($slice_contig, $set);
       
        # assembly_tags on the slice
	$self->_do_assembly_tag($slice_contig, $set);
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

Given an accession and sequence version, fetches the Otter AnnotatedClone.
Gets the CloneRemark objects from the CloneInfo object and returns the
text of the one containing the description.

Warns if no CloneRemarks are fetched for the clone, returning undef.

=cut

sub get_description_from_otter {
	my ( $self ) = @_;
    
    my $annotated_clone = $self->annotated_clone();
    my $clone_info = $annotated_clone->clone_info
        or confess "could not get: CloneInfo object";
        
    my @clone_remarks = $clone_info->remark;
    
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

Given an accession and sequence version, fetches the Otter AnnotatedClone.
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

=head2 _do_assembly_tag

Internal method called by make_embl_ft to add lines of the type:

FT   assembly_tag    156832..156837
FT   assembly_tag    complement(170549..170554)

These are stored in Otter in assembly_tag table on the Slice

=cut


sub _do_assembly_tag {
  my ( $self, $slice, $set ) = @_;

  my $atags_Ad = $slice->adaptor->db->get_AssemblyTagAdaptor;

  # $atags_Ad inherits from Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor,
  # which inherits from Bio::EnsEMBL::DBSQL:BaseAdaptor
  # This also allows fetching AssemblyTag features by passing a RowContig obj to fetch_all_by_RawContig()

  my $atags = $atags_Ad->fetch_all_by_RawContig($slice); # slice obj transformed into RawContig obj

  foreach my $atag (@$atags) {

    my $feat = $set->newFeature;

    # assembly_tag types: Clone_left_end, Clone_right_end and Misc
    #                     are assigned "misc_feature" key,
    #                     whereas type "unsure" is assigned "unsure" key

   if ( $atag->tag_type eq "unsure" ){
      $feat->key('unsure');
    }
    else {
      $feat->key('misc_feature');
    }

    if ($atag->strand <= 1) {
      $feat->location(simple_location($atag->start, $atag->end));
    }
    elsif ($atag->strand == -1) {
      $feat->location(simple_location($atag->end, $atag->start));
    }

    # add qualifier
    if ( $atag->tag_type =~ /^Clone.+/ ){
      $feat->addQualifierStrings('note', $&.": ".$atag->tag_info)
    }
    else {
      $feat->addQualifierStrings('note', $atag->tag_info)
    }
  }
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
    my $polyA_site_feats   = $slice->get_all_SimpleFeatures('polyA_site');

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

my %ens2embl_phase = (
    0   => 1,
    2   => 2,
    1   => 3,
    );

sub _do_Gene {
    my ( $self, $gene, $set ) = @_;

    #Bio::Otter::AnnotatedTranscript, isa Bio::EnsEMBL::Transcript
    #Transcript here give an mRNA, potentially + a CDS in EMBL record.
    foreach my $transcript (@{$gene->get_all_Transcripts}) {

        my $transcript_info = $transcript->transcript_info;
        my $locus_tag = $transcript->transcript_info->name
            or warn "No transcript_info->name for locus_tag\n";
        if ($locus_tag =~ /^[A-Z]+:/) {
            # There are some GD: transcripts in Havana genes!
            warn "Skipping non-Havana transcript '$locus_tag'\n";
            next;
        }
 
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
                $ft->addQualifierStrings('locus_tag', $locus_tag);
                
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
                    if ($transcript_info->cds_start_not_found) {
                        $CDS_exonlocation->start_not_found(1);
                        my $phase = $all_transcript_Exons->[0]->phase;
                        my $embl_phase = $ens2embl_phase{$phase}
                            or confess "Bad exon phase '$phase'";
                        $ft->addQualifierStrings('codon_start', $embl_phase);
                    }
                    $CDS_exonlocation->end_not_found($transcript_info->cds_end_not_found);
                    
                    $self->_add_gene_qualifiers($gene, $ft);
                    $self->_supporting_evidence($transcript_info, $ft, 'Protein');
                    $ft->addQualifierStrings('standard_name', $transcript->translation->stable_id);
                    $ft->addQualifierStrings('locus_tag', $locus_tag);
                }
            } else {
                warn "No CDS exons\n";
            }
        }
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
    foreach my $evidence (@{$transcript_info->get_all_Evidence}) {
        
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
        #printf STDERR "Adding transcript of gene '%s'\n", $gene_info->name->name;
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
    my( @all_exons );
    foreach my $exon (@$exons) {
        if ($exon->isa('Bio::EnsEMBL::StickyExon')) {
            push(@all_exons, @{$exon->get_all_component_Exons});
        } else {
            push(@all_exons, $exon);
        }
    }
    foreach my $exon (@all_exons) {

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
        if ($exon->isa('Bio::EnsEMBL::StickyExon')) {
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
 
