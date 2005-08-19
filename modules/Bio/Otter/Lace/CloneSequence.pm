
### Bio::Otter::Lace::CloneSequence

package Bio::Otter::Lace::CloneSequence;

use strict;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub accession {
    my( $self, $accession ) = @_;
    
    if ($accession) {
        $self->{'_accession'} = $accession;
    }
    return $self->{'_accession'};
}

sub sv {
    my( $self, $sv ) = @_;
    
    if (defined $sv) {
        $self->{'_sv'} = $sv;
    }
    return $self->{'_sv'};
}

sub clone_name {
    my( $self, $clone_name ) = @_;
    
    if ($clone_name) {
        $self->{'_clone_name'} = $clone_name;
    }
    return $self->{'_clone_name'};
}

sub length {
    my( $self, $length ) = @_;
    
    if ($length) {
        $self->{'_length'} = $length;
    }
    return $self->{'_length'};
}

sub chromosome {
    my( $self, $chromosome ) = @_;
    
    if ($chromosome) {
        $self->{'_chromosome'} = $chromosome;
    }
    return $self->{'_chromosome'};
}
sub pipeline_chromosome {
    my( $self, $chromosome ) = @_;
    
    if ($chromosome) {
        $self->{'_pipeline_chromosome'} = $chromosome;
    }
    return $self->{'_pipeline_chromosome'};
}
sub chr_start {
    my( $self, $chr_start ) = @_;
    
    if (defined $chr_start) {
        $self->{'_chr_start'} = $chr_start;
    }
    return $self->{'_chr_start'};
}

sub chr_end {
    my( $self, $chr_end ) = @_;
    
    if (defined $chr_end) {
        $self->{'_chr_end'} = $chr_end;
    }
    return $self->{'_chr_end'};
}

sub contig_id {
    my( $self, $contig_id ) = @_;
    
    if ($contig_id) {
        $self->{'_contig_id'} = $contig_id;
    }
    return $self->{'_contig_id'};
}

sub pipeline_contig_id {
    my( $self, $pipe_contig_id ) = @_;
    
    if ($pipe_contig_id) {
        $self->{'_pipe_contig_id'} = $pipe_contig_id;
    }
    return $self->{'_pipe_contig_id'};
}


sub contig_name {
    my( $self, $contig_name ) = @_;
    
    if ($contig_name) {
        $self->{'_contig_name'} = $contig_name;
    }
    return $self->{'_contig_name'};
}
sub super_contig_name {
    my( $self, $contig_name ) = @_;
    
    if ($contig_name) {
        $self->{'_super_contig_name'} = $contig_name;
    }
    return $self->{'_super_contig_name'};
}
sub contig_start {
    my( $self, $contig_start ) = @_;
    
    if (defined $contig_start) {
        $self->{'_contig_start'} = $contig_start;
    }
    return $self->{'_contig_start'};
}

sub contig_end {
    my( $self, $contig_end ) = @_;
    
    if (defined $contig_end) {
        $self->{'_contig_end'} = $contig_end;
    }
    return $self->{'_contig_end'};
}

sub contig_strand {
    my( $self, $contig_strand ) = @_;
    
    if ($contig_strand) {
        $self->{'_contig_strand'} = $contig_strand;
    }
    return $self->{'_contig_strand'};
}

sub pipelineStatus {
    my( $self, $status ) = @_;

    if ($status) {
        $self->{'_pipelineStatus'} = $status;
    }
    return $self->{'_pipelineStatus'};
}

sub drop_pipelineStatus {
    my( $self ) = @_;

    $self->{'_pipelineStatus'} = undef;
}

sub add_SequenceNote {
    my( $self, $note ) = @_;
    
    my $sn_list = $self->{'_SequenceNote_list'} ||= [];
    push(@$sn_list, $note);
}

sub truncate_SequenceNotes{
    my( $self ) = @_;
    $self->{'_SequenceNote_list'} = [];
    return $self->{'_SequenceNote_list'};
}

sub get_all_SequenceNotes {
    my( $self ) = @_;
    
    return $self->{'_SequenceNote_list'};
}

sub current_SequenceNote {
    my( $self, $current_SequenceNote ) = @_;
    
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

sub set_lock_status{
    my ($self , $lock) = @_ ;
    if (defined $lock ){
        $self->{'_lock_status'} = $lock ;
    }
}

sub get_lock_status{
    my $self = shift;
    warn "get_lock_status is 'Get' only" if @_;
    return $self->{'_lock_status'} ? 1 : 0 ;
}

sub get_lock_as_CloneLock{
    my ($self) = @_;
    return $self->{'_lock_status'};
}
1;

__END__

=head1 NAME - Bio::Otter::Lace::CloneSequence

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

