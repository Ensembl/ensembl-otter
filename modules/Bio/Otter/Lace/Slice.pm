package Bio::Otter::Lace::Slice;

use strict;
use warnings;

    # all the parsing is now performed by a separate module ...
use Bio::Otter::Lace::ViaText::FromText qw( &ParseSimpleFeatures &ParseAlignFeatures &ParseRepeatFeatures
                                            &ParseMarkerFeatures &ParseDitagFeatureGroups
                                            &ParsePredictionTranscripts &ParseGenes );

    # ... apart from parsing the tiling path
use Bio::Otter::Lace::CloneSequence;

sub new {
    my( $pkg,
        $Client, # object
        $dsname, # e.g. 'human'
        $ssname, # e.g. 'chr20-03'

        $csname, # e.g. 'chromosome'
        $csver,  # e.g. 'Otter'
        $seqname,# e.g. '20'
        $start,  # in the given coordinate system
        $end,    # in the given coordinate system
    ) = @_;
    
    return bless {
        '_Client'   => $Client,
        '_dsname'   => $dsname,
        '_ssname'   => $ssname,

        '_csname'   => $csname,
        '_csver'    => $csver  || '',
        '_seqname'  => $seqname,
        '_start'    => $start,
        '_end'      => $end,
    }, $pkg;
}

sub Client {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change Client" if defined($dummy);

    return $self->{_Client};
}

sub dsname {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change dsname" if defined($dummy);

    return $self->{_dsname};
}

sub ssname {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change ssname" if defined($dummy);

    return $self->{_ssname};
}


sub csname {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change csname" if defined($dummy);

    return $self->{_csname};
}

sub csver {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change csver" if defined($dummy);

    return $self->{_csver};
}

sub seqname {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change seqname" if defined($dummy);

    return $self->{_seqname};
}

sub start {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change start" if defined($dummy);

    return $self->{_start};
}

sub end {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change end" if defined($dummy);

    return $self->{_end};
}

sub length {
    my ( $self ) = @_;

    return $self->end() - $self->start() + 1;
}

sub name {
    my( $self ) = @_;
    return $self->seqname().'.'.$self->start().'-'.$self->end();
}


sub toHash {
    my $self = shift @_;

    return {
            'dataset' => $self->dsname(),
            'type'    => $self->ssname(),

            'cs'      => $self->csname(),
            'csver'   => $self->csver(),
            'name'    => $self->seqname(),
            'start'   => $self->start(),
            'end'     => $self->end(),
    };
}

sub create_detached_slice {
    my $self = shift @_;

    my $slice = Bio::EnsEMBL::Slice->new(
        -chr_name      => $self->seqname(),
        -chr_start     => $self->start(),
        -chr_end       => $self->end(),
        -assembly_type => $self->ssname(),
    );
    return $slice;
}

# ----------------------------------------------------------------------------------

sub get_tiling_path_and_sequence {
    my ( $self, $dna_wanted ) = @_;

    $dna_wanted = $dna_wanted ? 1 : 0; # make it defined

            # is it cached and there's enough DNA?
    if( $self->{_tiling_path}
    && ($self->{_tiling_path_dna} >= $dna_wanted) ) {
        return $self->{_tiling_path};
    }

    # else:

    $self->{_tiling_path} = [];
    $self->{_tiling_path_dna} = $dna_wanted;

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_tiling_and_seq',
        {
            %{$self->toHash},
            'dnawanted' => $dna_wanted,
            'metakey'   => '.',             # get the slice from Otter_db
            #
            # If you want to get the tiling_path from Pipe_db,
            # omit the 'metakey' altogether (it will be set to '' on the server side)
            #
        },
    );
    foreach my $respline ( split(/\n/,$response) ) {
        my ($embl_accession, $embl_version, $intl_clone_name, $contig_name,
            $chr_name, $asm_type, $asm_start, $asm_end,
            $cmp_start, $cmp_end, $cmp_ori, $cmp_length,
            $dna
        ) = split(/\t/, $respline);

        my $cs = Bio::Otter::Lace::CloneSequence->new();
        $cs->accession($embl_accession);    # e.g. 'AL161656'
        $cs->sv($embl_version);             # e.g. '19'
        $cs->clone_name($intl_clone_name);  # e.g. 'RP11-12M19'
        $cs->contig_name($contig_name);     # e.g. 'AL161656.19.1.103370'

        $cs->chromosome($chr_name);         # e.g. '20'
        $cs->assembly_type($asm_type);      # e.g. 'chr20-03'
        $cs->chr_start($asm_start);         # FORMALLY INCORRECT, as slice_coords!=chromosomal_coords
        $cs->chr_end($asm_end);             # but we shall temporarily keep superslice coords here.

        $cs->contig_start($cmp_start);
        $cs->contig_end($cmp_end);
        $cs->contig_strand($cmp_ori);
        $cs->length($cmp_length);

        if($dna_wanted) {
            $cs->sequence($dna);
        }

        push @{ $self->{_tiling_path} }, $cs;
    }

    return $self->{_tiling_path};
}

sub get_all_tiles_as_Slices {
    my ( $self, $dna_wanted ) = @_;

    my @subslices = ();

    my $tiles = $self->get_tiling_path_and_sequence($dna_wanted);
    for my $cs (@$tiles) {
        my $newslice = ref($self)->new(
            $self->Client(), $self->dsname(), $self->ssname(),
            'contig', '', $cs->contig_name(),
            1, $cs->length(), # assume we are interested in WHOLE contigs
        );
        push @subslices, $newslice;
    }
    return \@subslices;
}

sub get_all_SimpleFeatures { # get simple features from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey ) = @_;

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_simple_features',
        {
            %{$self->toHash},
            $analysis_name ? ('analysis' => $analysis_name) : (),
            $metakey ? ('metakey' => $metakey) : (),
        },
    );

    return ParseSimpleFeatures(\$response, $self->name(), $analysis_name);
}

sub get_all_DAS_SimpleFeatures { # get simple features from DAS source (via mapping Otter server)
    my( $self, $analysis_name, $csver_remote, $source, $dsn ) = @_;

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_das_simple_features',
        {
            %{$self->toHash},
            'analysis' => $analysis_name,
            'metakey'  => '.', # let's pretend to be taking things from otter database
            $csver_remote   ? ('csver_remote' => $csver_remote) : (), # if you forget it, the assembly will be Otter by default!
            'source'   => $source,
            'dsn'      => $dsn,
        },
    );

    return ParseSimpleFeatures(\$response, $self->name(), $analysis_name);
}

sub get_all_Cons_SimpleFeatures { # get simple features from Compara 'GERP_CONSERVATION_SCORE'
    my( $self, $analysis_name, $metakey ) = @_;

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_cons_simple_features',
        {
            %{$self->toHash},
            'analysis' => $analysis_name,
            $metakey   ? ('metakey' => $metakey) : (), # if you forget it, it will be 'Otter' by default!
        },
    );

    return ParseSimpleFeatures(\$response, $self->name(), $analysis_name);
}

sub get_all_DnaAlignFeatures { # get dna align features from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey ) = @_;

    return $self->get_all_AlignFeatures( 'dafs', $analysis_name, $metakey );
}

sub get_all_ProteinAlignFeatures { # get protein align features from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey ) = @_;

    return $self->get_all_AlignFeatures( 'pafs', $analysis_name, $metakey );
}

sub get_all_AlignFeatures { # get align features from otter/pipeline/ensembl db
    my( $self, $kind, $analysis_name, $metakey ) = @_;

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_align_features',
        {
            %{$self->toHash},
            'kind'     => $kind,
            $analysis_name ? ('analysis' => $analysis_name) : (),
            $metakey ? ('metakey' => $metakey) : (),
        },
    );

    return ParseAlignFeatures(\$response, $kind, $self->name(), $analysis_name);
}

sub get_all_RepeatFeatures { # get repeat features from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey ) = @_;

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_repeat_features',
        {
            %{$self->toHash},
            $analysis_name ? ('analysis' => $analysis_name) : (),
            $metakey ? ('metakey' => $metakey) : (),
        },
    );

    return ParseRepeatFeatures(\$response, $analysis_name);
}

sub get_all_MarkerFeatures { # get marker features from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey ) = @_;

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_marker_features',
        {
            %{$self->toHash},
            $analysis_name ? ('analysis' => $analysis_name) : (),
            $metakey ? ('metakey' => $metakey) : (),
        },
    );

    return ParseMarkerFeatures(\$response, $analysis_name);
}

    #
    # the returned list is 2d, with features grouped by ditag_id.ditag_pair_id
    # (even if there was only one feature per group)
    #
sub get_all_DitagFeatureGroups { # get ditag features from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey, $ditypes ) = @_;

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_ditag_features',
        {
            %{$self->toHash},
            $analysis_name ? ('analysis' => $analysis_name) : (),
            $metakey ? ('metakey' => $metakey) : (),
            $ditypes ? ('ditypes' => $ditypes) : (),
        },
    );

    return ParseDitagFeatureGroups(\$response, $analysis_name);
}

sub get_all_PredictionTranscripts { # get prediction transcripts from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey ) = @_;

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_prediction_transcripts',
        {
            %{$self->toHash},
            $analysis_name ? ('analysis' => $analysis_name) : (),
            $metakey ? ('metakey' => $metakey) : (),
        },
    );

    return ParsePredictionTranscripts(\$response, $analysis_name);
}

sub get_all_DAS_PredictionTranscripts { # get simple features from DAS source (via mapping Otter server)
    my( $self, $analysis_name, $csver_remote, $source, $dsn ) = @_;

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_das_prediction_transcripts',
        {
            %{$self->toHash},
            'analysis' => $analysis_name,
            'metakey'  => '.', # let's pretend to be taking things from otter database
            $csver_remote   ? ('csver_remote' => $csver_remote) : (), # if you forget it, the assembly will be Otter by default!
            'source'   => $source,
            'dsn'      => $dsn,
        },
    );

    return ParsePredictionTranscripts(\$response, $analysis_name);
}

sub get_all_PipelineGenes { # get genes from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey, $transcript_analyses, $translation_xref_dbs ) = @_;

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_genes',
        {
            %{$self->toHash},
            'analysis' => $analysis_name,
            $metakey ? ('metakey' => $metakey) : (),
            $transcript_analyses ? ('transcript_analyses' => $transcript_analyses) : (),
            $translation_xref_dbs ? ('translation_xref_dbs' => $translation_xref_dbs) : (),
        },
    );

    my $slice = $self->create_detached_slice();

    return ParseGenes(\$response, $slice);
}

sub get_all_Genes { # non-default :)
    my( $self, $analysis_name ) = @_;

    $analysis_name ||= 'otter';

    return $self->get_all_PipelineGenes($analysis_name, 1, '.');
}

1;

__END__


=head1 NAME - Bio::Otter::Lace::Slice

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk

