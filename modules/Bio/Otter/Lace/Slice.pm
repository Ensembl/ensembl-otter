package Bio::Otter::Lace::Slice;

use strict;
use warnings;

    # parsing is now performed by a table-driven parser:
use Bio::Otter::Lace::ViaText qw( %LangDesc &ParseFeatures );

    # parsing of genes is done separately:
use Bio::Otter::FromXML;

    # so we only parse the tiling path here:
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

sub get_all_features { # get Simple|DnaAlign|ProteinAlign|Repeat|Marker|Ditag|PredictionTranscript features from otter|pipe|ensembl db
    my $self            = shift @_;
    my $feature_kind    = shift @_;
    my $call_arg_values = \@_; # contains $metakey, $csver_remote and all call parameters

    my $analysis_name = '';
    my @args = (); # key-value pairs of call parameters in the order of the 'original' (B::E::Slice-based) call

    my $call_arg_descs = $LangDesc{$feature_kind}{-call_args};
    unshift @$call_arg_descs, ['metakey', ''], ['csver_remote', '']; # now is in sync with $call_arg_values

    for(my $i=0;$i<scalar(@$call_arg_descs);$i++) {
        my ($arg_name, $arg_def_value) = @{ $call_arg_descs->[$i] };
        my $arg_value = defined($call_arg_values->[$i]) ? $call_arg_values->[$i] : $arg_def_value;
        if(defined($arg_value)) {
            push @args, $arg_name => $arg_value;
            warn "pushing '$arg_name' and '$arg_value'\n";

            if($arg_name eq 'analysis') {
                $analysis_name = $arg_value;
            }
        }
    }

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_features',
        {
            %{$self->toHash},
            ('kind' => $feature_kind),
            @args,
        },
    );

    my $features = ParseFeatures(\$response, $self->name(), $analysis_name)->{$feature_kind};

    return ( ($LangDesc{$feature_kind}{-hash_by}||$LangDesc{$feature_kind}{-group_by})
        ? [values %$features ]
        : $features
    ) || [];
}

sub get_all_SimpleFeatures { # get simple features from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey, $csver_remote ) = @_;

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_simple_features',
        {
            %{$self->toHash},
            $analysis_name ? ('analysis' => $analysis_name) : (),
            $metakey ? ('metakey' => $metakey) : (),
            $csver_remote   ? ('csver_remote' => $csver_remote) : (), # if you forget it, the assembly will be Otter by default!
        },
    );

    return ParseFeatures(\$response, $self->name(), $analysis_name)->{SimpleFeature} || [];
}

sub get_all_DAS_SimpleFeatures { # get simple features from DAS source (via mapping Otter server)
    my( $self, $analysis_name, $source, $dsn, $csver_remote ) = @_;

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

    return ParseFeatures(\$response, $self->name(), $analysis_name)->{SimpleFeature} || [];
}

sub get_all_Cons_SimpleFeatures { # get simple features from Compara 'GERP_CONSERVATION_SCORE'
    my( $self, $analysis_name, $metakey, $csver_remote ) = @_;

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
            $csver_remote   ? ('csver_remote' => $csver_remote) : (), # if you forget it, the assembly will be Otter by default!
        },
    );

    return ParseFeatures(\$response, $self->name(), $analysis_name)->{SimpleFeature} || [];
}

sub get_all_DnaAlignFeatures { # get dna align features from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey, $csver_remote ) = @_;

    return $self->get_all_AlignFeatures( 'dafs', $analysis_name, $metakey, $csver_remote );
}

sub get_all_ProteinAlignFeatures { # get protein align features from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey, $csver_remote ) = @_;

    return $self->get_all_AlignFeatures( 'pafs', $analysis_name, $metakey, $csver_remote );
}

sub get_all_AlignFeatures { # get align features from otter/pipeline/ensembl db
    my( $self, $kind, $analysis_name, $metakey, $csver_remote ) = @_;

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_align_features',
        {
            %{$self->toHash},
            'kind'     => $kind,
            $analysis_name ? ('analysis' => $analysis_name) : (),
            $metakey ? ('metakey' => $metakey) : (),
            $csver_remote   ? ('csver_remote' => $csver_remote) : (), # if you forget it, the assembly will be Otter by default!
        },
    );

    return ParseFeatures(\$response, $self->name(), $analysis_name)->{ $kind eq 'dafs' ? 'DnaDnaAlignFeature' : 'DnaPepAlignFeature'} || [];
}

