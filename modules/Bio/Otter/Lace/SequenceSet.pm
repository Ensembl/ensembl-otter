
### Bio::Otter::Lace::SequenceSet

package Bio::Otter::Lace::SequenceSet;

use strict;
use Carp;

sub new {
    my $pkg = shift;
    
    return bless {}, $pkg;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub dataset_name {
    my( $self, $dataset_name ) = @_;
    
    if ($dataset_name) {
        $self->{'_dataset_name'} = $dataset_name;
    }
    return $self->{'_dataset_name'};
}

sub description {
    my( $self, $description ) = @_;
    
    if ($description) {
        $self->{'_description'} = $description;
    }
    return $self->{'_description'};
}

sub write_access {
    my( $self, $write_access ) = @_;
    
    if ($write_access) {
        $self->{'_write_access'} = $write_access ? 1 : 0;
    }
    $write_access = $self->{'_write_access'};
    if (defined $write_access) {
        return $write_access;
    } else {
        return 1;
    }
}

sub CloneSequence_list {
    my( $self, $CloneSequence_list ) = @_;
    
    if ($CloneSequence_list) {
        $self->{'_CloneSequence_list'} = $CloneSequence_list;
    }
    return $self->{'_CloneSequence_list'};
}

sub drop_CloneSequence_list {
    my( $self ) = @_;
    
    $self->{'_CloneSequence_list'} = undef;
}

sub selected_CloneSequences {
    my( $self, $selected_CloneSequences ) = @_;
    
    if ($selected_CloneSequences) {
        my $is_list = 1;
        eval{ $is_list = 1 if ref($selected_CloneSequences) eq 'ARRAY' };
        confess "Not a list ref: '$selected_CloneSequences'" unless $is_list;
        $self->{'_selected_CloneSequences'} = $selected_CloneSequences;
    }
    return $self->{'_selected_CloneSequences'};
}

sub unselect_all_CloneSequences {
    my( $self ) = @_;
    
    $self->{'_selected_CloneSequences'} = undef;
}

sub selected_CloneSequences_as_contig_list {
    my( $self ) = @_;
    
    my $cs_list = $self->selected_CloneSequences
        or return;
    my $ctg = [];
    my $ctg_list = [$ctg];
    foreach my $this (sort {
        $a->chromosome->chromosome_id <=> $b->chromosome->chromosome_id ||
        $a->chr_start <=> $b->chr_start
        } @$cs_list)
    {
        my $last = $ctg->[$#$ctg];
        if ($last) {
            if ($last->chr_end + 50_001 >= $this->chr_start) {
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

### Method for fetching completeness of analysis
### for all the CloneSequences in a SequenceSet

1;

__END__

=head1 NAME - Bio::Otter::Lace::SequenceSet

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

