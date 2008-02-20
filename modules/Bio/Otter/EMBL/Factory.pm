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
from the DataSet, together with Slice, Gene and ContigInfo adaptors.

    my ($otter_db, $slice_aptr, $gene_aptr
        , $annotated_contig_aptr) = get_DBAdaptors();

=cut

sub get_DBAdaptors {
    my ( $self ) = @_;

    my $ds = $self->DataSet or confess "DataSet not set";

    # Bio::Vega::DBSQL::DBAdaptor
    my $loutre_db = $ds->make_DBAdaptor
      or confess 'get Bio::Vega::DBSQL::DBAdaptor failed';

    my $ensdb_aptr = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
                                                      -user   => $ds->USER,
                                                      -dbname => $ds->DBNAME,
                                                      -host   => $ds->HOST,
                                                      -pass   => $ds->PASS,
                                                      -port   => $ds->PORT,
                                                      -driver => 'mysql');

    # Bio::EnsEMBL::DBSQL::GeneAdaptor
    my $gene_aptr  = $ensdb_aptr->get_GeneAdaptor
      or confess "get Bio::EnsEMBL::DBSQL::GeneAdaptor failed";

    #    # Bio::Vega::DBSQL::GeneAdaptor
    #    my $gene_aptr  = $loutre_db->get_GeneAdaptor
    #      or confess "get Bio::Vega::DBSQL::GeneAdaptor failed";


    # Bio::EnsEMBL::DBSQL::SliceAdaptor
    my $slice_aptr = $loutre_db->get_SliceAdaptor
      or confess "get Bio::EnsEMBL::DBSQL::SliceAdaptor failed";

    # Bio::Vega::DBSQL::ContigInfoAdaptor
    $loutre_db->get_ContigInfoAdaptor;
    my $annotated_contig_aptr = $loutre_db->get_ContigInfoAdaptor
      or confess "get Bio::Vega::DBSQL::ContigInfoAdaptor failed";

    return ($loutre_db, $ensdb_aptr, $slice_aptr, $gene_aptr, $annotated_contig_aptr);
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

    # New format ID line
    my $id = $embl->newID;
    $id->accession($accession);
    $id->version($seq_version);
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

    # DE line
    my $description;
    unless ($description = $self->description) {
        $description = $self->get_description_from_otter;
    }
    my $de = $embl->newDE;
    $de->list($description);
    $embl->newXX;

    # KW line
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
    my ( $self, $embl ) = @_;

    my $acc              = $self->accession;
    my $sequence_version = $self->sequence_version;

    my $ds = $self->DataSet
      or confess "DataSet must be set before calling make_embl";

    # my ($loutre_db, $ensdb_aptr, $slice_aptr, $gene_aptr, $annotated_contig_aptr)
    #   = $self->get_DBAdaptors();
    
    my $ens_db = $ds->make_EnsEMBL_DBAdaptor;
    my ($chr_name, $chr_start, $chr_end,
        $ctg_name, $ctg_start, $ctg_end,
        $ctg_ori) = $self->get_ctg_coordinate_details($ens_db, "$acc.$sequence_version");
    warn "\nContig: ", quote_row($chr_name, $chr_start, $chr_end, $ctg_name, $ctg_start, $ctg_end, $ctg_ori);
    
    # Not sure if we need $ctg_ori
    my $chr_slice = $ens_db->get_SliceAdaptor->fetch_by_region('chromosome', $chr_name, $chr_start, $chr_end, $ctg_ori);
    my $ctg_slice = $ens_db->get_SliceAdaptor->fetch_by_region('contig', $ctg_name);

    my $set = 'Hum::EMBL::FeatureSet'->new;

    # no lazy-loading transcripts,
    my $genes = $chr_slice->get_all_Genes;
    warn "Got ", scalar @$genes, " gene(s)";

    # won't include this FT line if no genes are annotated
    # originally to deal with tomato clones
    if ( $genes->[0] ){
        # add component_start/end of accession to indicate region of annotation
        # the position of this code here makes it appears as the first FT line
        # in the embl dump
        my $feat = $embl->newFT;
        $feat->key('misc_feature');
        $feat->location(simple_location($ctg_start, $ctg_end));
        $feat->addQualifierStrings('note', "annotated region of clone");

        foreach my $gene (@$genes) {
            # Don't dump deleted or non-Havana genes
            next if $gene->biotype eq 'obsolete';
            next if $gene->source ne 'havana';

            # $self->_do_Gene($gene, $set, $chr_slice);
            $self->process_gene($set, $ens_db, $ctg_name, $gene);
        }
    }

    # PolyA signals and sites are on chrom. slice
    $self->_do_polyA($chr_slice, $set);

    # Assembly_tags are on the contig slice
    $self->_do_assembly_tag($ctg_slice, $set);

    # Finish up
    $set->sortByPosition;
    $set->removeDuplicateFeatures;
    $set->addToEntry($embl);
}


sub get_ctg_coordinate_details {
    my ($self, $ens_db, $acc) = @_;
    
    my $get_ctg_coords = $ens_db->dbc->prepare(q{
        SELECT chr.name
          , a.asm_start
          , a.asm_end
          , ctg.name
          , a.cmp_start
          , a.cmp_end
          , a.ori
        FROM seq_region ctg
          , assembly a
          , seq_region chr
        LEFT JOIN seq_region_attrib hide
          ON chr.seq_region_id = hide.seq_region_id
          AND hide.attrib_type_id =
            (SELECT attrib_type_id
                FROM attrib_type
                WHERE code = 'hidden')
        WHERE ctg.seq_region_id = a.cmp_seq_region_id
          AND a.asm_seq_region_id = chr.seq_region_id
          AND ctg.coord_system_id =
            (SELECT coord_system_id
                FROM coord_system
                WHERE name = 'contig')
          AND chr.coord_system_id =
            (SELECT coord_system_id
                FROM coord_system
                WHERE name = 'chromosome'
                  AND version = 'Otter')
          AND hide.value = 0
          AND ctg.name like ?
    });
    
    $get_ctg_coords->execute("$acc%");
    
    if ($get_ctg_coords->rows > 1) {
        my $err = "Too many rows from coordinate fetching query:\n";
        while (my @row = $get_ctg_coords->fetchrow) {
            $err .= quote_row(@row);
        }
        die $err;
    }
    elsif ($get_ctg_coords->rows == 0) {
        die "No rows from contig coordinate query for '$acc%'"
    }
    else {
        return $get_ctg_coords->fetchrow;
    }
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

    my ($loutre_db, $ensdb_aptr, $slice_aptr, $gene_aptr, $annotated_contig_aptr) = $self->get_DBAdaptors();
    my  $clone_slice = $slice_aptr->fetch_by_region('clone', $accession.".".$seq_version)
      or confess "Could not fetch clone slice by accession_version "
        . "acc: $accession sv: $seq_version";

    $self->{'_bio_otter_embl_factory_annotated_clone'} = $clone_slice;
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

    my ($loutre_db, $ensdb_aptr, $slice_aptr, $gene_aptr, $annotated_contig_aptr)
      = $self->get_DBAdaptors();

    my $clone_slice = $self->annotated_clone();
    my $ctgname     = $clone_slice->seq_region_name.".".$clone_slice->start.".".$clone_slice->end;
    my $ctg         = $clone_slice->adaptor->fetch_by_region('contig', $ctgname);

    # need to turn DBAdaptor to loutre from Ensembl to work with contig_info
    $clone_slice->adaptor()->db($loutre_db);
    my $ctginfo_ad  = $clone_slice->adaptor->db->get_ContigInfoAdaptor;
    my $ctginfo     = $ctginfo_ad->fetch_by_seq_region_id($ctg->get_seq_region_id);

    unless ( $ctginfo ){ print STDERR "No description for $ctgname\n"; return '' }

    warn "$ctgname [seq_reg id: ", $ctg->get_seq_region_id, "] [contig_info_id: ", $ctginfo->dbID, "]";
    my $desc;
    eval { $desc = $ctginfo->get_all_Attributes('description')->[0]->value };
    $desc = '' if $@;
    return $desc;
}

