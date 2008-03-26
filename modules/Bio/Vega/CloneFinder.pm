package Bio::Vega::CloneFinder;

#
# A module used by server script 'find_clones' to find things on clones
# (new API version)
#

use strict;
use Bio::Otter::Lace::Locator;

my $component = 'clone'; # this is the type of components we want the found matches mapped on
my $DEBUG=0; # do not show all SQL statements

sub new {
    my ($class, $dba, $qnames) = @_;

    my $self = bless {
        '_dba' => $dba,
        '_ql'  => ($qnames ? {map {(uc($_) => [])} @$qnames } : {}),
    }, $class;

    return $self;
}

sub dba {
    my $self = shift @_;

    return $self->{_dba};
}

sub dbc {
    my $self = shift @_;

    return $self->dba->dbc();
}

sub qnames_locators {
#
# This is a HoL
# {query_name}[locators*]
#
    my $self = shift @_;

    return $self->{_ql};
}

sub find_containing_chromosomes {
    my ($self, $slice) = @_;

        # EnsEMBL as of rel46 cannot perform ambigous clone|subregion->contig->chromosome mapping correctly.
        # So we prefer to do it using direct SQL:
        
    my $sa = $self->dba()->get_SliceAdaptor();

        # map the original slice onto contig_ids
    my $seq_level_slice_ids = [ $slice->coord_system->is_sequence_level()
        ? $sa->get_seq_region_id($slice)
        : map { $sa->get_seq_region_id($_->to_Slice()) } @{$slice->project('seqlevel')}
    ];

        # now map those contig_ids back onto a chromosome
    my $sql = qq{
        SELECT  chr.name,
                group_concat(distinct a.cmp_seq_region_id) as joined_cmps
        FROM    assembly a,
                seq_region chr,
                coord_system cs
        WHERE   cs.name='chromosome'
        AND     cs.version='Otter'
        AND     cs.coord_system_id=chr.coord_system_id
        AND     chr.seq_region_id=a.asm_seq_region_id
        AND     a.cmp_seq_region_id IN (
    }.join(', ', @$seq_level_slice_ids).qq{
                )
     GROUP BY chr.name
    };

    my $sth = $self->dbc()->prepare($sql);
    $sth->execute();

    my @chr_slices = ();
    while( my ($atype, $joined_cmps) = $sth->fetchrow() ) {

        my @cmps = split(/,/, $joined_cmps);

        if(scalar(@cmps) == scalar(@$seq_level_slice_ids)) {
            my $chr_slice = $sa->fetch_by_region('chromosome', $atype, undef, undef, undef, 'Otter');
            push @chr_slices, $chr_slice;
        }
    }

    return \@chr_slices;
}

sub register_feature {
    my ($self, $qname, $qtype, $feature) = @_;


    my $unhide = $self->{_unhide};

    my $feature_slice = $feature->isa('Bio::EnsEMBL::Slice')
        ? $feature
        : $feature->feature_Slice();
    my $cs_name = $feature_slice->coord_system_name();

    my $component_names = [ ($cs_name eq $component)
        ? $feature_slice->seq_region_name
        : map { $_->to_Slice()->seq_region_name() }
                    # NOTE: order of projection segments WAS strand-dependent
                sort { ($a->from_start() <=> $b->from_start())*$feature->strand() }
                    @{ $feature_slice->project($component) } ];

    my $found_chromosome_slices = ($cs_name eq 'chromosome')
        ? [ $feature_slice ]
        : $self->find_containing_chromosomes($feature_slice);

    foreach my $chr_slice (@$found_chromosome_slices) {

        unless($unhide) {
            my ($hidden) = ((map {$_->value()} @{$chr_slice->get_all_Attributes('hidden')}), 1);

            next if $hidden;
        }

        my $loc = Bio::Otter::Lace::Locator->new($qname, $qtype);

        $loc->assembly( $chr_slice->seq_region_name() );
        $loc->component_names( $component_names );

        push @{ $self->qnames_locators()->{uc($qname)} }, $loc;
    }
}

sub find_by_stable_ids {
    my $self = shift @_;

    my $dba      = $self->dba();
    my $meta_con = $dba->get_MetaContainer();

    my $prefix_primary = $meta_con->get_primary_prefix()
        || die "'prefix.primary' missing from meta table";

    my $prefix_species = $meta_con->get_species_prefix()
        || die "'prefix.species' missing from meta table";

    my $gene_adaptor           = $dba->get_GeneAdaptor();
    my $transcript_adaptor     = $dba->get_TranscriptAdaptor();
    my $exon_adaptor           = $dba->get_ExonAdaptor();

    foreach my $qname (keys %{$self->qnames_locators()}) {
        if(uc($qname) =~ /^$prefix_primary$prefix_species([TPGE])\d+/i){ # try stable_ids
            my $typeletter = $1;
            my $qtype;
            my $feature;

            eval {
                if($typeletter eq 'G') {
                    $qtype = 'gene_stable_id';
                    $feature = $gene_adaptor->fetch_by_stable_id($qname);
                } elsif($typeletter eq 'T') {
                    $qtype = 'transcript_stable_id';
                    $feature = $transcript_adaptor->fetch_by_stable_id($qname);
                } elsif($typeletter eq 'P') {
                    $qtype = 'translation_stable_id';
                    $feature = $transcript_adaptor->fetch_by_translation_stable_id($qname);
                } elsif($typeletter eq 'E') {
                    $qtype = 'exon_stable_id';
                    $feature = $exon_adaptor->fetch_by_stable_id($qname);
                }
            };

                # Just imagine: they raise an EXCEPTION to indicate nothing was found. Terrific!
            if($@) {
                # warn "'$qname' looks like a stable id, but wasn't found.";
                # warn ($@) if $DEBUG;
            } elsif($feature) { # however watch out, sometimes we just silently get nothing!
                $self->register_feature($qname, $qtype, $feature);
            }
        }
    } # foreach $qname
}

