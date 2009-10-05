package Bio::Otter::Lace::Slice;

use strict;
use warnings;

use Bio::EnsEMBL::Slice;

    # parsing is now performed by a table-driven parser:
use Bio::Otter::Lace::ViaText qw( %LangDesc &ParseFeatures );

    # parsing of genes is done separately:
use Bio::Otter::FromXML;

    # so we only parse the tiling path here:
use Bio::Otter::Lace::CloneSequence;

use Bio::Vega::Transform::Otter;


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
    
    # chromosome:Otter:chr6-17:2666323:2834369:1
    
    
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

    return sprintf "%s_%d-%d",
        $self->ssname,
        $self->start,
        $self->end;
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
        -seq_region_name    => $self->ssname,
        -start              => $self->start,
        -end                => $self->end,
        -coord_system   => Bio::EnsEMBL::CoordSystem->new(
            -name           => $self->csname,
            -version        => $self->csver,
            -rank           => 2,
            -sequence_level => 0,
            -default        => 1,
        ),
    );
    return $slice;
}

sub DataSet {
    my ($self) = @_;
    
    return $self->Client->get_DataSet_by_name($self->dsname);
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

sub get_region_xml {
    my $self = shift @_;

    my $client = $self->Client();

    if($client->debug()) {
        warn sprintf("Fetching data from chr %s %s-%s\n", $self->seqname(), $self->start(), $self->end() );
    }

    my $xml = $client->http_response_content( # should be unified with 'otter_response_content'
        'GET',
        'get_region',
        {
            %{$self->toHash},
            'email'     => $client->email,
            'trunc'     => $client->fetch_truncated_genes,
        },
    );

    if ($client->debug) {
        my $debug_file = Bio::Otter::Lace::PersistentFile->new();
        $debug_file->name("otter-debug.$$.fetch.xml");
        my $fh = $debug_file->write_file_handle();
        print $fh $xml;
        close $fh;
    }

    return $xml;
}

sub lock_region_xml {
    my $self = shift @_;

    my $client = $self->Client();

    return $client->http_response_content(
        'GET',
        'lock_region',
        {
            %{$self->toHash},
            'email'    => $client->email(),
            'hostname' => $client->client_hostname(),
        }
    );
}


sub get_all_features_hash { # get Simple|DnaAlign|ProteinAlign|Repeat|Marker|Ditag|PredictionTranscript features from otter|pipe|ensembl db

    # This returns features hashed by their actual Perl classes,
    # rather than the feature types used in $kind_and_args. This
    # supports dummy feature types (such as ExonSupportingFeature)
    # that return features whose class is not the same as the feature
    # type.

    my ($self, $kind_and_args, $metakey, $csver_remote) = @_;

    my @feature_kinds = map { $_->[0] } @$kind_and_args;

    my %arg_pairs = (
        %{$self->toHash},
        'kind' => join(',', @feature_kinds),
        $metakey      ? ('metakey'      => $metakey) : (),
        $csver_remote ? ('csver_remote' => $csver_remote) : (),
    ); # key-value pairs of mixed call parameters

    foreach my $ka_pair (@$kind_and_args) {
        my ($feature_kind, $call_arg_values) = @$ka_pair;
        my $call_arg_descs = $LangDesc{$feature_kind}{-call_args};

        for(my $i=0;$i<scalar(@$call_arg_descs);$i++) {
            my ($arg_name, $arg_def_value) = @{ $call_arg_descs->[$i] };
            my $arg_value = defined($call_arg_values->[$i]) ? $call_arg_values->[$i] : $arg_def_value;
            if($arg_value) {
                $arg_pairs{$arg_name} = $arg_value;
            }
        }
    }

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_features',
        \%arg_pairs,
    );

    my $all_features = ParseFeatures(\$response, $self->name(), $arg_pairs{'analysis'});

    return {
	map {
	    my $features = $all_features->{$_} || [];
	    $features = [ values %$features ] if ref($features) eq "HASH";
	    $_ => $features;
	} keys %$all_features,
    };
}


sub get_all_features { # get Simple|DnaAlign|ProteinAlign|Repeat|Marker|Ditag|PredictionTranscript features from otter|pipe|ensembl db
    my ($self, $kind_and_args, $metakey, $csver_remote) = @_;
    my @feature_kinds = map { $_->[0] } @$kind_and_args;
    my $all_features = $self->get_all_features_hash($kind_and_args, $metakey, $csver_remote);
    return @$all_features{@feature_kinds};
}

sub get_all_DAS_features { # get SimpleFeatures or PredictionExons from DAS source (via mapping Otter server)
    my( $self, $kind, $source, $dsn, $csver_remote, $analysis_name, $sieve, $grouplabel ) = @_;

    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_das_features',
        {
            %{$self->toHash},
            'kind'     => $kind,
            'metakey'  => '.', # let's pretend to be taking things from otter database
            $source         ? ('source'     => $source) : (),
            'dsn'      => $dsn,
            $csver_remote   ? ('csver_remote' => $csver_remote) : (), # if you forget it, the assembly will be Otter by default!
            $analysis_name  ? ('analysis'   => $analysis_name) : (),
            $sieve          ? ('sieve'      => $sieve) : (),
            $grouplabel     ? ('grouplabel' => $grouplabel) : (),
        },
    );

    # my $filter_kind = $kind eq 'SimpleFeature' ? 'SimpleFeature' : 'PredictionTranscript';
    return ParseFeatures(\$response, $self->name(), $analysis_name);
}

sub get_all_PipelineGenes { # get genes from otter/pipeline/ensembl db
    my( $self, $analysis_name, $metakey, $csver_remote, $transcript_analyses, $translation_xref_dbs ) = @_;

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

    my $response = $self->Client()->http_response_content(
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

    # my $slice = $self->create_detached_slice();
    # 
    # my $gene_parser = Bio::Otter::FromXML->new([ split(/\n/, $response) ], $slice);
    # return $gene_parser->build_Gene_array($slice);
    
    if ($response) {
        my $parser = Bio::Vega::Transform::Otter->new;
        $parser->set_ChromosomeSlice($self->create_detached_slice);
        $parser->parse($response);
        return $parser->get_Genes;
    } else {
        return [];
    }
}

1;

__END__


=head1 NAME - Bio::Otter::Lace::Slice

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk

