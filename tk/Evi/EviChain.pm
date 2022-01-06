=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Evi::EviChain;

# a chain of evidence matches (DnaAlignFeatures) with the same name
# in some slice's coordinates (the slice is fixed, but not known to the EviChain)
#
# lg4

use List::Util qw(min max);

use Evi::Taxonamer;

sub new {
	my $pkg = shift @_;

	my $self = bless {}, $pkg;

	if(@_) {
		my %param = @_;
		for my $k (keys %param) {
			$self->{"_$k"} = $param{$k};
		}
	}
	return $self;
}

sub afs_lp {	# a list pointer
	my $self = shift @_;

	if(@_) {
		$self->{_afs} = shift @_;
	}
	return $self->{_afs} || [()];
}

sub get_first_exon {
	my $self = shift @_;

	return $self->{_afs}->[0] || die "$self->name() has no exons defined";
}

sub get_last_exon {
	my $self = shift @_;

	return $self->{_afs}->[scalar(@{$self->{_afs}})-1]
		|| die "$self->name() has no exons defined";
}

sub eviseq_length {	# the length of the evidence sequence (EST|mRNA)
	my $self = shift @_;

	return $self->get_first_exon()->get_HitDescription()->hit_length();
}

sub taxon_id {
	my $self = shift @_;

	return $self->get_first_exon()->get_HitDescription()->taxon_id();
}

sub taxon_name {
	my $self = shift @_;

	return Evi::Taxonamer::get_name($self->taxon_id());
}

sub db_name {
	my $self = shift @_;

	return $self->get_first_exon()->get_HitDescription()->db_name();
}

sub name {
	my $self = shift @_;

	return $self->get_first_exon()->hseqname();
}

my %db2prefix = (
	EMBL        => 'Em:',
	SwissProt   => 'Sw:',
	TrEMBL      => 'Tr:',
);

sub prefixed_name {
	my $self = shift @_;

	return $db2prefix{$self->db_name()}.$self->name();
}

my %db2unit = (
    EMBL        => 1,
    SwissProt   => 3,
    TrEMBL      => 3,
);

sub unit {
    my $self = shift @_;

    return $db2unit{$self->db_name()};
}

sub analysis {
	my $self = shift @_;

	return $self->get_first_exon()->analysis()->logic_name() || 'unknown';
}

my %analysis2type = (
	'vertrna' =>			'cDNA',
	'Est2genome_human' => 	'EST',
	'Est2genome_mouse' =>	'EST',
	'Est2genome_other' =>	'EST',
	'Uniprot' =>			'Protein',
);

sub evitype {
	my $self = shift @_;

	return $analysis2type{$self->analysis()} || 'unknown';
}

sub start {	# in slice coordinates
	my $self = shift @_;

	return $self->get_first_exon()->start();
}

sub end { # in slice coordinates
	my $self = shift @_;

	return $self->get_last_exon()->end();
}

sub hstrand {
	my $self = shift @_;

	return $self->get_first_exon()->hstrand();
}

sub strand {
	my $self = shift @_;

	return $self->get_first_exon()->strand();
}

sub min_percent_id {	# cached, not to be set
	my $self = shift @_;

	if($self->{_min_percent_id}) {
		return $self->{_min_percent_id};
	} elsif($self->afs_lp()) {
		my $minperc = 100;
		for my $af (@{$self->afs_lp()}) {
			if($af->percent_id() < $minperc) {
				$minperc = $af->percent_id();
			}
		}
		
		return ($self->{_min_percent_id} = $minperc);
	} else {
		return 0;
	}
}

sub match_lengths { # returns (upstream_unmatched,matched,downstream_unmatched,eviseq_length)
	my $self = shift @_;

	my $eviseq_len = $self->eviseq_length();

	my ($ups_len,$dns_len);
	if($self->hstrand() == 1) {
		$ups_len = $self->get_first_exon()->hstart() - 1;
		$dns_len = $eviseq_len - $self->get_last_exon()->hend();
	} else {
		$ups_len = $eviseq_len - $self->get_first_exon()->hend();
		$dns_len = $self->get_last_exon()->hstart() - 1;
	}
	my $match_len = $eviseq_len-($ups_len+$dns_len);

	return ($ups_len, $match_len, $dns_len, $eviseq_len);
}

sub eviseq_coverage {
	my $self = shift @_;

	if(!exists($self->{_eviseq_coverage})) {
		my ($ups_len, $match_len, $dns_len, $eviseq_len) = $self->match_lengths();

		$self->{_eviseq_coverage} = roundto(
			($eviseq_len-($ups_len+$dns_len))*100/$eviseq_len,
			0.01
		);
	}
	return $self->{_eviseq_coverage};
}

sub roundto {
	my ($number,$precision) = @_;

	return int($number/$precision)*$precision;
}

sub intersect2exons { # NB: not a method
	my ($exon1,$exon2) = @_;

	return max(0,
		  min( $exon1->end(), $exon2->end() )
		- max( $exon1->start(), $exon2->start() )
		+ 1
	);
}

sub supported_length {
	my ($self, $transcript) = @_;

	if(! exists($self->{_supported_length}{$transcript})) {
		$self->{_supported_length}{$transcript} = 0;
		for my $trans_exon (@{ $transcript->get_all_Exons() }) {
			for my $af (@{ $self->afs_lp() }) {
				$self->{_supported_length}{$transcript} += intersect2exons($trans_exon,$af);
			}
		}
	}
	return $self->{_supported_length}{$transcript};
}

sub transcript_coverage {
	my ($self, $transcript) = @_;

	return roundto(
		$self->supported_length($transcript)*100/$transcript->length(),
		0.01
	);
}

sub contrasupported_length { # a part of matched part of EST/mRNA length
	my ($self, $transcript) = @_;

	my ($ups_len, $match_len, $dns_len, $eviseq_len) = $self->match_lengths();

	return    $match_len
			- $self->supported_length($transcript);
}

sub junctions_hp {	# a pointer to the hash of splice junctions
	my $self = shift @_;

	if($self->{_junctions}) {
		return $self->{_junctions};
	} elsif($self->afs_lp()) {
		$self->{_junctions} = {
			map { ($_->start() => 1, $_->end() => 1); }
			    (@{ $self->afs_lp()})
		};
		return $self->{_junctions};
	} else {
		return {()};
	}
}

sub trans_supported_junctions {
	my ($self, $transcript) = @_;

	if(! exists($self->{_tsj}->{$transcript})) {

		$self->{_tsj}->{$transcript} = 0;
		for my $exon (@{ $transcript->get_all_Exons()}) {
			if($self->junctions_hp()->{$exon->start()}) {
				$self->{_tsj}->{$transcript}++;
			}
			if($self->junctions_hp()->{$exon->end()}) {
				$self->{_tsj}->{$transcript}++;
			}
		}
	}
	return $self->{_tsj}->{$transcript};
}

sub introns_hp {	# a pointer to the hash of "intron_start:intron_end"
	my $self = shift @_;

	if($self->{_introns}) {
		return $self->{_introns};
	} elsif($self->afs_lp()) {
		$self->{_introns} = {};
		my @pairs = map { ($_->start(), $_->end()); }
			        (@{ $self->afs_lp()});
		pop @pairs; shift @pairs;
		while (@pairs) {
			my $start = shift @pairs;
			my $end   = shift @pairs;
			$self->{_introns}->{"$start:$end"}=1;
		}
		return $self->{_introns};
	} else {
		return {()};
	}
}

sub trans_supported_introns {
	my ($self, $transcript) = @_;

	if(! exists($self->{_tsi}->{$transcript})) {

		$self->{_tsi}->{$transcript} = 0;
		my @pairs = sort {$a <=> $b}
				map { ($_->start(), $_->end()); }
				(@{ $transcript->get_all_Exons()});
		pop @pairs; shift @pairs;
		while (@pairs) {
			my $start = shift @pairs;
			my $end   = shift @pairs;
			if($self->introns_hp()->{"$start:$end"}) {
				$self->{_tsi}->{$transcript}++;
			}
		}
	}
	return $self->{_tsi}->{$transcript};
}

sub _af2string {	# not-a-method:
	my $af = shift @_;

        my $hstrand     = $af->hstrand();
        my $hstart      = $af->hstart();
        my $hend        = $af->hend();

        my $start       = $af->start();
        my $end         = $af->end();
	my $percent_id  = $af->percent_id();

	return ($hstrand == 1)
		? "[$hstart-$hend]/".($hend-$hstart+1)." ($start ==> $end)/".($end-$start+1)." ${percent_id}%"
		: "[$hend-$hstart]/".($hstart-$hend+1)." ($start <== $end)/".($start-$end+1)." ${percent_id}%"
}

sub toString {	# multistring text, actually
	my $self = shift @_;
	my $transcript = shift @_ || 0;

	return '['.$self->eviseq_length().'] '
		.$self->prefixed_name().':'
		. ($transcript
			? (' supp_introns='.$self->trans_supported_introns($transcript)
			  .' supp_junctions='.$self->trans_supported_junctions($transcript)
			)
			: '')
		.'  eviseq_coverage='.$self->eviseq_coverage()
		.'  min_percent_id='.$self->min_percent_id()
		."\n"
		.join('',map {"\t"._af2string($_)."\n"} @{$self->afs_lp()});
}

1;
