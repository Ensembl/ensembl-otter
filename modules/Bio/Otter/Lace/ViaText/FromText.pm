# Assemble pre-ver.20 EnsEMBL objects from text

package Bio::Otter::Lace::ViaText::FromText;

use strict;
use warnings;

use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DnaDnaAlignFeature;
use Bio::EnsEMBL::DnaPepAlignFeature;
use Bio::EnsEMBL::PredictionTranscript;
use Bio::EnsEMBL::RepeatConsensus;
use Bio::EnsEMBL::RepeatFeature;
use Bio::EnsEMBL::SimpleFeature;
use Bio::EnsEMBL::Slice;
use Bio::EnsEMBL::Map::MarkerSynonym;
use Bio::EnsEMBL::Map::Marker;
use Bio::EnsEMBL::Map::MarkerFeature;
use Bio::EnsEMBL::Map::Ditag;
use Bio::EnsEMBL::Map::DitagFeature;
use Bio::Otter::DnaDnaAlignFeature;
use Bio::Otter::DnaPepAlignFeature;
use Bio::Otter::FromXML;
use Bio::Otter::HitDescription;

use Bio::Otter::Lace::ViaText ('%OrderOfOptions');

use base ('Exporter');
our @EXPORT    = ();
our @EXPORT_OK = qw( &ParseSimpleFeatures &ParseAlignFeatures &ParseRepeatFeatures &ParseMarkerFeatures
                     &ParseDitagFeatureGroups &ParsePredictionTranscripts &ParseGenes );


### The following parsers create lists of objects given the ViaText representation: ###

sub ParseSimpleFeatures {
    my ($response_ref, $seqname, $analysis_name) = @_;

    my %analyses = (); # keep cached analysis objects here
    my $resplines_ref = [ split(/\n/,$$response_ref) ];

    my @sf_optnames = @{ $OrderOfOptions{SimpleFeature} };

    my @sfs = (); # simple features in a list
    foreach my $respline (@$resplines_ref) {

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

            # passed value:
        $sf->seqname( $seqname );

        push @sfs, $sf;
    }

    return \@sfs;
}

sub ParseAlignFeatures {
    my ($response_ref, $kind, $seqname, $analysis_name) = @_;

    my ($baseclass, $subclass) = @{ {
        'dafs' => [ qw(Bio::EnsEMBL::DnaDnaAlignFeature Bio::Otter::DnaDnaAlignFeature) ],
        'pafs' => [ qw(Bio::EnsEMBL::DnaPepAlignFeature Bio::Otter::DnaPepAlignFeature) ],
    }->{$kind} };
    
    my %analyses = (); # keep cached analysis objects here
    my $resplines_ref = [ split(/\n/,$$response_ref) ];

    my @af_optnames = @{ $OrderOfOptions{AlignFeature} };
    my @hd_optnames = @{ $OrderOfOptions{HitDescription} };

    my %hds = (); # cached hit descriptions, keyed by hit_name
    my @afs = (); # align features in a list
    foreach my $respline (@$resplines_ref) {

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

                # use the passed value:
            $af->seqname( $seqname );

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

sub ParseRepeatFeatures {
    my ($response_ref, $analysis_name) = @_;

    my %analyses = (); # keep cached analysis objects here
    my $resplines_ref = [ split(/\n/,$$response_ref) ];

    my @rf_optnames = @{ $OrderOfOptions{RepeatFeature} };
    my @rc_optnames = @{ $OrderOfOptions{RepeatConsensus} };

        # cached values:
    my $analysis = Bio::EnsEMBL::Analysis->new( -logic_name => $analysis_name );

    my %rcs = (); # cached repeat consensi, keyed by rc_id
    my @rfs = (); # repeat features in a list
    foreach my $respline (@$resplines_ref) {

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

sub ParseMarkerFeatures {
    my ($response_ref, $analysis_name) = @_;

    my %analyses = (); # keep cached analysis objects here
    my $resplines_ref = [ split(/\n/,$$response_ref) ];

    my @mf_optnames = @{ $OrderOfOptions{MarkerFeature} };
    my @mo_optnames = @{ $OrderOfOptions{MarkerObject} };
    my @ms_optnames = @{ $OrderOfOptions{MarkerSynonym} };

    my %mos  = (); # cached marker objects, keyed by mo_id
    my @mfs  = (); # marker features in a list
    foreach my $respline (@$resplines_ref) {

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

    #
    # the returned list is 2d, with features grouped by ditag_id.ditag_pair_id
    # (even if there was only one feature per group)
    #
sub ParseDitagFeatureGroups {
    my ($response_ref, $analysis_name) = @_;

    my %analyses = (); # keep cached analysis objects here
    my $resplines_ref = [ split(/\n/,$$response_ref) ];

    my @df_optnames = @{ $OrderOfOptions{DitagFeature} };
    my @do_optnames = @{ $OrderOfOptions{DitagObject} };

    my %dos  = (); # cached ditag objects, keyed by do_id
    my %dfs  = (); # ditag features in a HoHoL {ditag_id}{ditag_pair_id} -> [L,R]
    foreach my $respline (@$resplines_ref) {

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

sub ParsePredictionTranscripts {
    my ($response_ref, $analysis_name) = @_;

    my %analyses = (); # keep cached analysis objects here
    my $resplines_ref = [ split(/\n/,$$response_ref) ];

    my @pt_optnames = @{ $OrderOfOptions{PredictionTranscript} };
    my @pe_optnames = @{ $OrderOfOptions{PredictionExon} };

    my @pts = (); # prediction transcripts in a list
    my $curr_pt;
    my $curr_ptid;
    foreach my $respline (@$resplines_ref) {

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

sub ParseGenes {
    my ($response_ref, $slice) = @_;

    my $gene_parser = Bio::Otter::FromXML->new([ split(/\n/, $$response_ref) ], $slice);
    my $genes = $gene_parser->build_Gene_array($slice);

    return $genes;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::ViaText::FromText

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk

