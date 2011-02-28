package Bio::Otter::Lace::Slice;

use strict;
use warnings;

use Bio::EnsEMBL::Slice;

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


    my $self = {
        '_Client'   => $Client,
        '_dsname'   => $dsname,
        '_ssname'   => $ssname,

        '_csname'   => $csname,
        '_csver'    => $csver  || '',
        '_seqname'  => $seqname,
        '_start'    => $start,
        '_end'      => $end,
    }; 

    return bless $self, $pkg;
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

sub length { ## no critic(Subroutines::ProhibitBuiltinHomonyms)
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
    my ($self) = @_;

    my $hash = {
            'dataset' => $self->dsname(),
            'type'    => $self->ssname(),

            'cs'      => $self->csname(),
            'csver'   => $self->csver(),
            'name'    => $self->seqname(),
            'start'   => $self->start(),
            'end'     => $self->end(),
    };

    return $hash;
}

sub create_detached_slice {
    my ($self) = @_;

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


sub get_assembly_dna {
    my ($self) = @_;
    
    my $response = $self->Client()->otter_response_content(
        'GET',
        'get_assembly_dna',
        {
            %{$self->toHash},
            'metakey'   => '.',             # get the slice from Otter_db
        },
    );
    
    my ($seq, @tiles) = split /\n/, $response;
    for (my $i = 0; $i < @tiles; $i++) {
        my ($start, $end, $ctg_name, $ctg_start, $ctg_end, $ctg_strand, $ctg_length) = split /\t/, $tiles[$i];
        $tiles[$i] = {
            start       => $start,
            end         => $end,
            ctg_name    => $ctg_name,
            ctg_start   => $ctg_start,
            ctg_end     => $ctg_end,
            ctg_strand  => $ctg_strand,
            ctg_length  => $ctg_length,
        };
    }
    return (lc $seq, @tiles);
}


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
    my %contig_dna;

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

        if($dna) { $contig_dna{$contig_name} = $dna; }

        if($dna_wanted) {
            $cs->sequence($contig_dna{$contig_name});
        }

        push @{ $self->{_tiling_path} }, $cs;
    }

    return $self->{_tiling_path};
}

sub get_all_tiles_as_Slices {
    my ( $self, $dna_wanted ) = @_;

    my $subslices = [];

    my $tiles = $self->get_tiling_path_and_sequence($dna_wanted);
    my %seen_contig;
    for my $cs (@$tiles) {
        my $ctg_name = $cs->contig_name();

        # To prevent fetching of contig data more than once where
        # a contig appears multiple times in the assembly.
        next if $seen_contig{$ctg_name};
        $seen_contig{$ctg_name} = 1;

        my $newslice = ref($self)->new(
            $self->Client(), $self->dsname(), $self->ssname(),
            'contig', '', $ctg_name,
            1, $cs->length(), # assume we are interested in WHOLE contigs
        );
        push @$subslices, $newslice;
    }
    return $subslices;
}

sub get_region_xml {
    my ($self) = @_;

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
        my $debug_file = "/var/tmp/otter-debug.$$.fetch.xml";
        if (open my $fh, '>', $debug_file) {
            print $fh $xml;
            unless (close $fh) {
                warn "get_region_xml(): failed to close the debug file '${debug_file}'\n";
            }
        }
        else {
            warn "get_region_xml(): failed to open the debug file '${debug_file}'\n";
        }
    }

    return $xml;
}

sub lock_region_xml {
    my ($self) = @_;

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

sub dna_ace_data {
    my ($self) = @_;

    my $name = $self->name;

    my ($dna_str, @t_path) = $self->get_assembly_dna;

    my $ace_output = qq{\nSequence "$name"\n};

    foreach my $tile (@t_path) {
        my $start   = $tile->{'start'};
        my $end     = $tile->{'end'};
        my $strand  = $tile->{'ctg_strand'};
        if ($strand == -1) {
            ($start, $end) = ($end, $start);
        }
        $ace_output .= sprintf qq{Feature "Genomic_canonical" %d %d %f "%s-%d-%d-%s"\n},
            $start,
            $end,
            1.000,
            $tile->{'ctg_name'},
            $tile->{'ctg_start'},
            $tile->{'ctg_end'},
            $tile->{'ctg_strand'} == -1 ? 'minus' : 'plus';
    }
    
    my %seen_ctg;
    foreach my $tile (@t_path) {
        my $ctg_name = $tile->{'ctg_name'};
        next if $seen_ctg{$ctg_name};
        $seen_ctg{$ctg_name} = 1;
        $ace_output .= sprintf qq{\nSequence "%s"\nLength %d\n},
            $tile->{'ctg_name'},
            $tile->{'ctg_length'};
    }
    
    $ace_output .= qq{\nSequence : "$name"\n}
                 # . qq{Genomic_canonical\n}
                 # . qq{Method Genomic_canonical\n}
                 . qq{DNA "$name"\n}
                 . qq{\nDNA : "$name"\n};

    while ($dna_str =~ /(.{1,60})/g) {
        $ace_output .= "$1\n";
    }
    
    return $ace_output;
}

1;

__END__


=head1 NAME - Bio::Otter::Lace::Slice

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk

