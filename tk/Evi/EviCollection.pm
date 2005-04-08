package Evi::EviCollection;

# A factory for EviChains.
#
# Collects the ESTs/mRNAs/proteins that match the genomic sequence in a certain slice,
# combines them into matching chains and returns as a list of EviChain objects.
#
# lg4, 7.Apr'2005

use strict;
use Evi::EviChain;
use Evi::Taxonamer;

sub new {
	my $pkg = shift @_;

	my $self = bless {}, $pkg;

	$self->otter_slice(shift @_);
	$self->rna_analyses_lp(shift @_);
	$self->protein_analyses_lp(shift @_);

	my $otter_dba = $self->otter_slice()->adaptor()->db();

    # my $pipe_dba  = Bio::Otter::Lace::PipelineDB::get_DBAdaptor($otter_dba);
    my $pipe_dba  = Bio::Otter::Lace::PipelineDB::get_rw_DBAdaptor($otter_dba);
	$pipe_dba->assembly_type($otter_dba->assembly_type());

	my $pipe_slice = $pipe_dba->get_SliceAdaptor()->fetch_by_chr_start_end(
			$self->otter_slice()->chr_name(),
			$self->otter_slice()->chr_start(),
			$self->otter_slice()->chr_end());

	$self->{_collection} = [];	# whole list of chains
	$self->{_name2chains} = {}; # sublists of chains indexed by name

	my $daf_adaptor = $pipe_dba->get_DnaAlignFeatureAdaptor();
	for my $analysis (@{$self->rna_analyses_lp()}) {
		my $dafs_lp = $daf_adaptor->fetch_all_by_Slice($pipe_slice,$analysis);
		print STDERR "[$analysis] ";
		$self->add_collection($dafs_lp);
	}

	my $paf_adaptor = $pipe_dba->get_ProteinAlignFeatureAdaptor();
	for my $analysis (@{$self->protein_analyses_lp()}) {
		my $pafs_lp = $paf_adaptor->fetch_all_by_Slice($pipe_slice,$analysis);
		print STDERR "[$analysis] ";
		$self->add_collection($pafs_lp);
	}
	print STDERR "\n";

	return $self;
}

sub otter_slice {
	my $self = shift @_;

	if(@_) {
		$self->{_otter_slice} = shift @_;
	}
	return $self->{_otter_slice};
}

sub rna_analyses_lp {
	my $self = shift @_;

	if(@_) {
		$self->{_rna_analyses_lp} = shift @_;
	}
	return $self->{_rna_analyses_lp};
}

sub protein_analyses_lp {
	my $self = shift @_;

	if(@_) {
		$self->{_protein_analyses_lp} = shift @_;
	}
	return $self->{_protein_analyses_lp};
}

sub get_all_matches {
	my $self = shift @_;

	return $self->{_collection};
}

sub get_all_matches_by_name {
	my $self = shift @_;
	my $name = shift @_;

	return $self->{_name2chains}{$name};
}

sub find_intersecting_matches {
	my ($self, $transcript) = @_;

	return [
		grep {	$transcript->start()<=$_->end()
			and $_->start()<=$transcript->end() }
		@{ $self->get_all_matches() }
	];
}

sub add_collection {
	my $self = shift @_;

	my @afs = @{ shift @_ };

	my %match_by_eviname = ();
	my %unique_match = ();

		# group the *unique* matches by the EST/mRNA name [and the strand]:
	foreach my $af (@afs) {
		my $hseqname    = $af->hseqname();
		my $hstrand     = $af->hstrand();

		my $keyline	= $hseqname;
		my $start       = $af->start();
		my $end         = $af->end();
		my $hstart      = $af->hstart();
		my $hend        = $af->hend();

			# certain things just get duplicated (quadruplicated) in the database,
			# let's get rid of the redundant copies:
		if(! $unique_match{$start,$end,$hstart,$hend}++) {
			push @{$match_by_eviname{$keyline}}, $af;
		}
	}

	my @candidates = ();

		# within these groups...
	for my $keyline (keys %match_by_eviname) {

		my @order = sort {$a->start() <=> $b->start() }
				@{$match_by_eviname{$keyline}};

		my %next = ();  # HoL (the digraph adjacency hash/array)
		my %pointed_at_count = ();  # HoCounts
		my @seen = ();  # list of object ptrs

			# build the digraph:
		for my $curr (reverse @order) { # start moving upstream in contig coordinates
			for my $prev (@seen) { # check all previously seen matches
				if( ($curr->end() < $prev->start())
				 && _joinable($curr,$prev) ) {
					push @{$next{$curr}}, $prev;
					$pointed_at_count{$prev}++;
				}
			}
			push @seen, $curr;
		}

			# trace the graph and create EviChain objects:
		for my $start (@order) {
			if(! $pointed_at_count{$start}) { # if it's a start of a chain
				push @candidates, _tracechains($start,\%next,());
			}
		}
	}

	for my $evichain (@candidates) {
		if(1) {  # (any global filters for candidates should appear here)
			push @{$self->{_collection}}, $evichain; # put it on the global list
			push @{$self->{_name2chains}{$evichain->name()}}, $evichain; # add it to by-name index
			Evi::Taxonamer::put_id($evichain->taxon_id());
		}
	}

}

sub _tracechains {	# not a method
        my $curr   = shift @_;
        my $nextp  = shift @_;
        my @prefix = @_;        # collected _before_ $curr

        push @prefix, $curr;

        if(exists($nextp->{$curr})) {     # this node has children
            my @results = (); # full-length chains
            for my $child (@{$nextp->{$curr}}) {
               push @results, _tracechains($child,$nextp,@prefix);
            }
            return @results;
        } else {
			return Evi::EviChain->new('afs' => \@prefix);
        }
}

sub _joinable {		# not a method
        my ($c_ups,$c_downs) = @_;      # DnaAlignFeatures in contig coordinate system

        if($c_ups->hstrand()*$c_downs->hstrand() == -1) {       # different strands
                return 0;
        } elsif($c_ups->hstrand() == 1) { # forward strand
                return (($c_downs->hstart() - $c_ups->hend()) == 1);
        } else { # reverse strand
                return (($c_ups->hstart() - $c_downs->hend()) == 1);
        }
}

1;

