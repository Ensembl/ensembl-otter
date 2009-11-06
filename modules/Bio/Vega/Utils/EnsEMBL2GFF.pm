### Bio::Vega::Utils::EnsEMBL2GFF

package Bio::Vega::Utils::EnsEMBL2GFF;

use strict;
use warnings;

# This module allows conversion of ensembl/otter objects to GFF by inserting
# to_gff (and supporting _gff_hash) methods into the necessary feature classes

{

    package Bio::EnsEMBL::Slice;

    sub gff_header {

        my $self        = shift;
        my %args        = @_;
        my $include_dna = $args{include_dna};

        # build up a date string in the format specified by the GFF spec

        my ( $sec, $min, $hr, $mday, $mon, $year ) = localtime;
        $year += 1900;    # correct the year
        $mon++;           # correct the month
        my $date = "$year-$mon-$mday";

        my $hdr =
            "##gff-version 2\n"
          . "##source-version EnsEMBL2GFF 1.0\n"
          . "##date $date\n"
          . "##sequence-region "
          . $self->seq_region_name . " "
          . $self->start . " "
          . $self->end . "\n";

        if ($include_dna) {
            $hdr .= "##DNA\n" . "##" . $self->seq . "\n" . "##end-DNA\n";
        }

        return $hdr;
    }

    sub to_gff {

        # convert an entire slice to GFF, pass in the analyses and feature types
        # you're interested in, e.g.:
        #
        # print $slice->to_gff(
        # 	 analyses 		=> ['RepeatMasker', 'vertrna'],
        #	 feature_types	=> ['RepeatFeatures', 'DnaAlignFeatures', 'SimpleFeatures'],
        #	 include_header => 1
        # );

        my $self = shift;

        my %args = @_;

        my $analyses = $args{analyses}
          || ['']
          ; # if we're not given any analyses, search for features from all analyses
        my $feature_types  = $args{feature_types};
        my $include_header = $args{include_header};
        my $include_dna    = $args{include_dna};
        my $verbose        = $args{verbose};

        my $sources_to_types = $args{sources_to_types};

        my $gff =
            $include_header
          ? $self->gff_header( include_dna => $include_dna )
          : '';

        # grab features of each type we're interested in

        for my $feature_type (@$feature_types) {

            my $method = 'get_all_' . $feature_type;

            unless ( $self->can($method) ) {
                warn "There is no method to retrieve $feature_type from a slice";
                next;
            }

            for my $analysis (@$analyses) {

                my $features = $self->$method($analysis);

                if ( $verbose && scalar(@$features) ) {
                    print "Found "
                      . scalar(@$features)
                      . " $feature_type from $analysis on slice "
                      . $self->seq_region_name . "\n";
                }

               for my $feature (@$features) {

                    if ( $feature->can('to_gff') ) {
                        
                        if (ref $feature eq 'Bio::EnsEMBL::Gene') {
                            map { 
                                my $truncated = $_->truncate_to_Slice($self);
                                warn "Truncated transcript: ".$_->display_id if $truncated;
                            } @{ $feature->get_all_Transcripts };
                        }
                        elsif (ref $feature eq 'Bio::EnsEMBL::Transcript') {
                            my $truncated = $feature->truncate_to_Slice($self);
                            warn "Truncated transcript: ".$feature->display_id if $truncated;
                        }
            
                        
                        $gff .= $feature->to_gff . "\n";

                        if ($sources_to_types) {

                            # If we are passed a sources_to_types hashref, then as we identify the types of
                            # features each analysis can create, fill in the hash for the caller. This is
                            # required by enzembl, but other users can just ignore this parameter.

                            my $source = $feature->_gff_hash->{source};

                            if ( $sources_to_types->{$source} ) {
                                unless ( $sources_to_types->{$source} eq
                                    $feature_type )
                                {
                                    die
                                        "Can't have multiple gff sources from one analysis:\n"
                                      . "('$analysis' seems to have both '"
                                      . $sources_to_types->{$source}
                                      . "' and '$feature_type')\n";
                                }
                            }
                            else {
                                $sources_to_types->{$source} = $feature_type;
                            }
                        }
                    }
                    else {
                        warn "no to_gff method in $feature_type";
                    }
                }
            }
        }

        return $gff;
    }
}