sub get_all_RepeatFeatures { # get repeat features from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey, $csver_remote ) = @_;

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_repeat_features',
        {
            %{$self->toHash},
            $analysis_name ? ('analysis' => $analysis_name) : (),
            $metakey ? ('metakey' => $metakey) : (),
            $csver_remote   ? ('csver_remote' => $csver_remote) : (), # if you forget it, the assembly will be Otter by default!
        },
    );

    return ParseFeatures(\$response, $self->name(), $analysis_name)->{RepeatFeature} || [];
}

sub get_all_MarkerFeatures { # get marker features from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey, $csver_remote ) = @_;

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_marker_features',
        {
            %{$self->toHash},
            $analysis_name ? ('analysis' => $analysis_name) : (),
            $metakey ? ('metakey' => $metakey) : (),
            $csver_remote   ? ('csver_remote' => $csver_remote) : (), # if you forget it, the assembly will be Otter by default!
        },
    );

    return ParseFeatures(\$response, $self->name(), $analysis_name)->{MarkerFeature} || [];
}

    #
    # the returned list is 2d, with features grouped by ditag_id.ditag_pair_id
    # (even if there was only one feature per group)
    #
sub get_all_DitagFeatureGroups { # get ditag features from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey, $csver_remote, $ditypes ) = @_;

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_ditag_features',
        {
            %{$self->toHash},
            $analysis_name ? ('analysis' => $analysis_name) : (),
            $metakey ? ('metakey' => $metakey) : (),
            $csver_remote   ? ('csver_remote' => $csver_remote) : (), # if you forget it, the assembly will be Otter by default!
            $ditypes ? ('ditypes' => $ditypes) : (),
        },
    );

    my $ditag_subhash = ParseFeatures(\$response, $self->name(), $analysis_name)->{DitagFeature};

    return $ditag_subhash ? [ values %$ditag_subhash ] : [];
}

sub get_all_PredictionTranscripts { # get prediction transcripts from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey, $csver_remote ) = @_;

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_prediction_transcripts',
        {
            %{$self->toHash},
            $analysis_name ? ('analysis' => $analysis_name) : (),
            $metakey ? ('metakey' => $metakey) : (),
            $csver_remote   ? ('csver_remote' => $csver_remote) : (), # if you forget it, the assembly will be Otter by default!
        },
    );

    my $pt_subhash = ParseFeatures(\$response, $self->name(), $analysis_name)->{PredictionTranscript};

    return $pt_subhash ? [ values %$pt_subhash ] : [];
}

sub get_all_DAS_PredictionTranscripts { # get simple features from DAS source (via mapping Otter server)
    my( $self, $analysis_name, $source, $dsn, $csver_remote ) = @_;

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

    my $pt_subhash = ParseFeatures(\$response, $self->name(), $analysis_name)->{PredictionTranscript};

    return $pt_subhash ? [ values %$pt_subhash ] : [];
}

sub get_all_PipelineGenes { # get genes from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey, $csver_remote, $transcript_analyses, $translation_xref_dbs ) = @_;

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
            $csver_remote   ? ('csver_remote' => $csver_remote) : (), # if you forget it, the assembly will be Otter by default!
            $transcript_analyses ? ('transcript_analyses' => $transcript_analyses) : (),
            $translation_xref_dbs ? ('translation_xref_dbs' => $translation_xref_dbs) : (),
        },
    );

    my $slice = $self->create_detached_slice();

    my $gene_parser = Bio::Otter::FromXML->new([ split(/\n/, $response) ], $slice);
    return $gene_parser->build_Gene_array($slice);
}

sub get_all_Genes { # currently unused by ensembl-ace, but is retained for interface-compatibility with Slice
    my( $self, $analysis_name ) = @_;

    $analysis_name ||= 'otter';

    return $self->get_all_PipelineGenes($analysis_name, '.');
}

1;

__END__


=head1 NAME - Bio::Otter::Lace::Slice

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk

