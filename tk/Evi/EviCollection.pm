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

package Evi::EviCollection;

# A factory for EviChains.
#
# Collects the ESTs/mRNAs/proteins that match the genomic sequence in a certain slice,
# combines them into matching chains and returns as a list of EviChain objects.

use strict;
use Evi::EviChain;
use Evi::Taxonamer;

use base ('Tk::DestroyReporter'); # we want to track the destruction event

sub otter_to_pipeline { # class method
    my $otter_slice = shift @_;

    my $otter_dba = $otter_slice->adaptor()->db();

        # connect to slave:
    my $pipeline_dba = Bio::Otter::Lace::PipelineDB::get_DBAdaptor($otter_dba);

    #   # connect to master: [for debug purposes]
    # my $pipeline_dba  = Bio::Otter::Lace::PipelineDB::get_rw_DBAdaptor($otter_dba);

    my $pipeline_slice = $pipeline_dba->get_SliceAdaptor()->fetch_by_chr_start_end(
            $otter_slice->chr_name(),
            $otter_slice->chr_start(),
            $otter_slice->chr_end()
    );

    return ($pipeline_dba, $pipeline_slice);
}

sub new_from_otter_Slice {
    my ($pkg, $otter_slice, $rna_analyses_lp, $protein_analyses_lp) = @_;

    my ($pipeline_dba, $pipeline_slice) = otter_to_pipeline($otter_slice);

    return $pkg->new_from_pipeline_Slice(
        $pipeline_dba,
        $pipeline_slice,
        $rna_analyses_lp, $protein_analyses_lp
    );
}

sub new_from_pipeline_Slice {
    my $pkg = shift @_;

    my $self = bless {}, $pkg;

    $self->pipeline_dba(shift @_);
    $self->pipeline_slice(shift @_);
    $self->rna_analyses_lp(shift @_);
    $self->protein_analyses_lp(shift @_);

    $self->{_collection} = {};  # hash{by_analysis} of lists of chains
    $self->{_name2chains} = {}; # sublists of chains indexed by name

    my $daf_adaptor = $self->pipeline_dba()->get_DnaAlignFeatureAdaptor();
    for my $analysis_name (@{$self->rna_analyses_lp()}) {
        my $dafs_lp = $daf_adaptor->fetch_all_by_Slice($self->pipeline_slice(),$analysis_name);
        $self->add_collection($dafs_lp, $analysis_name);
    }

    my $paf_adaptor = $self->pipeline_dba()->get_ProteinAlignFeatureAdaptor();
    for my $analysis_name (@{$self->protein_analyses_lp()}) {
        my $pafs_lp = $paf_adaptor->fetch_all_by_Slice($self->pipeline_slice(),$analysis_name);
        $self->add_collection($pafs_lp, $analysis_name);
    }
    print STDERR "\n";

    Evi::Taxonamer::fetch();

    return $self;
}

sub new_from_client_dataset_otterslice {
    my $pkg = shift @_;

    my $self = bless {}, $pkg;

    my $client      = shift @_;
    my $dataset     = shift @_; # e.g. 'human', 'mouse', etc
    my $otter_slice = shift @_; # contains assembly_type=set_name, chr_name, chr_start & chr_end

    my ($pipeline_dba, $pipeline_slice) = otter_to_pipeline($otter_slice);
    $self->pipeline_dba($pipeline_dba);
    $self->pipeline_slice($pipeline_slice);

    $self->rna_analyses_lp(shift @_);
    $self->protein_analyses_lp(shift @_);
    my $enshead     = shift @_ || 0;
    
    $self->{_collection} = {};  # hash{by_analysis} of lists of chains
    $self->{_name2chains} = {}; # sublists of chains indexed by name

    for my $analysis_name (@{$self->rna_analyses_lp()}) {
        my $dafs_lp = $client->get_dafs_from_dataset_sliceargs_analysis(
            $dataset,
            $otter_slice,
            $analysis_name,
            $enshead,
        );
        $self->add_collection($dafs_lp, $analysis_name);
    }
    for my $analysis_name (@{$self->protein_analyses_lp()}) {
        my $pafs_lp = $client->get_pafs_from_dataset_sliceargs_analysis(
            $dataset,
            $otter_slice,
            $analysis_name,
            $enshead,
        );
        $self->add_collection($pafs_lp, $analysis_name);
    }
    print STDERR "\n";

    Evi::Taxonamer::fetch();

    return $self;
}

sub pipeline_dba {
    my $self = shift @_;

    if(@_) {
        $self->{_pipeline_dba} = shift @_;
    }
    return $self->{_pipeline_dba};
}

sub pipeline_slice {
    my $self = shift @_;

    if(@_) {
        $self->{_pipeline_slice} = shift @_;
    }
    return $self->{_pipeline_slice};
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

    my @total = ();
    for my $analysis_name (@{$self->rna_analyses_lp()},@{$self->protein_analyses_lp()}) {
        push @total, @{$self->get_all_matches_by_analysis($analysis_name)}
    }
    return \@total;
}

sub get_all_matches_by_analysis {
    my $self          = shift @_;
    my $analysis_name = shift @_;

    return $self->{_collection}{$analysis_name};
}

sub get_all_matches_by_name {
    my $self = shift @_;
    my $name = shift @_;

    if(not $self->{_name2chains}{$name}) {
        warn "EviCollection: where did you get '$name' from???\n";
        warn "EviCollection: Certainly not from me!!!\n";
    }

    return $self->{_name2chains}{$name};
}

sub add_collection {
    my $self            = shift @_;
    my @separate_afs    = @{ shift @_ };
    my $analysis_name   = shift @_;

    my $strict_chains   = $analysis_name ne 'Uniprot';

    my %match_by_eviname = ();
    my %unique_match = ();

        # group the *unique* matches by the EST/mRNA name [and the strand]:
    foreach my $af (@separate_afs) {
        my $hseqname    = $af->hseqname();
        my $hstrand     = $af->hstrand();
        my $strand      = $af->strand();

        my $keyline     = $hseqname.':'.$strand.':'.$hstrand;

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

            # build the digraph:
        for my $curr_ind (reverse (0..@order-1)) { # start moving upstream in contig coordinates
            my $curr = $order[$curr_ind];

            for my $prev (@order[$curr_ind+1..@order-1]) { # check all previously connected matches

                if( ($curr->end() < $prev->start())
                 && ( $strict_chains ?  _joinable($curr,$prev) : (!$pointed_at_count{$prev}) )
                ) {
                    push @{$next{$curr}}, $prev;
                    $pointed_at_count{$prev}++;
                }
            }
        }

            # trace the graph and create EviChain objects:
        for my $start (@order) {
            if(! $pointed_at_count{$start}) { # if it's a start of a chain
                push @candidates, _tracechains($start,\%next,());
            }
        }
    }

    my $counter = 0;
    print STDERR "[$analysis_name...";
    for my $evichain (@candidates) {
        if($evichain->get_first_exon()->can('get_HitDescription')) {
            push @{$self->{_collection}{$analysis_name}}, $evichain; # put it on the global list
            push @{$self->{_name2chains}{$evichain->name()}}, $evichain; # add it to by-name index
            Evi::Taxonamer::put_id($evichain->taxon_id());
            $counter++;
        } else {
            warn "EviColleciton: ".$evichain->name()." does not have a hit_Description(), ignoring.";
        }
    }
    print STDERR ''.($counter ? $counter : 'EMPTY').']';
}

sub _tracechains {  # not a method
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

sub _joinable {     # not a method
    my ($c_ups,$c_downs) = @_;      # DnaXXXAlignFeatures in contig coordinate system

    if($c_ups->hstrand()*$c_downs->hstrand() == -1) {       # different strands
            return 0;
    } elsif($c_ups->hstrand() == 1) { # forward strand
            return (($c_downs->hstart() - $c_ups->hend()) == 1);
    } else { # reverse strand
            return (($c_ups->hstart() - $c_downs->hend()) == 1);
    }
}

1;

