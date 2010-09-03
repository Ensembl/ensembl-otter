### Bio::Vega::Utils::EnsEMBL2GFF

package Bio::Vega::Utils::EnsEMBL2GFF;

use strict;
use warnings;


# This module allows conversion of ensembl/otter objects to GFF by inserting
# to_gff (and supporting _gff_hash) methods into the necessary feature classes

sub gff_header {
    my ($name, $start, $end, $dna) = @_;
    
    # build up a date string in the format specified by the GFF spec

    my ( $sec, $min, $hr, $mday, $mon, $year ) = localtime;
    $year += 1900;    # correct the year
    $mon++;           # correct the month
    my $date = "$year-$mon-$mday";
    
    my $hdr =
        "##gff-version 2\n"
      . "##source-version EnsEMBL2GFF 1.0\n"
      . "##date $date\n"
      . "##sequence-region $name $start $end\n";

    $hdr .= "##DNA\n##$dna\n##end-DNA\n" if $dna;

    return $hdr;
}


## no critic(Modules::ProhibitMultiplePackages)

{

    package Bio::EnsEMBL::Slice;
    
    use Bio::EnsEMBL::Utils::Exception qw(verbose);

    sub gff_header {
        my ($self, %args) = @_;

        my $include_dna = $args{include_dna};
        my $rebase      = $args{rebase};
        my $seqname     = $args{gff_seqname} || $self->seq_region_name;

        my $name  = $rebase ? $seqname.'_'.$self->start.'-'.$self->end : $seqname;
        my $start = $rebase ? 1 : $self->start;
        my $end   = $rebase ? $self->length : $self->end;

        return Bio::Vega::Utils::EnsEMBL2GFF::gff_header(
            $name, 
            $start, 
            $end, 
            ($include_dna ? $self->seq : undef),
        );      
    }

    sub to_gff {

        # convert an entire slice to GFF, pass in the analyses and feature types
        # you're interested in, e.g.:
        #
        # print $slice->to_gff(
        #     analyses       => ['RepeatMasker', 'vertrna'],
        #     feature_types  => ['RepeatFeatures', 'DnaAlignFeatures', 'SimpleFeatures'],
        #     include_header => 1
        # );

        my ($self, %args) = @_;

        my $analyses = $args{analyses} || ['']; # if we're not given any analyses, search for features from all analyses
        my $feature_types  = $args{feature_types};
        my $include_header = $args{include_header};
        my $include_dna    = $args{include_dna};
        my $verbose        = $args{verbose};
        my $target_slice   = $args{target_slice} || $self;
        my $common_slice   = $args{common_slice};
        my $rebase         = $args{rebase};
        my $gff_source     = $args{gff_source};
        my $gff_seqname    = $args{gff_seqname};
        

        my $sources_to_types = $args{sources_to_types};
    
        my $gff = $include_header ? 
            $target_slice->gff_header( include_dna => $include_dna, rebase => $rebase, gff_seqname => $gff_seqname ) :
            '';
        
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
                      . " $feature_type from $analysis\n";
                }

                for my $feature (@$features) {
                    
                    if ( $feature->can('to_gff') ) {
                        
                        if ($common_slice) {
                            
                            # if we're passed a common slice we need to give it to each feature
                            # and then transfer from this slice to the target slice
                        
                            $feature->slice($common_slice);
                            
                            my $id = $feature->display_id;
                            
                            my $old_verbose_level = verbose();
                            verbose(0);
                            
                            $feature = $feature->transfer($target_slice);
                            
                            verbose($old_verbose_level);
                            
                            unless ($feature) {
                                print "Failed to transform feature: $id\n" if $verbose;
                                next;
                            }
                        }
                        
                        if ($feature->isa('Bio::EnsEMBL::Gene')) {
                            foreach my $transcript ( @{ $feature->get_all_Transcripts } ) { 
                                my $truncated = $_->truncate_to_Slice($target_slice);
                                print "Truncated transcript: ".$_->display_id."\n" if $truncated && $verbose;
                            }
                        }
                        elsif ($feature->isa('Bio::EnsEMBL::Transcript')) {
                            my $truncated = $feature->truncate_to_Slice($target_slice);
                            print "Truncated transcript: ".$feature->display_id."\n" if $truncated && $verbose;
                        }
                        
                        $gff .= $feature->to_gff(rebase => $rebase, gff_source => $gff_source, gff_seqname => $gff_seqname) . "\n";

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
        
        # remove any empty lines resulting from truncated transcripts etc.
        $gff =~ s/\n\s*\n/\n/g;        

        return $gff;
    }
}

{

    package Bio::EnsEMBL::Feature;

    sub to_gff {

        my ($self, %args) = @_;
        
        # This parameter is assumed to be a hashref which includes extra attributes you'd
        # like to have appended onto the gff line for the feature
        my $extra_attrs = $args{extra_attrs};

        my $gff = $self->_gff_hash(%args);

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
            @{ $gff->{attributes} }{ keys %$extra_attrs } = values %$extra_attrs;
        }

        if ( $gff->{attributes} ) {

            my @attrs = map  { $_ . ' ' . $gff->{attributes}->{$_} } keys %{ $gff->{attributes} };
                
            $gff_str .= "\t" . join( "\t;\t", @attrs );
        }

        return $gff_str;
    }

    sub _gff_hash {
        my ($self, %args) = @_;
        
        my $rebase      = $args{rebase};
        my $gff_seqname = $args{gff_seqname} || $self->slice->seq_region_name;
        my $gff_source  = $args{gff_source} || $self->_gff_source;

        my $seqname = $rebase ? $gff_seqname.'_'.$self->slice->start.'-'.$self->slice->end : $gff_seqname;
        my $start = $rebase ? $self->start : $self->seq_region_start;
        my $end = $rebase ? $self->end : $self->seq_region_end;

        my $gff = {
            seqname => $seqname,
            source  => $gff_source,
            feature => $self->_gff_feature,
            start   => $start,
            end     => $end,
            strand  => (
                $self->strand == 1 ? '+' : ( $self->strand == -1 ? '-' : '.' )
            )
        };

        return $gff;
    }

    sub _gff_source {
        my ($self) = @_;
        
        if ($self->analysis) {
            return
                $self->analysis->gff_source
                || $self->analysis->logic_name;
        }
        else {
            return ref($self);
        }
    }

    sub _gff_feature {
        my ($self) = @_;

        return
            ( $self->analysis && $self->analysis->gff_feature )
            || 'misc_feature';
    }
}

{

    package Bio::EnsEMBL::SimpleFeature;

    sub _gff_hash {
        my ($self, @args) = @_;

        my $gff = $self->SUPER::_gff_hash(@args);

        $gff->{score}   = $self->score;
        $gff->{feature} = 'misc_feature';

        if ( $self->display_label ) {
            $gff->{attributes}->{Name} = '"' . $self->display_label . '"';
        }

        return $gff;
    }
}

{

    package Bio::EnsEMBL::FeaturePair;

    sub _gff_hash {
        my ($self, %args) = @_;
        
        my $rebase = $args{rebase};
        
        my $gap_string = '';

        my @fps = $self->ungapped_features;

        if ( @fps > 1 ) {
            my @gaps =
              map { join( ' ', ($rebase ? $_->start : $_->seq_region_start), ($rebase ? $_->end : $_->seq_region_end), $_->hstart, $_->hend ) }
              @fps;
            $gap_string = join( ',', @gaps );
        }

        my $gff = $self->SUPER::_gff_hash(%args);

        $gff->{score} = $self->percent_id;
        $gff->{feature} = ($self->analysis && $self->analysis->gff_feature) || 'similarity';
        
        $gff->{attributes}->{Class} = qq("Sequence");
        $gff->{attributes}->{Name} = '"'.$self->hseqname.'"';
        $gff->{attributes}->{Align} = $self->hstart.' '.$self->hend.' '.( $self->hstrand == -1 ? '-' : '+' );

        if ($gap_string) {
            $gff->{attributes}->{Gaps} = qq("$gap_string");
        }

        return $gff;
    }
}

{
    
    package Bio::EnsEMBL::DnaPepAlignFeature;
    
    sub _gff_hash {
        my ($self, @args) = @_;
        my $gff = $self->SUPER::_gff_hash(@args);
        $gff->{attributes}->{Class} = qq("Protein");
        return $gff;
    }
}

{

    package Bio::EnsEMBL::Gene;

    sub to_gff {
        my ($self, @args) = @_;
      
        # just concatenate the gff of each of the transcripts, joining them together
        # with the Locus attribute
        return join( "\n",
            map { $_->to_gff(@args, extra_attrs => { Locus => '"' . $self->display_id . '"' } ) }
              @{ $self->get_all_Transcripts } );
    }
}

