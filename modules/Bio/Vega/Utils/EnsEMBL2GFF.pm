### Bio::Vega::Utils::EnsEMBL2GFF

package Bio::Vega::Utils::EnsEMBL2GFF;

use strict;
use warnings;

# This module allows conversion of ensembl/otter objects to GFF by inserting
# to_gff (and supporting _gff_hash) methods into the necessary feature classes

{
	package Bio::EnsEMBL::Slice;
	
	sub gff_header {
		
		my $self = shift;
		my %args = @_;
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
			$hdr .=
				  "##DNA\n"
				. "##".$self->seq."\n"
				. "##end-DNA\n";
		}
		
		return $hdr;
	}
	
	sub to_gff {
		
		my $self = shift;
		
		my %args = @_;
		
		my $include_header 	= $args{include_header};
		my $include_dna 	= $args{include_dna};
		my $feature_types	= $args{feature_types};
		my $analyses 		= $args{analyses};
		my $verbose			= $args{verbose};
		
		my $sources_to_types =	$args{sources_to_types};
		
		my $gff = $include_header ? $self->gff_header(include_dna => $include_dna) : '';
		
		# grab features of each type we're interested in
			
		for my $feature_type (@$feature_types) {
			
			my $method = 'get_all_'.$feature_type;
			
			unless ($self->can($method)) {
				warn "There is no method to retrieve $feature_type from a slice";
				next; 
			}
			
			for my $analysis (@$analyses) {
				
				my $features = $self->$method($analysis);
				
				if ($verbose && scalar(@$features)) {
					print "Found ".scalar(@$features)." $feature_type from $analysis on slice ".$self->seq_region_name."\n";
				}
				
				for my $feature (@$features) {
					
					if ( $feature->can('to_gff') ) {
						
						$gff .= $feature->to_gff . "\n";

						if ($sources_to_types) {
							
							# If we are passed a sources_to_types hashref, then as we identify the types of 
							# features each analysis can create, fill in the hash for the caller. This is
							# required by enzembl, but other users can just ignore this parameter.
							
							my $source = $feature->_gff_hash->{source};
						
							if ($sources_to_types->{$source}) {
								unless ($sources_to_types->{$source} eq $feature_type) {
									die "Can't have multiple gff sources from one analysis:\n".
										"('$analysis' seems to have both '".$sources_to_types->{$source}.
										"' and '$feature_type')\n";
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
	
		my $gff = $self->_gff_hash;
		
		$gff->{score} 	= '.' unless defined $gff->{score};
		$gff->{strand} 	= '.' unless defined $gff->{strand};
		$gff->{frame} 	= '.' unless defined $gff->{frame};
		
		# order as per GFF spec: http://www.sanger.ac.uk/Software/formats/GFF/GFF_Spec.shtml
		
		my $gff_str = join("\t",
			$gff->{seqname},
			$gff->{source},
			$gff->{feature},
			$gff->{start},
			$gff->{end},
			$gff->{score},
			$gff->{strand},
			$gff->{frame},
		);
		
		if ($gff->{attributes}) {
			my @attrs = map { $_.' '.$gff->{attributes}->{$_} } keys %{ $gff->{attributes} };
			$gff_str .= "\t".join("\t;\t", @attrs);
		}
		
		return $gff_str;
	}
	
	sub _gff_hash {
		my $self = shift;

		my %gff = (
			seqname	=> $self->slice->seq_region_name,
			source	=> ($self->analysis->gff_source || $self->analysis->logic_name),
			feature	=> ($self->analysis->gff_feature || 'misc_feature'),
			start	=> $self->start,
			end		=> $self->end,
			strand	=> ( $self->strand == 1 ? '+' : ($self->strand == -1 ? '-' : '.' ))
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
		$gff->{score} = $self->score;
		$gff->{feature} = 'misc_feature';
	
		if ($self->display_label) {
			$gff->{attributes}->{Note} = '"'.$self->display_label.'"';
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
			my @gaps = map { join( ' ', $_->hstart, $_->hend, $_->start, $_->end ) } @fps;
			$gap_string = join( ',', @gaps );
		}
	
		my $gff = $self->SUPER::_gff_hash;
		
		$gff->{score} = $self->score;
		$gff->{feature}	= $self->analysis->gff_feature || 'similarity';
		
		$gff->{attributes}->{Target} = '"Sequence:'.$self->hseqname.'" '.
			($self->hstrand == -1 ? 
				$self->hend.' '.$self->hstart : 
				$self->hstart.' '.$self->hend);
		
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
		
		my $gff = '';	
	
		for my $tsct (@{ $self->get_all_Transcripts }) {
			
			$gff .= "\n" if $gff;
			
			# add a line for each transcript, appending the locus information
			$gff .= $tsct->to_gff. "\t;\tLocus ".'"'.$self->display_id.'"';
			
			if (defined $tsct->coding_region_start) {
			
				# build up the CDS line (unfortunately there's not really an object we can hang this off
				# so we have to build the whole line ourselves)
				$gff .= "\n".join("\t",
					$tsct->_gff_hash->{seqname},
					$tsct->_gff_hash->{source},
					'CDS', # feature
					$tsct->coding_region_start,
					$tsct->coding_region_end,
					'.', # score
					$tsct->_gff_hash->{strand},
					'0', # frame - not really sure what we should put here, but giface always seems to use 0, so we will too!
					'Sequence '.$tsct->_gff_hash->{attributes}->{Sequence}
				);
			}
			
			# add gff lines for each of the introns and exons
			for my $feat (@{ $tsct->get_all_Exons }, @{ $tsct->get_all_Introns }) {
				
				# exons and introns don't have analyses attached, so give them the transcript's one
				$feat->analysis($tsct->analysis);
				
				# and add the feature's gff line to our string, appending the sequence information
				$gff .= "\n".$feat->to_gff . "\tSequence ".'"'.$tsct->display_id.'"';
				
				# to be on the safe side, get rid of the analysis we temporarily attached 
				# (someone might rely on there not being one later)
				$feat->analysis(undef);
			}
		}
	
		return $gff;
	}
}

{
	package Bio::EnsEMBL::Transcript;
	
	sub _gff_hash {
		my $self = shift;
		my $gff = $self->SUPER::_gff_hash;
		$gff->{feature} = 'Sequence';
		$gff->{attributes}->{Sequence} = '"'.$self->display_id.'"';
		return $gff;
	}
}

{
	package Bio::EnsEMBL::Exon;
	
	sub _gff_hash {
		my $self = shift;
		my $gff = $self->SUPER::_gff_hash;
		$gff->{feature} = 'exon';
		return $gff;
	}
}

{
	package Bio::EnsEMBL::Intron;
	
	sub _gff_hash {
		my $self = shift;
		my $gff = $self->SUPER::_gff_hash;
		$gff->{feature} = 'intron';
		return $gff;
	}
}

{
	package Bio::Otter::DnaDnaAlignFeature;
	
	sub _gff_hash {
		my $self = shift;

		my $gff = $self->SUPER::_gff_hash;
	
		$gff->{attributes}->{Length} = $self->get_HitDescription->hit_length;
	
		return $gff;
	}
}

1;

__END__
	
=head1 NAME - Bio::Vega::Utils::EnsEMBL2GFF 

=head1 SYNOPSIS

Inserts _gff_hash and to_gff methods into various EnsEMBL and Otter classes, allowing
them to be converted to GFF by calling C<$object->to_gff>.

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk

