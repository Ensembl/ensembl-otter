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
use Bio::EnsEMBL::Map::Ditag;
use Bio::EnsEMBL::Map::DitagFeature;

use Bio::Otter::DnaDnaAlignFeature;
use Bio::Otter::DnaPepAlignFeature;
use Bio::Otter::FromXML;
use Bio::Otter::HitDescription;
use Bio::Otter::Lace::CloneSequence;
use Bio::Otter::Lace::ViaText ('%OrderOfOptions');

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

    my $ds_headcode = $self->Client()->get_DataSet_by_name($self->dsname())->HEADCODE();

    my $response = $self->Client()->general_http_dialog(
        0,
        'GET',
        'get_tiling_and_seq',
        {
            %{$self->toHash},
            'dnawanted' => $dna_wanted,
            'metakey'   => '.',             # get the slice from Otter_db
            'pipehead'  => $ds_headcode,    # API version of Otter_db must be set in species.dat
            #
            # If you want to get the tiling_path from Pipe_db,
            # omit 'metakey' and set 'pipehead' from the value in otter_config
            #
        },
        1,
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
    my( $self, $analysis_name, $pipehead, $metakey ) = @_;

    my %analyses = (); # keep cached analysis objects here

    my $response = $self->Client()->general_http_dialog(
        0,
        'GET',
        'get_simple_features',
        {
            %{$self->toHash},
            $analysis_name ? ('analysis' => $analysis_name) : (),
            'pipehead' => $pipehead ? 1 : 0,
            $metakey ? ('metakey' => $metakey) : (),
        },
        1,
    );

    my @resplines = split(/\n/,$response);

    my @sf_optnames = @{ $OrderOfOptions{SimpleFeature} };

    my @sfs = (); # simple features in a list
    foreach my $respline (@resplines) {

        my @optvalues  = split(/\t/,$respline);
        my $linetype   = shift @optvalues; # 'SimpleFeature'

            # note this is optional now, depending on trueness of $analysis_name:
        my $logic_name = $analysis_name || pop @optvalues;

        my $sf = Bio::EnsEMBL::SimpleFeature->new();

        for (my $i = 0; $i < @sf_optnames; $i++) {
            my $method = $sf_optnames[$i];
            $sf->$method($optvalues[$i]);
        }

            # cache if needed, otherwise use the cached value:
        $sf->analysis(
            $analyses{$logic_name} ||= Bio::EnsEMBL::Analysis->new(-logic_name => $logic_name)
        );

            # cached value:
        $sf->seqname( $self->name() );

        push @sfs, $sf;
    }

    return \@sfs;
}

