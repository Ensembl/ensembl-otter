package Bio::Otter::Lace::Slice;

use strict;
use Carp qw{ confess cluck };

use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DnaDnaAlignFeature;
use Bio::EnsEMBL::DnaPepAlignFeature;
use Bio::EnsEMBL::PredictionTranscript;
use Bio::EnsEMBL::RepeatConsensus;
use Bio::EnsEMBL::RepeatFeature;
use Bio::EnsEMBL::SimpleFeature;
use Bio::EnsEMBL::Map::MarkerSynonym;
use Bio::EnsEMBL::Map::Marker;
use Bio::EnsEMBL::Map::MarkerFeature;

use Bio::Otter::Author;
use Bio::Otter::DnaDnaAlignFeature;
use Bio::Otter::DnaPepAlignFeature;
use Bio::Otter::FromXML;
use Bio::Otter::HitDescription;
use Bio::Otter::Lace::DataSet;
use Bio::Otter::Lace::ViaText ('%OrderOfOptions');

sub new {
    my( $pkg, $chr_name, $chr_start, $chr_end, $asm_type ) = @_;
    
    return bless {
        '_chr_name'  => $chr_name,
        '_chr_start' => $chr_start,
        '_chr_end'   => $chr_end,
        '_asm_type'  => $asm_type,
    }, $pkg;
}

sub chr_name {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change chr_name" if defined($dummy);

    return $self->{_chr_name};
}

sub chr_start {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change chr_name" if defined($dummy);

    return $self->{_chr_start};
}

sub chr_end {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change chr_end" if defined($dummy);

    return $self->{_chr_end};
}

sub assembly_type {
    my( $self, $dummy ) = @_;

    die "You shouldn't need to change assembly_type" if defined($dummy);

    return $self->{_asm_type};
}

sub name {
    my( $self ) = @_;
    return $self->chr_name().'.'.$self->chr_start().'-'.$self->chr_end();
}


sub Client {
    my( $self, $client ) = @_;
    if ($client) {
        $self->{_Client} = $client;
    }
    return $self->{_Client};
}

sub DataSet_name {
    my( $self, $dsname ) = @_;
    if ($dsname) {
        $self->{_dsname} = $dsname;
    }
    return $self->{_dsname};
}

sub toHash {
    my $self = shift @_;

    return {
            'dataset' => $self->DataSet_name(),
            'cs'      => 'chromosome',
            'csver'   => 'Otter',
            'name'    => $self->chr_name(),
            'start'   => $self->chr_start(),
            'end'     => $self->chr_end(),
            'type'    => $self->assembly_type(),
    };
}

