### Bio::Vega::Utils::EnsEMBL2GFF

package Bio::Vega::Utils::EnsEMBL2GFF;

use strict;
use warnings;

# This module allows conversion of ensembl/otter objects to GFF by inserting
# _gff_hash and to_gff methods into the necessary feature classes

sub gff_header {
	
	# create a generic GFF header in the format expected by ZMap
	
	my $slice = shift;
	
	my $include_dna = shift;
	
	# build up a date string in the format specified by the GFF spec
	
	my ( $sec, $min, $hr, $mday, $mon, $year ) = localtime;
	$year += 1900;    # correct the year
	$mon++;           # months start at 0
	my $date = "$year-$mon-$mday";

	my $hdr = 
		  "##gff-version 2\n"
		. "##source-version EnsEMBL2GFF 1.0\n"
		. "##date $date\n"
		. "##sequence-region "
		. $slice->seq_region_name . " "
		. $slice->start . " "
		. $slice->end . "\n";
		
	if ($include_dna) {	
		$hdr .=
			  "##DNA\n"
			. "##".$slice->seq."\n"
			. "##end-DNA\n";
	}
		
	return $hdr;
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
		
		#$gff->{strand} = '-' if ($self->hstrand == -1);
		#$gff->{attributes}->{Target} = '"Sequence:'.$self->hseqname.'" '.$self->hstart.' '.$self->hend;
		
		$gff->{attributes}->{Target} = '"Sequence:'.$self->hseqname.'" '.
			($self->hstrand == -1 ? $self->hend : $self->hstart).' '.
			($self->hstrand == -1 ? $self->hstart : $self->hend);
		
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
					'CDS',
					$tsct->coding_region_start,
					$tsct->coding_region_end,
					'.', # score
					$tsct->_gff_hash->{strand},
					'0', # strand - not really sure what we should put here, but giface always seems to use 0, so we will too!
					'Sequence '.$tsct->_gff_hash->{attributes}->{Sequence}
				);
			}
			
			# add gff lines for each of the introns and exons
			for my $feat (@{ $tsct->get_all_Exons }, @{ $tsct->get_all_Introns }) {
				
				# exons and introns don't have analyses attached, so give them the transcript's one
				$feat->analysis($tsct->analysis);
				
				# and add the features gff line to our string, appending the sequence information
				$gff .= "\n".$feat->to_gff . "\tSequence ".'"'.$tsct->display_id.'"';
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

