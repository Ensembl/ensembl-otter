
### Bio::Otter::Lace::SequenceSet

package Bio::Otter::Lace::SequenceSet;

use strict;
use warnings;
use Carp;

sub new {
    my $pkg = shift;

    return bless {}, $pkg;
}

sub name {
    my ($self, $name) = @_;

    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub dataset_name {
    my ($self, $dataset_name) = @_;

    if ($dataset_name) {
        $self->{'_dataset_name'} = $dataset_name;
    }
    return $self->{'_dataset_name'};
}

sub coord_system_name {
    my ($self, $coord_system_name) = @_;

    if ($coord_system_name) {
        $self->{'_coord_system_name'} = $coord_system_name;
    }
    return $self->{'_coord_system_name'};
}

sub coord_system_version {
    my ($self, $coord_system_version) = @_;

    if ($coord_system_version) {
        $self->{'_coord_system_version'} = $coord_system_version;
    }
    return $self->{'_coord_system_version'};
}

sub description {
    my ($self, $description) = @_;

    if ($description) {
        $self->{'_description'} = $description;
    }
    return $self->{'_description'};
}

sub priority {
    my ($self, $priority) = @_;

    if ($priority) {
        $self->{'_priority'} = $priority;
    }
    return $self->{'_priority'};
}

sub is_hidden {
    my ($self, $is_hidden) = @_;

    if (defined $is_hidden) {
        $self->{'_is_hidden'} = $is_hidden ? 1 : 0;
    }
    return $self->{'_is_hidden'};
}

sub vega_set_id {
    my ($self, $vega_set_id) = @_;

    if ($vega_set_id) {
        die "Expected INT for vega_set_id, but got: '$vega_set_id'"
            unless $vega_set_id =~ /^\d+$/;
        $self->{'_vega_set_id'} = $vega_set_id;
    }
    return $self->{'_vega_set_id'} || 0;
}

sub write_access {
    my ($self, $write_access) = @_;

    if (defined $write_access) {
        $self->{'_write_access'} = $write_access ? 1 : 0;
    }
    $write_access = $self->{'_write_access'};

    return defined($write_access) ? $write_access : 1;
}

sub CloneSequence_list {
    my ($self, $CloneSequence_list) = @_;

    if ($CloneSequence_list) {
        $self->{'_CloneSequence_list'} = $CloneSequence_list;
    }
    return $self->{'_CloneSequence_list'};
}

sub drop_CloneSequence_list {
    my ($self) = @_;

    $self->{'_CloneSequence_list'} = undef;

    return;
}

sub selected_CloneSequences {
    my ($self, $selected_CloneSequences) = @_;

    if ($selected_CloneSequences) {
        confess "Not a list ref: '$selected_CloneSequences'"
            unless ref $selected_CloneSequences eq 'ARRAY';
        $self->{'_selected_CloneSequences'} = $selected_CloneSequences;
    }
    return $self->{'_selected_CloneSequences'};
}

sub unselect_all_CloneSequences {
    my ($self) = @_;

    $self->{'_selected_CloneSequences'} = undef;

    return;
}

sub select_CloneSequences_by_start_end_accessions {
    my ($self, $start_acc, $end_acc) = @_;

    my $ctg = [];
    my $in_contig = 0;
    my $cs_list = $self->CloneSequence_list;
    foreach my $cs (@$cs_list) {
        my $acc = $cs->accession;
        if ($acc eq $start_acc) {
            $in_contig = 1;
        }
        if ($in_contig) {
            push(@$ctg, $cs);
        }
        if ($acc eq $end_acc) {
            if ($in_contig) {
                $in_contig = 0;
            } else {
                die "Found end '$end_acc' but not start '$start_acc'\n";
            }
        }
    }
    if (@$ctg == 0) {
        die "Failed to find start '$start_acc'\n";
    }
    elsif ($in_contig) {
        die "Failed to find end '$end_acc'\n";
    }

    $self->selected_CloneSequences($ctg);

    return;
}

sub selected_CloneSequences_as_contig_list {
    my ($self) = @_;

    my $cs_list = $self->selected_CloneSequences
        or return;
    # Found that this funcionallity isn't desirable. Is better
    # if the annotator can open a single contig across a gap.
    # Just return all the selected clones in a single contig.
    return [$cs_list];
}

sub selected_CloneSequences_parameters {
    my ($self) = @_;

    my $ssname  = $self->name;
    my $dsname  = $self->dataset_name;
    my $cs_list = $self->selected_CloneSequences;

    confess "No CloneSequences selected" unless @$cs_list;

    my ($chr_name, $chr_start, $chr_end, $cs_name, $cs_version) = $self->region_coordinates($cs_list);

    return ($dsname, $ssname, $chr_name, $chr_start, $chr_end, $cs_name, $cs_version);
}

sub selected_CloneSequences_as_Slice {
    my ($self, $client) = @_;

    my ($dsname, $ssname, $chr_name, $chr_start, $chr_end) = $self->selected_CloneSequences_parameters;
    return Bio::Otter::Lace::Slice->new(
      $client, $dsname, $ssname,
      'chromosome', 'Otter',
      #'chromosome', __PACKAGE__.' '.__LINE__,     # Should these be defaults, or can we fetch them from another object?
      $chr_name, $chr_start, $chr_end,
      );
}

sub region_coordinates {
    my ($self, $ctg) = @_;

    my $chr_name  = $ctg->[0]->chromosome;
    my $chr_start = $ctg->[0]->chr_start;
    my $chr_end   = $ctg->[-1]->chr_end;
    my $cs_name   = $ctg->[0]->coord_system_name;
    my $cs_version = $ctg->[0]->coord_system_version;
    return ($chr_name, $chr_start, $chr_end, $cs_name, $cs_version);
}


sub CloneSequence_contigs_split_on_gaps {
    my ($self) = @_;

    my $cs_list = $self->CloneSequence_list;

    my $ctg = [];
    my $ctg_list = [$ctg];
    foreach my $this (sort {
        $a->chr_start <=> $b->chr_start
        } @$cs_list)
    {
        my $ctg_last = $ctg->[-1];
        if ($ctg_last) {
            if ($ctg_last->chr_end + 1 >= $this->chr_start) {
                push(@$ctg, $this);
            } else {
                $ctg = [$this];
                push(@$ctg_list, $ctg);
            }
        } else {
            push(@$ctg, $this);
        }
    }
    return $ctg_list;
}

sub agp_data {
    my ($self) = @_;

    my $cs_list = $self->CloneSequence_list;
    confess "CloneSequence list not yet loaded"
      unless @$cs_list;
    my $chr_name = $self->name;

    my $row  = 0;
    my $pos  = 0;
    my $data = [];
    foreach my $cs (@$cs_list) {
        $row++;
        my $acc           = $cs->accession;
        my $sv            = $cs->sv;
        my $chr_start     = $cs->chr_start;
        my $chr_end       = $cs->chr_end;
        my $superctg_name = $cs->super_contig_name;
        if (my $gap = ($chr_start - ($pos + 1))) {
            push(@$data,
                join("\t", $chr_name, $pos + 1, $pos + $gap, $row, 'N', $gap)
                  . "\n");
            $row++;
        }

        my @fields = (
            $chr_name,         $chr_start,
            $chr_end,          $row,
            'F',               "$acc.$sv",
            $cs->contig_start, $cs->contig_end,
            $cs->contig_strand eq '1' ? '+' : '-',
            );
        if ($superctg_name) {
            push(@fields, "# $superctg_name");
        }

        push(
            @$data,
            join("\t", @fields)
              . "\n"
        );
        $pos = $chr_end;
    }
    return $data;
}

## subroutines dealing with subsets:

sub accsv_belongs_to_subset { # the underlying mechanism
    my ($self, $accsv, $subset_tag, $belongs_flag) = @_;

    my $belhash = $self->{'_belongs_to'} ||= {};

    unless($subset_tag) { # to which subsets does this accsv belong?
        return map { $belhash->{$_}{$accsv} ? $_ : () } (keys %$belhash);
    }

    if(defined($belongs_flag)) {
        if($belongs_flag) { # a cleaner way - allows you to count keys, for example
            $belhash->{$subset_tag}{$accsv} = 1;
        } else {
            delete $belhash->{$subset_tag}{$accsv};
        }
    }
    return $self->{'_belongs_to'}{$subset_tag}{$accsv};
}

sub set_subset {
    my ($self, $subset_tag, $state_array_or_hash) = @_;


    $self->{'_belongs_to'}{$subset_tag} = (ref($state_array_or_hash) eq 'HASH')
        ? $state_array_or_hash
        : { map { ($_ => 1) } @$state_array_or_hash };

    return;
}

sub get_subset_names {
    my ($self) = @_;

    return [ keys %{ $self->{'_belongs_to'} } ];
}

sub get_subsets_first_last_index { # They are 0-based indices

    ## NB: make sure the CloneSequences have been loaded,
    ##     as it doesn't happen autimagically yet!

    my ($self, $subset_tag) = @_;

    my ($index_first, $index_last);
    my $cs_list = $self->CloneSequence_list;
    foreach my $i (0..scalar(@$cs_list)-1) {
        my $cs = $cs_list->[$i];
        if($self->accsv_belongs_to_subset($cs->accession_dot_sv(), $subset_tag)) {
            unless(defined($index_first)) { $index_first = $i; }
            $index_last = $i;
        }
    }
    return ($index_first, $index_last);
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::SequenceSet

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