sub find_by_feature_attributes {
    my ($self, $condition, $qtype, $table, $id_field, $code, $adaptor_call) = @_;

    my $sql = qq{
        SELECT $id_field, value
        FROM $table
        WHERE attrib_type_id = (SELECT attrib_type_id from attrib_type where code='$code')
          AND value $condition
    };

    my $dbc      = $self->dbc();
    my $sth = $dbc->prepare($sql);
    $sth->execute();

    my $adaptor;
    while( my ($feature_id, $qname) = $sth->fetchrow() ) {
        $adaptor ||= $self->dba()->$adaptor_call; # only do it if we found something

        my $feature = $adaptor->fetch_by_dbID($feature_id);

        if($feature->is_current()) {
            $self->register_feature($qname, $qtype, $feature);
        }
    }
}

sub find_by_seqregion_names {
    my ($self, $condition) = @_;

    my $dbc      = $self->dbc();
    my $adaptor;

    my $sql = qq{
        SELECT cs.name, sr.name
        FROM seq_region sr, coord_system cs
        WHERE sr.coord_system_id=cs.coord_system_id
          AND cs.name <> 'chromosome'
          AND sr.name $condition
    };

    my $sth = $dbc->prepare($sql);
    $sth->execute();
    while( my ($cs_name, $sr_name) = $sth->fetchrow() ) {
        $adaptor ||= $self->dba()->get_SliceAdaptor();

        my $slice = $adaptor->fetch_by_region($cs_name, $sr_name);

        $self->register_feature($sr_name, $cs_name.'_name', $slice);
    }
}

sub find_by_seqregion_attributes {
    my ($self, $condition, $qtype, $cs_name, $code) = @_;

    my $sql = qq{
        SELECT sr.name, sra.value
        FROM seq_region sr, coord_system cs, seq_region_attrib sra
        WHERE cs.name='$cs_name'
          AND sr.coord_system_id=cs.coord_system_id
          AND sr.seq_region_id=sra.seq_region_id
          AND sra.attrib_type_id = (SELECT attrib_type_id from attrib_type where code='$code')
          AND sra.value $condition
    };

    my $dbc      = $self->dbc();
    my $sth = $dbc->prepare($sql);
    $sth->execute();

    my $adaptor;
    while( my ($sr_name, $qname) = $sth->fetchrow() ) {
        $adaptor ||= $self->dba()->get_SliceAdaptor();

        my $slice = $adaptor->fetch_by_region($cs_name, $sr_name);

        $self->register_feature($qname, $qtype, $slice);
    }
}

sub find {
    my ($self, $unhide) = @_;

    $self->{_unhide} = $unhide;

    my $in_quoted_list = 'in ('. join(', ', map {"'$_'"} keys %{$self->qnames_locators()} ) .' ) ';

    $self->find_by_stable_ids();

    $self->find_by_seqregion_names($in_quoted_list);

    $self->find_by_feature_attributes($in_quoted_list, 'gene_name',
        'gene_attrib', 'gene_id', 'name', 'get_GeneAdaptor');

    $self->find_by_feature_attributes($in_quoted_list, 'gene_synonym',
        'gene_attrib', 'gene_id', 'synonym', 'get_GeneAdaptor');

    $self->find_by_feature_attributes($in_quoted_list, 'transcript_name',
        'transcript_attrib', 'transcript_id', 'name', 'get_TranscriptAdaptor');

    foreach my $qname (keys %{$self->qnames_locators()}) {

        $self->find_by_feature_attributes("like '%:$qname'", 'prefixed_gene_name',
            'gene_attrib', 'gene_id', 'name', 'get_GeneAdaptor');

        $self->find_by_feature_attributes("like '%:$qname'", 'prefixed_transcript_name',
            'transcript_attrib', 'transcript_id', 'name', 'get_TranscriptAdaptor');
    }

    $self->find_by_seqregion_attributes($in_quoted_list, 'international_clone_name', 'clone', 'intl_clone_name');

    $self->find_by_seqregion_attributes($in_quoted_list, 'clone_accession', 'clone', 'embl_acc');
}

sub generate_output {
    my ($self, $filter_atype) = @_;

    my $output_string = '';

    for my $qname (sort keys %{$self->qnames_locators()}) {
        my $count = 0;
        for my $loc (sort {$a->assembly cmp $b->assembly}
                        @{ $self->qnames_locators()->{$qname} }) {
            my $asm = $loc->assembly();
            if(!$filter_atype || ($filter_atype eq $asm)) {
                $output_string .= join("\t",
                    $loc->qname(), # take it from $loc to avoid case confusion
                    $loc->qtype(),
                    join(',', @{$loc->component_names()}),
                    $loc->assembly())."\n";
                $count++;
            }
        }
        if(!$count) {
            $output_string .= "$qname\n"; # no matches for this qname
        }
    }

    return $output_string;
}

1;