=head2 get_keywords_from_otter

Given an accession and sequence version, fetches the Otter AnnotatedClone.
Gets the Keyword objects from the CloneInfo object and returns their text
as a list.

Warns if no Keyword objects are fetched for the clone, returning undef.

=cut 

sub get_keywords_from_otter {
	my ( $self ) = @_;

    my $clone_slice = $self->annotated_clone();
    my $ctgname     = $clone_slice->seq_region_name.".".$clone_slice->start.".".$clone_slice->end;
    my $ctg         = $clone_slice->adaptor->fetch_by_region('contig', $ctgname);
    my $ctginfo_ad  = $clone_slice->adaptor->db->get_ContigInfoAdaptor;
    my $ctginfo     = $ctginfo_ad->fetch_by_seq_region_id($ctg->get_seq_region_id);

    unless ( $ctginfo ){ print STDERR "No keyword for $ctgname\n"; return };

    my @keywords_txt;

    foreach my $desc ( @{$ctginfo->get_all_Attributes} ){
      push(@keywords_txt, $desc->value) if $desc->code eq 'keyword';
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

These are stored in Otter in assembly_tag table and as misc_features
Fetch them via misc_feature
=cut


sub _do_assembly_tag {
  my ( $self, $slice, $set ) = @_;

  # get assembly_tags as misc_features
  my $mfa = $slice->adaptor->db->get_MiscFeatureAdaptor;

  my $misc_feats = [];
  foreach my $code ( qw(atag_CLE atag_CRE atag_Misc atag_Unsure) ){
    push(@$misc_feats, @{$mfa->fetch_all_by_Slice_and_set_code($slice, $code)})
  }

  unless ( $misc_feats->[0] ) {
    print STDERR "No misc_feature for assembly_tag ...\n";
    return(0);
  }
  else {
    print STDERR "Fetching ", scalar @$misc_feats, " misc_feature(s) for assembly_tag(s) ...\n";
  }

  foreach my $mf (@$misc_feats) {

    foreach my $atag ( @{$mf->get_all_Attributes} ){

      my $feat = $set->newFeature;

      # assembly_tag types: Clone_left_end, Clone_right_end and Misc
      #                     are assigned "misc_feature" key,
      #                     whereas type "unsure" is assigned "unsure" key

      if ( $atag->code eq "atag_Unsure" ){
        $feat->key('unsure');
      }
      else {
        $feat->key('misc_feature');
      }

      if ($mf->strand <= 1) {
        $feat->location(simple_location($mf->start, $mf->end));
      }
      elsif ($mf->strand == -1) {
        $feat->location(simple_location($mf->end, $mf->start));
      }

      # add qualifier
      if ( $atag->name =~ /^Clone.+/ ){
        $feat->addQualifierStrings('note', $&.": ".$atag->value)
      }
      else {
        $feat->addQualifierStrings('note', $atag->value)
      }
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

sub process_gene {
    my ($self, $set, $ens_db, $ctg_name, $gene) = @_;
    
    $gene = $ens_db->get_GeneAdaptor->fetch_by_dbID($gene->dbID);

    my $gtype = $gene->biotype;
    
    foreach my $transcript (@{$gene->get_all_Transcripts}) {
        my $name = $transcript->get_all_Attributes('name')->[0]->value;
        if ($name =~ /[A-Z]+:/) {
            # There are some GD: transcripts in Havana genes!
            warn "Skipping non-Havana transcript '$name'\n";
            next;
        }
        
        # Create mRNA feature
        my $mRNA_exonlocation = $self->make_ExonLocation($ctg_name, $transcript->get_all_Exons)
            or next;

        my $ft = $set->newFeature;
        $ft->location($mRNA_exonlocation);
        if ($gtype eq "transposon") {
            $ft->key('repeat_region');
            $ft->addQualifierStrings('mobile_element', "transposon");
        } elsif ($gtype =~ /pseudo/i) {
            $ft->key('CDS');
        } else {
            $ft->key('mRNA');
        }

        $mRNA_exonlocation->start_not_found($transcript->get_all_Attributes('mRNA_start_NF')->[0]->value);
        $mRNA_exonlocation->end_not_found(  $transcript->get_all_Attributes('mRNA_end_NF'  )->[0]->value);

        $self->_add_gene_qualifiers($gene, $ft) if $gtype ne "transposon";
        $ft->addQualifierStrings('locus_tag', $name);

        if ($gtype =~ /pseudo/i) {
            $self->_supporting_evidence($transcript, $ft, 'Protein');
        } else {
            $self->_supporting_evidence($transcript, $ft, 'EST', 'cDNA');
        }
        
        # Create CDS feature
        if ($ft->key eq 'mRNA'  # It isn't a weird type of transcript
            and $transcript->translation
            and $transcript->biotype ne "nonsense_mediated_decay")
        {
            my $CDS_exonlocation = $self->make_ExonLocation($ctg_name, $transcript->get_all_translateable_Exons)
                or next;

            my $cds_ft = $set->newFeature;
            $cds_ft->location($CDS_exonlocation);
            $cds_ft->key('CDS');

            if ($transcript->get_all_Attributes('cds_start_NF')->[0]->value) {
                $CDS_exonlocation->start_not_found(1);

                my $phase = ($CDS_exonlocation->exons)[0]->phase;
                my $embl_phase = $ens2embl_phase{$phase}
                    or confess "Bad exon phase '$phase'";
                $cds_ft->addQualifierStrings('codon_start', $embl_phase);
            }
            $CDS_exonlocation->end_not_found($transcript->get_all_Attributes('cds_end_NF')->[0]->value);

            $self->_add_gene_qualifiers($gene, $cds_ft);
            $self->_supporting_evidence($transcript, $cds_ft, 'Protein');
            $cds_ft->addQualifierStrings('standard_name', $transcript->translation->stable_id);
            $cds_ft->addQualifierStrings('locus_tag', $name);
        }
    }
}

sub _do_Gene {
  my ( $self, $gene, $set, $chrslice ) = @_;

  my $gtype = $gene->status;

  #Bio::Vega::Transcript, isa Bio::EnsEMBL::Transcript
  #Transcript here give an mRNA, potentially + a CDS in EMBL record.
  foreach my $transcript (@{$gene->get_all_Transcripts}) {

    #    warn %$transcript;
    my $locus_tag = $transcript->get_all_Attributes('name')->[0]->value
      or warn "No locus_tag for ", $transcript->stable_id, "\n";
    if ($locus_tag =~ /^[A-Z]+:/) {
      # There are some GD: transcripts in Havana genes!
      warn "Skipping non-Havana transcript '$locus_tag'\n";
      next;
    }

    #  #Do the mRNA
    my $all_transcript_Exons = $transcript->get_all_Exons;
    if ($all_transcript_Exons) {

      my $mRNA_exonlocation = Hum::EMBL::ExonLocation->new;

      #This will only return true if one or more Exons are on the Slice.
      if ($self->_add_exons_to_exonlocation($mRNA_exonlocation
                                            , $all_transcript_Exons, $chrslice)) {

        my $ft = $set->newFeature;
        if ( $gtype eq "Transposon" ) {
          $ft->key('repeat_region');
          $ft->addQualifierStrings('mobile_element', "transposon");
        } elsif ($gtype !~ /pseudo/i) {
          $ft->key('mRNA');
        } else {
          $ft->key('CDS');
        }
        $ft->location($mRNA_exonlocation);
        $mRNA_exonlocation->start_not_found($transcript->get_all_Attributes('mRNA_start_NF')->[0]->value);
        $mRNA_exonlocation->end_not_found($transcript->get_all_Attributes('mRNA_end_NF')->[0]->value);

        $self->_add_gene_qualifiers($gene, $ft) if $gtype ne "Transposon";
        $ft->addQualifierStrings('locus_tag', $locus_tag);

        if ($gtype !~ /pseudo/i) {
          $self->_supporting_evidence($transcript, $ft, 'EST', 'cDNA');
        } else {
          $self->_supporting_evidence($transcript, $ft, 'Protein');
        }
      }
    } else {
      warn "No mRNA exons\n";
    }

    next if $gtype eq "Transposon";

    #Do the CDS, if it has a translation
    if ($transcript->translation) {

      # HAVANA have recently changed NMD
      # transcripts from non-coding into coding transcripts because analysis
      # done on them in Vega is better etc. However these should not be
      # submitted in the EMBL flat files as coding peptides as it causes
      # problems in translation for Uniprot - message from Havana group
      if ( $transcript->biotype eq "nonsense_mediated_decay" ){
        warn "NMD - TRANSNAME: ", $transcript->get_all_Attributes('name')->[0]->value;
        next;
      }

      my $all_CDS_Exons = $transcript->get_all_translateable_Exons;

      if ($all_CDS_Exons) {
        my $CDS_exonlocation = Hum::EMBL::ExonLocation->new;
        if ($self->_add_exons_to_exonlocation($CDS_exonlocation
                                              , $all_CDS_Exons, $chrslice)) {

          my $ft = $set->newFeature;

          $ft->key('CDS');
          $ft->location($CDS_exonlocation);
          if ($transcript->get_all_Attributes('cds_start_NF')->[0]->value) {
            $CDS_exonlocation->start_not_found(1);

            my $phase = $all_CDS_Exons->[0]->phase;
            my $embl_phase = $ens2embl_phase{$phase}
              or confess "Bad exon phase '$phase'";
            $ft->addQualifierStrings('codon_start', $embl_phase);
          }
          $CDS_exonlocation->end_not_found($transcript->get_all_Attributes('cds_end_NF')->[0]->value);

          $self->_add_gene_qualifiers($gene, $ft);
          $self->_supporting_evidence($transcript, $ft, 'Protein');
          $ft->addQualifierStrings('standard_name', $transcript->translation->stable_id);
          $ft->addQualifierStrings('locus_tag', $locus_tag);
        }
      } else {
        warn "No CDS exons\n";
      }
    }
  }
}

sub make_ExonLocation {
    my ($self, $ctg_name, $exon_list) = @_;
    
    my $loc = Hum::EMBL::ExonLocation->new;
    
    my @all_exons;
    foreach my $exon (@$exon_list) {
        foreach my $seg (@{$exon->project('contig')}) {
            push(@all_exons, $self->make_Hum_EMBL_Exon($ctg_name, $seg->to_Slice));
        }
    }
    
    # Check that there is an exon in the contig being dumped
    my $exon_in_ctg = 0;
    foreach my $exon (@all_exons) {
        unless ($exon->accession_version) {
            $exon_in_ctg = 1;
            last;
        }
    }
    if ($exon_in_ctg) {
        my $loc = Hum::EMBL::ExonLocation->new;
        $loc->exons(@all_exons);
        return $loc;
    } else {
        return;
    }
}

sub make_Hum_EMBL_Exon {
    my ($self, $ctg_name, $obj) = @_;
    
    my $embl_exon = Hum::EMBL::Exon->new;
    $embl_exon->start(  $obj->start  );
    $embl_exon->end(    $obj->end    );
    $embl_exon->strand( $obj->strand );
    
    if ($obj->seq_region_name ne $ctg_name) {
        my ($acc_sv) = $obj->seq_region_name =~ /^(\w+\.\d+)/;
        $embl_exon->accession_version($acc_sv);
    }
    
    return $embl_exon;
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
  my ( $self, $transcript, $ft, @evidence_types ) = @_;

  my $ta = $transcript->adaptor->db->get_TranscriptAdaptor();
  my ($evids, $evidence);

  eval { $evids = $ta->fetch_evidence($transcript) };

  my %evidence_hash;
  foreach my $evid ( @$evids ){
    foreach my $evidence_type (@evidence_types) {
      if ($evid->type eq $evidence_type) {
        $evidence_hash{$evidence_type} .= $evid->name .' ';
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

  if ($gene->status eq "KNOWN") {
    #printf STDERR "Adding transcript of gene '%s'\n", $gene_info->name->name;
    $ft->addQualifierStrings('gene', $gene->get_all_Attributes('name')->[0]->value);
  }
  if ($gene->description) {
    $ft->addQualifierStrings('product',  $gene->description);
  }
  if ($gene->biotype =~ /pseudo/i) {
    $ft->addQualifierStrings('pseudo');
  }
}


=head2 _add_exons_to_exonlocation

Internal method called by _do_gene. See the latter for doumentation.

Returns a count of how many exons are actually on the Slice (i.e. clone)
or undef if none are.

=cut

sub _add_exons_to_exonlocation {
  my ( $self, $exonlocation, $exons, $chrslice ) = @_;

  my (@hum_embl_exons , $exons_on_slice);
  my( @all_exons );
  my $sa = $chrslice->adaptor;
  my $seqset = $self->DataSet->selected_SequenceSet;

  foreach my $exon (@$exons) {
    if ($exon->isa('Bio::EnsEMBL::StickyExon')) {
      push(@all_exons, @{$exon->get_all_component_Exons});
    } else {
      push(@all_exons, $exon);
    }
  }

  foreach my $exon (@all_exons) {

    my $hum_embl_exon = Hum::EMBL::Exon->new;

    #my $contig  = $exon->contig; # deprecated
    my $start   = $exon->start;
    my $end     = $exon->end;
    my $strand  = $exon->strand;
    my $slice_contig = $self->Slice_contig; # contig projected to chr
    my $contig_length = $self->contig_length;

    if ($end < 1 or $start > $slice_contig->length) {
      # these exons are on another contig
      # warn $exon->stable_id;
      # carp "Unexpected exon start '$start' end '$end' "
      #   . "on contig of length '$contig_length'\n";
      my $exonCtg = $exon->transform('contig');
      my ($acc_sv) = $exonCtg->seq_region_name =~ /^(\w+\.\d+)/;
      $hum_embl_exon->accession_version($acc_sv);

      $start = $exonCtg->start;
      $end   = $exonCtg->end;
      $strand = $exonCtg->strand;
    }
    elsif ( ($start < 1 and $end > 1) or ($start < $slice_contig->length and $end > $slice_contig->length) ) {
      # do something with overlapping exons in clone boundary
      #testing
    #  warn "Exons in clone boundary: clone LEN: ", $slice_contig->length;
#      warn "START-1: $start == END-1: $end === STRAND-1: $strand";
#      my $exonCtg = $exon->transform('contig');
#      my ($acc_sv) = $exonCtg->seq_region_name =~ /^(\w+\.\d+)/;
#      warn "$acc_sv, $exonCtg";
#      $hum_embl_exon->accession_version($acc_sv);
#      $start = $exonCtg->start;
#      $end   = $exonCtg->end;
#      $strand = $exonCtg->strand;
#      warn "START-2: $start == END-2: $end === STRAND-2: $strand";
    }
    else {
      $exons_on_slice++;
    }
    $hum_embl_exon->start($start);
    $hum_embl_exon->end($end);
    $hum_embl_exon->strand($strand);
    push(@hum_embl_exons, $hum_embl_exon);
  }
  $exonlocation->exons(@hum_embl_exons);

  #Set the start and end for the Hum::EMBL::ExonLocation
  $exonlocation->start($hum_embl_exons[0]->start);
  $exonlocation->end($hum_embl_exons[-1]->end);
  return $exons_on_slice;
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

1;

__END__

=head1 NAME - Bio::Otter::EMBL::Factory

=head1 AUTHOR

Mike Croning B<email> mdr@sanger.ac.uk

Chao-Kung Chen B<emai> ck1@sanger.ac.uk (updated for new schema)
