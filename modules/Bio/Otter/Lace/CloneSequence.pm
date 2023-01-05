=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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


### Bio::Otter::Lace::CloneSequence

package Bio::Otter::Lace::CloneSequence;

use strict;
use warnings;
use List::MoreUtils 'uniq';

sub new {
    my ($pkg) = @_;

    return bless {}, $pkg;
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

sub accession {
    my ($self, $accession) = @_;

    if ($accession) {
        $self->{'_accession'} = $accession;
    }
    return $self->{'_accession'} if $self->{'_accession'};
    return $self->{'_contig_name'};
}

sub sv {
    my ($self, $sv) = @_;

    if (defined $sv) {
        $self->{'_sv'} = $sv;
    }
    return $self->{'_sv'};
}

sub accession_dot_sv { # due to extreme popularity
    my ($self) = @_;

    if (my $sv = $self->sv()) {
        return $self->accession().'.'.$sv;
    } else {
        return $self->accession();
    }
}

sub clone_name {
    my ($self, $clone_name) = @_;

    if ($clone_name) {
        $self->{'_clone_name'} = $clone_name;
    }
    return $self->{'_clone_name'};
}

sub contig_name {
    my ($self, $contig_name) = @_;

    if ($contig_name) {
        $self->{'_contig_name'} = $contig_name;
    }
    return $self->{'_contig_name'};
}

sub chromosome {
    my ($self, $chromosome) = @_;

    if ($chromosome) {
        $self->{'_chromosome'} = $chromosome;
    }
    return $self->{'_chromosome'};
}

sub assembly_type {
    my ($self, $asm_type) = @_;

    if ($asm_type) {
        $self->{'_asm_type'} = $asm_type;
    }
    return $self->{'_asm_type'};
}

sub chr_start {
    my ($self, $chr_start) = @_;

    if (defined $chr_start) {
        $self->{'_chr_start'} = $chr_start;
    }
    return $self->{'_chr_start'};
}

sub chr_end {
    my ($self, $chr_end) = @_;

    if (defined $chr_end) {
        $self->{'_chr_end'} = $chr_end;
    }
    return $self->{'_chr_end'};
}

sub contig_start {
    my ($self, $contig_start) = @_;

    if (defined $contig_start) {
        $self->{'_contig_start'} = $contig_start;
    }
    return $self->{'_contig_start'};
}

sub contig_end {
    my ($self, $contig_end) = @_;

    if (defined $contig_end) {
        $self->{'_contig_end'} = $contig_end;
    }
    return $self->{'_contig_end'};
}

sub contig_strand {
    my ($self, $contig_strand) = @_;

    if ($contig_strand) {
        $self->{'_contig_strand'} = $contig_strand;
    }
    return $self->{'_contig_strand'};
}

sub length {
    my ($self, $length) = @_;

    if ($length) {
        $self->{'_length'} = $length;
    }
    return $self->{'_length'};
}

sub sequence {
    my ($self, $seq) = @_;

    if ($seq) {
        $self->{'_seq'} = $seq;
    }
    return $self->{'_seq'} || die 'sequence() not set';
}

# --------- check if we really need the following ones: ------------
sub contig_id {
    my ($self, $contig_id) = @_;

    if ($contig_id) {
        $self->{'_contig_id'} = $contig_id;
    }
    return $self->{'_contig_id'};
}

sub super_contig_name {
    my ($self, $contig_name) = @_;

    if ($contig_name) {
        $self->{'_super_contig_name'} = $contig_name;
    }
    return $self->{'_super_contig_name'};
}

sub pipeline_chromosome {
    my ($self, $chromosome) = @_;

    if ($chromosome) {
        $self->{'_pipeline_chromosome'} = $chromosome;
    }
    return $self->{'_pipeline_chromosome'};
}
# --------------------------------------------------------------------


# write_region requires that the client describe the region, to
# ensure it is the correct one, but then ignores ContigInfo.
#
# ContigInfo is still provided to the client, and inserted into AceDB.
# Other than that, it should be no longer used on the client.
sub ContigInfo {
    my ($self, $ContigInfo) = @_;

    if ($ContigInfo) {
        $self->{'_ContigInfo'} = $ContigInfo;
    }
    return $self->{'_ContigInfo'};
}

sub pipelineStatus {
    my ($self, $status) = @_;

    if ($status) {
        $self->{'_pipelineStatus'} = $status;
    }
    return $self->{'_pipelineStatus'};
}

sub drop_pipelineStatus {
    my ($self) = @_;

    $self->{'_pipelineStatus'} = undef;

    return;
}

sub add_SequenceNote {
    my ($self, $note) = @_;

    my $sn_list = $self->{'_SequenceNote_list'} ||= [];
    push(@$sn_list, $note);

    return;
}

sub truncate_SequenceNotes{
    my ($self) = @_;
    $self->{'_SequenceNote_list'} = [];
    return $self->{'_SequenceNote_list'};
}

sub get_all_SequenceNotes {
    my ($self) = @_;

    return $self->{'_SequenceNote_list'};
}

sub current_SequenceNote {
    my ($self, $current_SequenceNote) = @_;

    if ($current_SequenceNote) {

        # Add this SequenceNote to the list if it
        # isn't one of the ones on the list
        my $sn_list = $self->get_all_SequenceNotes;
        my $found = 0;
        foreach my $note (@$sn_list) {
            $found = 1 if $note == $current_SequenceNote;
        }
        unless ($found) {
            push(@$sn_list, $current_SequenceNote);
        }

        $self->{'_current_SequenceNote'} = $current_SequenceNote;
    }
    return $self->{'_current_SequenceNote'};
}

# SliceLocks which overlap this clone.  They could also overlap
# another clone, when we start doing that.
sub set_SliceLocks {
    my ($self, @lock_list) = @_;
    $self->{'_SliceLocks'} = \@lock_list;
    return;
}

sub get_lock_status {
    my ($self, @args) = @_;
    warn "get_lock_status is 'Get' only" if @args;
    my $slocks = $self->{'_SliceLocks'} || [];
    return @$slocks ? 1 : 0;
}

sub get_SliceLocks {
    my ($self) = @_;
    my $slocks = $self->{'_SliceLocks'} || [];
    return @$slocks;
}

sub get_lock_users {
    my ($self) = @_;
    my @usr = map { $_->describe_author } $self->get_SliceLocks;
    @usr = uniq sort(@usr);
    return @usr;
}


1;

__END__

=head1 NAME - Bio::Otter::Lace::CloneSequence

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