sub create_detached_slice {
    my $self = shift @_;

    my $slice = Bio::EnsEMBL::Slice->new(
        -chr_name      => $self->chr_name(),
        -chr_start     => $self->chr_start(),
        -chr_end       => $self->chr_end(),
        -assembly_type => $self->assembly_type(),
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

    my $response = $self->Client()->general_http_dialog(
        0,
        'GET',
        'get_tiling_and_seq',
        {
            %{$self->toHash},
            'dnawanted' => $dna_wanted,
            'pipehead'  => 0, # not to confuse the current server script
        },
        1,
    );
    foreach my $respline ( split(/\n/,$response) ) {
        my ($clone_name, $contig_name,
            $asm_start, $asm_end,
            $cmp_start, $cmp_end, $cmp_ori, $cmp_length,
            $dna
        ) = split(/\t/, $respline);

            # cannot use "real Tile"s while in schema transition period
        my %tile = (
            'clone_name'  => $clone_name,
            'contig_name' => $contig_name,
            'asm_start'   => $asm_start,
            'asm_end'     => $asm_end,
            'cmp_start'   => $cmp_start,
            'cmp_end'     => $cmp_end,
            'cmp_ori'     => $cmp_ori,
            'cmp_length'  => $cmp_length,
            $dna_wanted ? ('dna' => $dna) : (),
        );

        push @{ $self->{_tiling_path} }, \%tile;
    }

    return $self->{_tiling_path};
}

sub get_all_SimpleFeatures {
    my( $self, $analysis_name, $pipehead ) = @_;

        # cached values:
    my $analysis = Bio::EnsEMBL::Analysis->new( -logic_name => $analysis_name );

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

    my $response = $self->Client()->general_http_dialog(
        0,
        'GET',
        'get_simple_features',
        {
            %{$self->toHash},
            'analysis' => $analysis_name,
            'pipehead' => $pipehead ? 1 : 0,
        },
        1,
    );

    my @resplines = split(/\n/,$response);

    my @sf_optnames = @{ $OrderOfOptions{SimpleFeature} };

    my @sfs = (); # simple features in a list
    foreach my $respline (@resplines) {

        my @optvalues = split(/\t/,$respline);
        my $linetype      = shift @optvalues; # 'SimpleFeature'

        my $sf = Bio::EnsEMBL::SimpleFeature->new();

        for my $ind (0..@sf_optnames-1) {
            my $method = $sf_optnames[$ind];
            $sf->$method($optvalues[$ind]);
        }

            # use the cached values:
        $sf->analysis( $analysis );
        $sf->seqname( $self->name() );

        push @sfs, $sf;
    }

    return \@sfs;
}

sub get_all_DnaAlignFeatures {
    my( $self, $analysis_name, $pipehead ) = @_;

    return $self->get_all_AlignFeatures(
        'dafs', $analysis_name, $pipehead
    );
}

sub get_all_ProteinAlignFeatures {
    my( $self, $analysis_name, $pipehead ) = @_;

    return $self->get_all_AlignFeatures(
        'pafs', $analysis_name, $pipehead
    );
}

sub get_all_AlignFeatures {
    my( $self, $kind, $analysis_name, $pipehead ) = @_;

    my %analyses = (); # keep cached analysis objects here

    my ($baseclass, $subclass) = @{ {
        'dafs' => [ qw(Bio::EnsEMBL::DnaDnaAlignFeature Bio::Otter::DnaDnaAlignFeature) ],
        'pafs' => [ qw(Bio::EnsEMBL::DnaPepAlignFeature Bio::Otter::DnaPepAlignFeature) ],
    }->{$kind} };
    
    my $response = $self->Client()->general_http_dialog(
        0,
        'GET',
        'get_align_features',
        {
            %{$self->toHash},
            'kind'     => $kind,
            $analysis_name ? ('analysis' => $analysis_name) : (),
            'pipehead' => $pipehead ? 1 : 0,
        },
        1,
    );

    my @resplines = split(/\n/,$response);

    my @af_optnames = @{ $OrderOfOptions{AlignFeature} };
    my @hd_optnames = @{ $OrderOfOptions{HitDescription} };

    my %hds = (); # cached hit descriptions, keyed by hit_name
    my @afs = (); # align features in a list
    foreach my $respline (@resplines) {

        my @optvalues = split(/\t/,$respline);
        my $linetype  = shift @optvalues; # 'AlignFeature' || 'HitDescription'

        if($linetype eq 'HitDescription') {

            my $hit_name = shift @optvalues;
            my $hd = Bio::Otter::HitDescription->new();
            for my $ind (0..@hd_optnames-1) {
                my $method = $hd_optnames[$ind];
                $hd->$method($optvalues[$ind]);
            }
            $hds{$hit_name} = $hd;

        } elsif($linetype eq 'AlignFeature') {
            my $logic_name    = pop @optvalues;
            my $cigar_string  = pop @optvalues;

            my $af = $baseclass->new(
                    -cigar_string => $cigar_string
            );

            for my $ind (0..@af_optnames-1) {
                my $method = $af_optnames[$ind];
                $af->$method($optvalues[$ind]);
            }

                # cache if needed, otherwise use the cached value:
            $af->analysis(
                $analyses{$logic_name} ||= Bio::EnsEMBL::Analysis->new(-logic_name => $logic_name)
            );

                # use the cached value:
            $af->seqname( $self->name() );

                # Now add the HitDescriptions to Bio::EnsEMBL::DnaXxxAlignFeatures
                # and re-bless them into Bio::Otter::DnaXxxAlignFeatures,
                # IF the HitDescription is available
            my $hit_name = $af->hseqname();
            if(my $hd = $hds{$hit_name}) {
                bless $af, $subclass;
                $af->{'_hit_description'} = $hd;
            } else {
                # warn "No HitDescription for '$hit_name'";
            }

            push @afs, $af;
        }
    }

    return \@afs;
}

sub get_all_RepeatFeatures {
    my( $self, $analysis_name, $pipehead ) = @_;

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

    my $response = $self->Client()->general_http_dialog(
        0,
        'GET',
        'get_repeat_features',
        {
            %{$self->toHash},
            'analysis' => $analysis_name,
            'pipehead' => $pipehead ? 1 : 0,
        },
        1,
    );

    my @resplines = split(/\n/,$response);

    my @rf_optnames = @{ $OrderOfOptions{RepeatFeature} };
    my @rc_optnames = @{ $OrderOfOptions{RepeatConsensus} };

        # cached values:
    my $analysis = Bio::EnsEMBL::Analysis->new( -logic_name => $analysis_name );

    my %rcs = (); # cached repeat consensi, keyed by rc_id
    my @rfs = (); # repeat features in a list
    foreach my $respline (@resplines) {

        my @optvalues = split(/\t/,$respline);
        my $linetype      = shift @optvalues; # 'RepeatFeature' || 'RepeatConsensus'

        if($linetype eq 'RepeatConsensus') {

            my $rc_id = pop @optvalues;

            my $rc = Bio::EnsEMBL::RepeatConsensus->new();
            for my $ind (0..@rc_optnames-1) {
                my $method = $rc_optnames[$ind];
                $rc->$method($optvalues[$ind]);
            }
            $rcs{$rc_id} = $rc;

        } elsif($linetype eq 'RepeatFeature') {

            my $rc_id = pop @optvalues;

            my $rf = Bio::EnsEMBL::RepeatFeature->new();

            for my $ind (0..@rf_optnames-1) {
                my $method = $rf_optnames[$ind];
                $rf->$method($optvalues[$ind]);
            }

                # use the cached values:
            $rf->analysis( $analysis );
            $rf->repeat_consensus( $rcs{$rc_id} );

            push @rfs, $rf;
        }
    }

    return \@rfs;
}

sub get_all_MarkerFeatures {
    my( $self, $analysis_name, $pipehead ) = @_;

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

    my $response = $self->Client()->general_http_dialog(
        0,
        'GET',
        'get_marker_features',
        {
            %{$self->toHash},
            'analysis' => $analysis_name,
            'pipehead' => $pipehead ? 1 : 0,
        },
        1,
    );

    my @resplines = split(/\n/,$response);

    my @mf_optnames = @{ $OrderOfOptions{MarkerFeature} };
    my @mo_optnames = @{ $OrderOfOptions{MarkerObject} };
    my @ms_optnames = @{ $OrderOfOptions{MarkerSynonym} };

        # cached values:
    my $analysis = Bio::EnsEMBL::Analysis->new( -logic_name => $analysis_name );

    my %mos  = (); # cached marker objects, keyed by mo_id
    my @mfs  = (); # marker features in a list
    foreach my $respline (@resplines) {

        my @optvalues = split(/\t/,$respline);
        my $linetype  = shift @optvalues; # 'MarkerFeature' || 'MarkerObject' || 'MarkerSynonym'

        if($linetype eq 'MarkerObject') {

            my $mo_id = pop @optvalues;

            my $mo = Bio::EnsEMBL::Map::Marker->new();
            for my $ind (0..@mo_optnames-1) {
                my $method = $mo_optnames[$ind];
                $mo->$method($optvalues[$ind]);
            }
            $mos{mo_id} = $mo;

        } elsif($linetype eq 'MarkerSynonym') {

            my $mo_id = pop @optvalues;
            my $mo = $mos{mo_id}; # should have been defined earlier!

            my $ms = Bio::EnsEMBL::Map::MarkerSynonym->new();
            for my $ind (0..@ms_optnames-1) {
                my $method = $ms_optnames[$ind];
                $ms->$method($optvalues[$ind]);
            }
            $mo->add_MarkerSynonyms($ms);

        } elsif($linetype eq 'MarkerFeature') {

            my $mo_id = pop @optvalues;
            my $mo = $mos{mo_id}; # should have been defined earlier!

            my $mf = Bio::EnsEMBL::Map::MarkerFeature->new();

            for my $ind (0..@mf_optnames-1) {
                my $method = $mf_optnames[$ind];
                $mf->$method($optvalues[$ind]);
            }
            $mf->marker( $mo );
            $mf->_marker_id( $mo_id );

                # use the cached values:
            $mf->analysis( $analysis );
            $mf->strand( 0 );

            push @mfs, $mf;
        }
    }

    return \@mfs;
}

sub get_all_PredictionTranscripts {
    my( $self, $analysis_name, $pipehead ) = @_;

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

    my $response = $self->Client()->general_http_dialog(
        0,
        'GET',
        'get_prediction_transcripts',
        {
            %{$self->toHash},
            'analysis' => $analysis_name,
            'pipehead' => $pipehead ? 1 : 0,
        },
        1,
    );

    my @resplines = split(/\n/,$response);

    my @pt_optnames = @{ $OrderOfOptions{PredictionTranscript} };
    my @pe_optnames = @{ $OrderOfOptions{PredictionExon} };

        # cached values:
    my $analysis = Bio::EnsEMBL::Analysis->new( -logic_name => $analysis_name );

    my @pts = (); # prediction transcripts in a list
    my $curr_pt;
    my $curr_ptid;
    foreach my $respline (@resplines) {

        my @optvalues = split(/\t/,$respline);
        my $linetype      = shift @optvalues; # 'PredictionTranscript' || 'PredictionExon'

        if($linetype eq 'PredictionTranscript') {

            my $pt = Bio::EnsEMBL::PredictionTranscript->new();
            for my $ind (0..@pt_optnames-1) {
                my $method = $pt_optnames[$ind];
                $pt->$method($optvalues[$ind]);
            }
            $pt->analysis( $analysis );

            $curr_pt = $pt;
            $curr_ptid = $pt->dbID();

            push @pts, $pt;

        } elsif($linetype eq 'PredictionExon') {

            my $pt_id = pop @optvalues;

            my $pe = Bio::EnsEMBL::Exon->new(); # there is no PredictionExon in v.19 code!

            for my $ind (0..@pe_optnames-1) {
                my $method = $pe_optnames[$ind];
                $pe->$method($optvalues[$ind]);
            }

                # use the cached values:
            $pe->analysis( $analysis );

            if($pt_id == $curr_ptid) {
                $curr_pt->add_Exon( $pe );
            } else {
                die "Wrong order of exons in the stream!";
            }
        }
    }

    return \@pts;
}

sub get_all_PipelineGenes { # get genes from pipeline db - e.g. HalfWise genes
    my( $self, $analysis_name, $pipehead ) = @_;

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

    my $response = $self->Client()->general_http_dialog(
        0,
        'GET',
        'get_pipeline_genes',
        {
            %{$self->toHash},
            'analysis' => $analysis_name,
            'pipehead' => $pipehead ? 1 : 0,
        },
        1,
    );
    my $slice = $self->create_detached_slice();

    my @resplines = split(/\n/,$response);

    my $gene_parser = Bio::Otter::FromXML->new([ split(/\n/,$response) ], $slice);
    my $genes = $gene_parser->build_Gene_array($slice);

    return $genes;
}

1;