sub get_all_DAS_SimpleFeatures { # get simple features from DAS source (via mapping Otter server)
    my( $self, $analysis_name, $pipehead, $metakey, $source, $dsn ) = @_;

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

        # cached values:
    my $analysis = Bio::EnsEMBL::Analysis->new( -logic_name => $analysis_name );

    my $response = $self->Client()->general_http_dialog(
        0,
        'GET',
        'get_das_simple_features',
        {
            %{$self->toHash},
            'analysis' => $analysis_name,
            'pipehead' => $pipehead ? 1 : 0,
            $metakey   ? ('metakey' => $metakey) : (), # if you forget it, it will be 'Otter' by default!
            'source'   => $source,
            'dsn'      => $dsn,
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

        for (my $i = 0; $i < @sf_optnames; $i++) {
            my $method = $sf_optnames[$i];
            $sf->$method($optvalues[$i]);
        }

            # use the cached values:
        $sf->analysis( $analysis );
        $sf->seqname( $self->name() );

        push @sfs, $sf;
    }

    return \@sfs;
}

sub get_all_Cons_SimpleFeatures { # get simple features from Compara 'GERP_CONSERVATION_SCORE'
    my( $self, $analysis_name, $pipehead, $metakey ) = @_;

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

        # cached values:
    my $analysis = Bio::EnsEMBL::Analysis->new( -logic_name => $analysis_name );

    my $response = $self->Client()->general_http_dialog(
        0,
        'GET',
        'get_cons_simple_features',
        {
            %{$self->toHash},
            'analysis' => $analysis_name,
            'pipehead' => $pipehead ? 1 : 0,
            $metakey   ? ('metakey' => $metakey) : (), # if you forget it, it will be 'Otter' by default!
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

        for (my $i = 0; $i < @sf_optnames; $i++) {
            my $method = $sf_optnames[$i];
            $sf->$method($optvalues[$i]);
        }

            # use the cached values:
        $sf->analysis( $analysis );
        $sf->seqname( $self->name() );

        push @sfs, $sf;
    }

    return \@sfs;
}

sub get_all_DnaAlignFeatures { # get dna align features from otter/pipeline/ensembl db
    my( $self, $analysis_name, $pipehead, $metakey ) = @_;

    return $self->get_all_AlignFeatures( 'dafs', $analysis_name, $pipehead );
}

sub get_all_ProteinAlignFeatures { # get protein align features from otter/pipeline/ensembl db
    my( $self, $analysis_name, $pipehead, $metakey ) = @_;

    return $self->get_all_AlignFeatures( 'pafs', $analysis_name, $pipehead );
}

sub get_all_AlignFeatures { # get align features from otter/pipeline/ensembl db
    my( $self, $kind, $analysis_name, $pipehead, $metakey ) = @_;

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
            $metakey ? ('metakey' => $metakey) : (),
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

                # note this is optional now, depending on trueness of $analysis_name:
            my $logic_name    = $analysis_name || pop @optvalues;

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

sub get_all_RepeatFeatures { # get repeat features from otter/pipeline/ensembl db
    my( $self, $analysis_name, $pipehead, $metakey ) = @_;

    my %analyses = (); # keep cached analysis objects here

    my $response = $self->Client()->general_http_dialog(
        0,
        'GET',
        'get_repeat_features',
        {
            %{$self->toHash},
            $analysis_name ? ('analysis' => $analysis_name) : (),
            'pipehead' => $pipehead ? 1 : 0,
            $metakey ? ('metakey' => $metakey) : (),
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

                # note this is optional now, depending on trueness of $analysis_name:
            my $logic_name    = $analysis_name || pop @optvalues;

            my $rc_id = pop @optvalues;

            my $rf = Bio::EnsEMBL::RepeatFeature->new();

            for my $ind (0..@rf_optnames-1) {
                my $method = $rf_optnames[$ind];
                $rf->$method($optvalues[$ind]);
            }

                # cache if needed, otherwise use the cached value:
            $rf->analysis(
                $analyses{$logic_name} ||= Bio::EnsEMBL::Analysis->new(-logic_name => $logic_name)
            );

                # use the cached values:
            $rf->repeat_consensus( $rcs{$rc_id} );

            push @rfs, $rf;
        }
    }

    return \@rfs;
}

sub get_all_MarkerFeatures { # get marker features from otter/pipeline/ensembl db
    my( $self, $analysis_name, $pipehead, $metakey ) = @_;

    my %analyses = (); # keep cached analysis objects here

    my $response = $self->Client()->general_http_dialog(
        0,
        'GET',
        'get_marker_features',
        {
            %{$self->toHash},
            $analysis_name ? ('analysis' => $analysis_name) : (),
            'pipehead' => $pipehead ? 1 : 0,
            $metakey ? ('metakey' => $metakey) : (),
        },
        1,
    );

    my @resplines = split(/\n/,$response);

    my @mf_optnames = @{ $OrderOfOptions{MarkerFeature} };
    my @mo_optnames = @{ $OrderOfOptions{MarkerObject} };
    my @ms_optnames = @{ $OrderOfOptions{MarkerSynonym} };

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

                # note this is optional now, depending on trueness of $analysis_name:
            my $logic_name    = $analysis_name || pop @optvalues;

            my $mo_id = pop @optvalues;
            my $mo = $mos{mo_id}; # should have been defined earlier!

            my $mf = Bio::EnsEMBL::Map::MarkerFeature->new();

            for my $ind (0..@mf_optnames-1) {
                my $method = $mf_optnames[$ind];
                $mf->$method($optvalues[$ind]);
            }
            $mf->marker( $mo );
            $mf->_marker_id( $mo_id );

                # cache if needed, otherwise use the cached value:
            $mf->analysis(
                $analyses{$logic_name} ||= Bio::EnsEMBL::Analysis->new(-logic_name => $logic_name)
            );

                # use the cached values:
            $mf->strand( 0 );

            push @mfs, $mf;
        }
    }

    return \@mfs;
}

sub get_all_DitagFeatureGroups { # get ditag features from otter/pipeline/ensembl db
    #
    # the returned list is 2d, with features grouped by ditag_id.ditag_pair_id
    # (even if there was only one feature per group)
    #
    my( $self, $analysis_name, $pipehead, $metakey, $ditypes ) = @_;

    my %analyses = (); # keep cached analysis objects here

    my $response = $self->Client()->general_http_dialog(
        0,
        'GET',
        'get_ditag_features',
        {
            %{$self->toHash},
            $analysis_name ? ('analysis' => $analysis_name) : (),
            'pipehead' => $pipehead ? 1 : 0,
            $metakey ? ('metakey' => $metakey) : (),
            $ditypes ? ('ditypes' => $ditypes) : (),
        },
        1,
    );

    my @resplines = split(/\n/,$response);

    my @df_optnames = @{ $OrderOfOptions{DitagFeature} };
    my @do_optnames = @{ $OrderOfOptions{DitagObject} };

    my %dos  = (); # cached ditag objects, keyed by do_id
    my %dfs  = (); # ditag features in a HoHoL {ditag_id}{ditag_pair_id} -> [L,R]
    foreach my $respline (@resplines) {

        my @optvalues = split(/\t/,$respline);
        my $linetype  = shift @optvalues; # 'DitagFeature' || 'DitagObject'

        if($linetype eq 'DitagObject') {

            my $do_id = pop @optvalues;

            my $do = Bio::EnsEMBL::Map::Ditag->new(
                map { ("-$do_optnames[$_]" => $optvalues[$_]) }
                    (0..@do_optnames-1)
            );
            $dos{do_id} = $do;

        } elsif($linetype eq 'DitagFeature') {

                # note this is optional now, depending on trueness of $analysis_name:
            my $logic_name    = $analysis_name || pop @optvalues;

            my $do_id = pop @optvalues;
            my $do = $dos{do_id}; # should have been defined earlier!

            my $df = Bio::EnsEMBL::Map::DitagFeature->new(
                map { ("-$df_optnames[$_]" => $optvalues[$_]) }
                    (0..@df_optnames-1)
            );
            $df->ditag( $do );

                # cache if needed, otherwise use the cached value:
            $df->analysis(
                $analyses{$logic_name} ||= Bio::EnsEMBL::Analysis->new(-logic_name => $logic_name)
            );

            my $uniq_group_id = $do_id.'.'.$df->ditag_pair_id;
            push @{$dfs{$uniq_group_id}}, $df;
        }
    }

    return [ values %dfs ];
}

sub get_all_PredictionTranscripts { # get prediction transcripts from otter/pipeline/ensembl db
    my( $self, $analysis_name, $pipehead, $metakey ) = @_;

    my %analyses = (); # keep cached analysis objects here

    my $response = $self->Client()->general_http_dialog(
        0,
        'GET',
        'get_prediction_transcripts',
        {
            %{$self->toHash},
            $analysis_name ? ('analysis' => $analysis_name) : (),
            'pipehead' => $pipehead ? 1 : 0,
            $metakey ? ('metakey' => $metakey) : (),
        },
        1,
    );

    my @resplines = split(/\n/,$response);

    my @pt_optnames = @{ $OrderOfOptions{PredictionTranscript} };
    my @pe_optnames = @{ $OrderOfOptions{PredictionExon} };

    my @pts = (); # prediction transcripts in a list
    my $curr_pt;
    my $curr_ptid;
    foreach my $respline (@resplines) {

        my @optvalues = split(/\t/,$respline);
        my $linetype      = shift @optvalues; # 'PredictionTranscript' || 'PredictionExon'

        if($linetype eq 'PredictionTranscript') {

                # note this is optional now, depending on trueness of $analysis_name:
            my $logic_name    = $analysis_name || pop @optvalues;

            my $pt = Bio::EnsEMBL::PredictionTranscript->new();
            for my $ind (0..@pt_optnames-1) {
                my $method = $pt_optnames[$ind];
                $pt->$method($optvalues[$ind]);
            }

                # cache if needed, otherwise use the cached value:
            $pt->analysis(
                $analyses{$logic_name} ||= Bio::EnsEMBL::Analysis->new(-logic_name => $logic_name)
            );

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

            if($pt_id == $curr_ptid) {
                    # copy over:
                $pe->analysis( $curr_pt->analysis() );

                $curr_pt->add_Exon( $pe );
            } else {
                die "Wrong order of exons in the stream!";
            }
        }
    }

    return \@pts;
}

sub get_all_PipelineGenes { # get genes from otter/pipeline/ensembl db
    my( $self, $analysis_name, $pipehead, $metakey, $transcript_analyses, $translation_xref_dbs ) = @_;

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

    my $response = $self->Client()->general_http_dialog(
        0,
        'GET',
        'get_genes',
        {
            %{$self->toHash},
            'analysis' => $analysis_name,
            'pipehead' => $pipehead ? 1 : 0,
            $metakey ? ('metakey' => $metakey) : (),
            $transcript_analyses ? ('transcript_analyses' => $transcript_analyses) : (),
            $translation_xref_dbs ? ('translation_xref_dbs' => $translation_xref_dbs) : (),
        },
        1,
    );
    my $slice = $self->create_detached_slice();

    my @resplines = split(/\n/,$response);

    my $gene_parser = Bio::Otter::FromXML->new([ split(/\n/,$response) ], $slice);
    my $genes = $gene_parser->build_Gene_array($slice);

    return $genes;
}

sub get_all_Genes { # non-default :)
    my( $self, $analysis_name ) = @_;

    $analysis_name ||= 'otter';

    return $self->get_all_PipelineGenes($analysis_name, 0, '.');
}

1;