{

    package Bio::EnsEMBL::Transcript;

    sub _gff_hash {
        my ($self, @args) = @_;
        my $gff  = $self->SUPER::_gff_hash(@args);
        $gff->{feature} = 'Sequence';
        $gff->{attributes}->{Class} = qq("Sequence");
        $gff->{attributes}->{Name} = '"'.$self->display_id.'"';
        return $gff;
    }

    sub to_gff {
        my ($self, %args) = @_;
        
        my $rebase = $args{rebase};
        
        return '' unless $self->get_all_Exons && @{ $self->get_all_Exons };
        
        # XXX: hack to help differentiate the various otter transcripts
        if ($self->analysis && $self->analysis->logic_name eq 'Otter') {
            $self->analysis->gff_source('Otter_'.$self->biotype);
        }

        my $gff = $self->SUPER::to_gff(%args);

        if ( $self->translation ) {
            
            # build up the CDS line - it's not really worth creating a Translation->to_gff method, as most
            # of the fields are derived from the Transcript and Translation doesn't inherit from Feature
            
            my $start = $self->coding_region_start;
            $start += $self->slice->start - 1 unless $rebase;
            
            my $end = $self->coding_region_end;
            $end += $self->slice->start - 1 unless $rebase;
            
            my $gff_hash = $self->_gff_hash(%args);
            
            $gff .= "\n" . join(
                "\t",
                $gff_hash->{seqname},
                $gff_hash->{source},
                'CDS',    # feature
                $start,
                $end,
                '.',      # score
                $gff_hash->{strand},
                '0', # frame - not really sure what we should put here, but giface always seems to use 0, so we will too!
                'Class "Sequence"',
                ';',
                'Name ' . $gff_hash->{attributes}->{Name}
            );
        }

        # add gff lines for each of the introns and exons
        # (adding lines for both seems a bit redundant to me, but zmap seems to like it!)
        for my $feat ( @{ $self->get_all_Exons }, @{ $self->get_all_Introns } ) {
            
            # exons and introns don't have analyses attached, so temporarily give them the transcript's one
            $feat->analysis( $self->analysis );

            # and add the feature's gff line to our string, including the sequence name information as an attribute
            $gff .= "\n"
              . $feat->to_gff( %args, extra_attrs => { Name => '"' . $self->display_id . '"' } );

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
            return; # unreached, but quietens "perlcritic --stern"
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
#        if ($exons_truncated) {
#            $self->{'translation'}     = undef;
#            $self->{'_translation_id'} = undef;
#            my $attrib = $self->get_all_Attributes;
#            for ( my $i = 0 ; $i < @$attrib ; ) {
#                my $this = $attrib->[$i];
#
#                # Should not have CDS start/end not found attributes
#                # if there is no CDS!
#                if ( $this->code =~ /^cds_(start|end)_NF$/ ) {
#                    splice( @$attrib, $i, 1 );
#                }
#                else {
#                    $i++;
#                }
#            }
#        }
        
        $self->recalculate_coordinates;
        
        return $exons_truncated;
    }
}

{

    package Bio::EnsEMBL::Exon;

    sub _gff_hash {
        my ($self, @args) = @_;
        my $gff  = $self->SUPER::_gff_hash(@args);
        $gff->{feature} = 'exon';
        $gff->{attributes}->{Class} = qq("Sequence");
        return $gff;
    }
}

{

    package Bio::EnsEMBL::Intron;

    sub _gff_hash {
        my ($self, @args) = @_;
        my $gff  = $self->SUPER::_gff_hash(@args);
        $gff->{feature} = 'intron';
        $gff->{attributes}->{Class} = qq("Sequence");
        return $gff;
    }
}

{

    package Bio::EnsEMBL::Variation::VariationFeature;

    my $url_format =
        'http://www.ensembl.org/Homo_sapiens/Variation/Summary?v=%s';

    sub _gff_hash {
        my ($self, @args) = @_;

        my $name = $self->variation->name;
        my $allele = $self->allele_string;
        my $url = sprintf $url_format, $name;

        my $gff  = $self->SUPER::_gff_hash(@args);
        my ( $start, $end ) = @{$gff}{qw( start end )};
        if ( $start == $end - 1 ) {
            @{$gff}{qw( start end )} = ( $end, $start );
        }

        $gff->{attributes}->{Name} = qq("$name - $allele");
        $gff->{attributes}->{URL} = qq("$url");

        return $gff;
    }

    sub _gff_source {
        return 'variation';
    }
}

{
    
    package Bio::EnsEMBL::RepeatFeature;
    
    sub _gff_hash {
        my ($self, @args) = @_;
        my $gff  = $self->SUPER::_gff_hash(@args);
        
        if ($self->analysis->logic_name =~ /RepeatMasker/i) {
            my $class = $self->repeat_consensus->repeat_class;
        
            if ($class =~ /LINE/) {
                $gff->{source} .= '_LINE'; 
            }
            elsif ($class =~ /SINE/) {
                $gff->{source} .= '_SINE';
            }
            
            $gff->{feature} = 'similarity';
            $gff->{score} = $self->score;
            
            $gff->{attributes}->{Class} = qq("Motif");
            $gff->{attributes}->{Name} = '"'.$self->repeat_consensus->name.'"';
            $gff->{attributes}->{Align} = $self->hstart.' '.$self->hend.' '.($self->hstrand == -1 ? '-' : '+');
        }
        elsif ($self->analysis->logic_name =~ /trf/i) {
            $gff->{feature} = 'misc_feature';
            $gff->{score} = $self->score;
            my $cons = $self->repeat_consensus->repeat_consensus;
            my $len = length($cons);
            my $copies = sprintf "%.1f", ($self->end - $self->start + 1) / $len;
            $gff->{attributes}->{Name}  = qq("$copies copies $len mer $cons");
        }
        
        return $gff;
    }
}

{
    
    package Bio::EnsEMBL::Map::DitagFeature;
    
    sub to_gff {
        my ($self, @args) = @_;
        
        my ($start, $end, $hstart, $hend, $cigar_string);
        
        if($self->ditag_side eq "F"){
            $start = $self->start;
            $end   = $self->end;
            $hstart = $self->hit_start;
            $hend = $self->hit_end;
            $cigar_string = $self->cigar_line;
        }
        elsif ($self->ditag_side eq "L") {
            
            # we only return some GFF for L side ditags, as the R side one will be included here 
            
            my ($df1, $df2);
            eval {
                ($df1, $df2) = @{$self->adaptor->fetch_all_by_ditagID(
                    $self->ditag_id,
                    $self->ditag_pair_id,
                    $self->analysis->dbID
                )};
            };
            
            if ($@ || !defined($df1) || !defined($df2)) {
                die "Failed to find matching ditag pair: $@";
            }
            
            die "Mismatching strands on in a ditag feature pair" unless $df1->strand == $df2->strand;
            
            ($df1, $df2) = ($df2, $df1) if $df1->start > $df2->start;
            
            $start = $df1->start;
            $end = $df2->end;
            my $fw = $df1->strand == 1;
            $hstart = $fw ? $df1->hit_start : $df2->hit_start;
            $hend = $fw ? $df2->hit_end : $df1->hit_end;
            
            my $insert = $df2->start - $df1->end - 1;
            
            # XXX: gr5: this generates GFF slightly differently from the ace server for 
            # instances where the hit_end of df1 and the hit_start of df2 are the same
            # e.g. 1-19, 19-37, which seems to occur fairly often. I don't really know
            # what this means (do the pair share a base of the alignment?), but I do not
            # cope with it here, and the GFF will show that such a pair have hit coords
            # 1-19, 20-38. The coords on the genomic sequence will be correct though.
            
            $cigar_string = $df1->cigar_line.$insert.'I'.$df2->cigar_line;
            
            
        }
        else {
            
            # we are the R side ditag feature and we don't generate anything
            
            return '';
        }
        
        # fake up a DAF which we then convert to GFF as this is the format produced by acedb
        
        my $daf = Bio::EnsEMBL::DnaDnaAlignFeature->new(
            -slice        => $self->slice,
            -start        => $start - $self->slice->start + 1,
            -end          => $end - $self->slice->start + 1,
            -strand       => $self->strand,
            -hseqname     => $self->ditag->type.':'.$self->ditag->name,
            -hstart       => $hstart,
            -hend         => $hend,
            -hstrand      => $self->hit_strand,
            -analysis     => $self->analysis,
            -cigar_string => $cigar_string,
        );
        
        return $daf->to_gff(@args);
    }
    
#    sub _gff_hash {
#        
#        my $self = shift;
#        my $gff  = $self->SUPER::_gff_hash(@_);
#        
#        $gff->{feature} = 'similarity';
#        
#        $gff->{attributes}->{Class} = qq("Sequence");
#        $gff->{attributes}->{Name} = '"'.$self->ditag->type.':'.$self->ditag->name.'"';
#        $gff->{attributes}->{Align} = $self->hit_start.' '.$self->hit_end.' '.( $self->hit_strand == -1 ? '-' : '+' );
#        
#        return $gff;
#    }

}

{

    package Bio::Otter::DnaDnaAlignFeature;

    sub _gff_hash {
        my ($self, @args) = @_;
        my $gff  = $self->SUPER::_gff_hash(@args);
        $gff->{attributes}->{Length} = $self->get_HitDescription->hit_length;
        #$gff->{attributes}->{Note} = '"'.$self->get_HitDescription->description.'"';
        return $gff;
    }
}

{

    package Bio::Otter::DnaPepAlignFeature;

    sub _gff_hash {
        my ($self, @args) = @_;
        my $gff  = $self->SUPER::_gff_hash(@args);
        $gff->{attributes}->{Length} = $self->get_HitDescription->hit_length;
        #$gff->{attributes}->{Note} = '"'.$self->get_HitDescription->description.'"';
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