{

    package Bio::EnsEMBL::Feature;

    sub to_gff {

        my $self = shift;

        # This parameter is assumed to be a hashref which includes extra attributes you'd
        # like to have appended onto the gff line for the feature
        my $extra_attrs = shift;

        my $gff = $self->_gff_hash;

        $gff->{score}  = '.' unless defined $gff->{score};
        $gff->{strand} = '.' unless defined $gff->{strand};
        $gff->{frame}  = '.' unless defined $gff->{frame};

        # order as per GFF spec: http://www.sanger.ac.uk/Software/formats/GFF/GFF_Spec.shtml

        my $gff_str = join( "\t",
            $gff->{seqname}, $gff->{source}, $gff->{feature}, $gff->{start},
            $gff->{end},     $gff->{score},  $gff->{strand},  $gff->{frame},
        );

        if ($extra_attrs) {

            # combine the extra attributes with any existing ones (duplicate keys will get squashed!)
            $gff->{attributes} = {} unless defined $gff->{attributes};
            @{ $gff->{attributes} }{ keys %$extra_attrs } =
              values %$extra_attrs;
        }

        if ( $gff->{attributes} ) {

            # we only sort in reverse alphabetical order here for the moment to work around a bug in zmap
            # that requires "Sequence" attributes to come before "Locus" attributes
            my @attrs =
              map  { $_ . ' ' . $gff->{attributes}->{$_} }
              sort { $b cmp $a } keys %{ $gff->{attributes} };
            $gff_str .= "\t" . join( "\t;\t", @attrs );
        }

        return $gff_str;
    }

    sub _gff_hash {
        my $self = shift;

        my %gff = (
            seqname => $self->slice->seq_region_name,
            source =>
              ( $self->analysis->gff_source || $self->analysis->logic_name ),
            feature => ( $self->analysis->gff_feature || 'misc_feature' ),
            start   => $self->start,
            end     => $self->end,
            strand  => (
                $self->strand == 1 ? '+' : ( $self->strand == -1 ? '-' : '.' )
            )
        );

        return \%gff;
    }
}

{

    package Bio::EnsEMBL::SimpleFeature;

    sub _gff_hash {
        my $self = shift;

        my $gff = $self->SUPER::_gff_hash;

        $gff->{source} .= "_simple_feature";
        $gff->{score}   = $self->score;
        $gff->{feature} = 'misc_feature';

        if ( $self->display_label ) {
            $gff->{attributes}->{Note} = '"' . $self->display_label . '"';
        }

        return $gff;
    }
}

{

    package Bio::EnsEMBL::FeaturePair;

    sub _gff_hash {
        my $self = shift;

        my $gap_string = '';

        my @fps = $self->ungapped_features;

        if ( @fps > 1 ) {
            my @gaps =
              map { join( ' ', $_->start, $_->end, $_->hstart, $_->hend ) }
              @fps;
            $gap_string = join( ',', @gaps );
        }

        my $gff = $self->SUPER::_gff_hash;

        $gff->{score} = $self->score;
        $gff->{feature} = $self->analysis->gff_feature || 'similarity';

        $gff->{attributes}->{Target} =
            '"Sequence:'
          . $self->hseqname . '" '
          . $self->hstart . ' '
          . $self->hend . ' '
          . ( $self->hstrand == -1 ? '-' : '+' );

        if ($gap_string) {
            $gff->{attributes}->{Gaps} = qq("$gap_string");
        }

        return $gff;
    }
}

{

    package Bio::EnsEMBL::Gene;

    sub to_gff {
        my $self = shift;

        # just concatenate the gff of each of the transcripts, joining them together
        # with the Locus attribute
        return join( "\n",
            map { $_->to_gff( { Locus => '"' . $self->display_id . '"' } ) }
              @{ $self->get_all_Transcripts } );
    }
}

{

    package Bio::EnsEMBL::Transcript;

    sub _gff_hash {
        my $self = shift;
        my $gff  = $self->SUPER::_gff_hash;
        $gff->{feature} = 'Sequence';
        $gff->{attributes}->{Sequence} = '"' . $self->display_id . '"';
        return $gff;
    }

    sub to_gff {

        my $self = shift;
        
        return '' unless @{ $self->get_all_Exons };

        my $gff = $self->SUPER::to_gff(@_);

        if ( defined $self->coding_region_start ) {

            # build up the CDS line (unfortunately there's not really an object we can hang this off
            # so we have to build the whole line ourselves)
            $gff .= "\n" . join(
                "\t",
                $self->_gff_hash->{seqname},
                $self->_gff_hash->{source},
                'CDS',    # feature
                $self->coding_region_start,
                $self->coding_region_end,
                '.',      # score
                $self->_gff_hash->{strand},
                '0'
                , # frame - not really sure what we should put here, but giface always seems to use 0, so we will too!
                'Sequence ' . $self->_gff_hash->{attributes}->{Sequence}
            );
        }

        # add gff lines for each of the introns and exons
        # (adding lines for both seems a bit redundant to me, but zmap seems to like it!)
        for my $feat ( @{ $self->get_all_Exons }, @{ $self->get_all_Introns } )
        {

            # exons and introns don't have analyses attached, so give them the transcript's one
            $feat->analysis( $self->analysis );

            # and add the feature's gff line to our string, including the sequence information as an attribute
            $gff .= "\n"
              . $feat->to_gff( { Sequence => '"' . $self->display_id . '"' } );

            # to be on the safe side, get rid of the analysis we temporarily attached
            # (someone might rely on there not being one later)
            $feat->analysis(undef);
        }

        return $gff;
    }
    
    sub get_all_Exons_ref {
        my ($self) = @_;
    
        $self->get_all_Exons;
        if (my $ref = $self->{'_trans_exon_array'}) {
            return $ref;
        } else {
            $self->throw("'_trans_exon_array' not set");
        }
    }
    
    sub truncate_to_Slice {
        my ( $self, $slice ) = @_;

        # start and end exon are set to zero so that we can
        # safely use them in "==" without generating warnings
        # as we loop through the list of exons.
        ### Not used until we enable translation truncating
        my $start_exon = 0;
        my $end_exon   = 0;
        my ($tsl);
        if ( $tsl = $self->translation ) {
            $start_exon = $tsl->start_Exon;
            $end_exon   = $tsl->end_Exon;
        }
        my $exons_truncated     = 0;
        my $in_translation_zone = 0;
        my $slice_length        = $slice->length;

        # Ref to list of exons for inplace editing
        my $ex_list = $self->get_all_Exons_ref;

        for ( my $i = 0 ; $i < @$ex_list ; ) {
            my $exon       = $ex_list->[$i];
            my $exon_start = $exon->start;
            my $exon_end   = $exon->end;

            # now compare slice names instead of slice references
            # slice references can be different not the slice names
            if (   $exon->slice->name ne $slice->name
                or $exon_end < 1
                or $exon_start > $slice_length )
            {

                #warn "removing exon that is off slice";
                splice( @$ex_list, $i, 1 );
                $exons_truncated++;
            }
            else {

                #printf STDERR
                #    "Checking if exon %s is within slice %s of length %d\n"
                #    . "  being attached to %s and extending from %d to %d\n",
                #    $exon->stable_id, $slice, $slice_length, $exon->contig, $exon_start, $exon_end;
                $i++;
                my $trunc_flag = 0;
                if ( $exon->start < 1 ) {

                    #warn "truncating exon that overlaps start of slice";
                    $trunc_flag = 1;
                    $exon->start(1);
                }
                if ( $exon->end > $slice_length ) {

                    #warn "truncating exon that overlaps end of slice";
                    $trunc_flag = 1;
                    $exon->end($slice_length);
                }
                $exons_truncated++ if $trunc_flag;
            }
        }
        
        ### Hack until we fiddle with translation stuff
        if ($exons_truncated) {
            $self->{'translation'}     = undef;
            $self->{'_translation_id'} = undef;
            my $attrib = $self->get_all_Attributes;
            for ( my $i = 0 ; $i < @$attrib ; ) {
                my $this = $attrib->[$i];

                # Should not have CDS start/end not found attributes
                # if there is no CDS!
                if ( $this->code =~ /^cds_(start|end)_NF$/ ) {
                    splice( @$attrib, $i, 1 );
                }
                else {
                    $i++;
                }
            }
        }
        
        $self->recalculate_coordinates;
        
        return $exons_truncated;
    }
}

{

    package Bio::EnsEMBL::Exon;

    sub _gff_hash {
        my $self = shift;
        my $gff  = $self->SUPER::_gff_hash;
        $gff->{feature} = 'exon';
        return $gff;
    }
}

{

    package Bio::EnsEMBL::Intron;

    sub _gff_hash {
        my $self = shift;
        my $gff  = $self->SUPER::_gff_hash;
        $gff->{feature} = 'intron';
        return $gff;
    }
}

{

    package Bio::Otter::DnaDnaAlignFeature;

    sub _gff_hash {
        my $self = shift;
        my $gff  = $self->SUPER::_gff_hash;
        $gff->{attributes}->{Length} = $self->get_HitDescription->hit_length;
        return $gff;
    }
}

1;

__END__
	
=head1 NAME - Bio::Vega::Utils::EnsEMBL2GFF 

=head1 SYNOPSIS

Inserts to_gff (and supporting _gff_hash) methods into various EnsEMBL and Otter classes, allowing
them to be converted to GFF by calling C<$object->to_gff>. You can also get the GFF for an entire slice
by calling C<$slice->to_gff>, passing in lists of the analyses and feature types you're interested in.

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk

