
### Bio::Otter::Utils::DotterLauncher

package Bio::Otter::Utils::DotterLauncher;

use strict;
use warnings;
use Carp;
use Hum::FastaFileIO;
use Hum::Pfetch;
use POSIX ();

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}

sub query_start {
    my( $self, $query_start ) = @_;

    if ($query_start) {
        $self->{'_query_start'} = $query_start;
    }
    return $self->{'_query_start'};
}

sub query_end {
    my( $self, $query_end ) = @_;

    if ($query_end) {
        $self->{'_query_end'} = $query_end;
    }
    return $self->{'_query_end'};
}

sub query_Sequence {
    my( $self, $query_Sequence ) = @_;

    if ($query_Sequence) {
        $self->{'_query_Sequence'} = $query_Sequence;
    }
    return $self->{'_query_Sequence'};
}

sub subject_name {
    my( $self, $subject_name ) = @_;

    if ($subject_name) {
        $self->{'_subject_name'} = $subject_name;
    }
    return $self->{'_subject_name'};
}

sub revcomp_subject {
    my( $self, $flag ) = @_;

    if (defined $flag) {
        $self->{'_revcomp_subject'} = $flag;
    }
    return $self->{'_revcomp_subject'} || 0;
}

sub fork_dotter {
    my( $self ) = @_;

    my $start           = $self->query_start    or confess "query_start not set";
    my $end             = $self->query_end      or confess "query_end not set";
    my $seq             = $self->query_Sequence or confess "query_Sequence not set";
    my $subject_name    = $self->subject_name   or confess "subject_name not set";

    if (my $pid = fork) {
        return 1;
    }
    elsif (defined $pid) {
        my $prefix = "/tmp/dotter.$$";
        my $query_file   = "$prefix.query";
        my $subject_file = "$prefix.subject";
        eval{
            my $query_seq = $seq->sub_sequence($start, $end);
            $query_seq->name($seq->name);

            # Gaps between clones are emitted as dashes by acedb but dotter
            # splcies them out, which affects the coordinates, so we must
            # change them to "n"s.
            $self->change_dashes_to_n($query_seq);

            # Write the subject with pfetch
            my ($subject_seq) = Hum::Pfetch::get_Sequences($subject_name);
            die "Can't fetch '$subject_name'\n" unless $subject_seq;
            if ($self->revcomp_subject) {
                bless($subject_seq, 'Hum::Sequence::DNA');  # hack!
                $subject_seq = $subject_seq->reverse_complement;
            }
            my $subject_out = Hum::FastaFileIO->new("> $subject_file");
            $subject_out->write_sequences($subject_seq);
            $subject_out = undef;

            # Write out the query sequence
            my $query_out = Hum::FastaFileIO->new("> $query_file");
            $query_out->write_sequences($query_seq);
            $query_out = undef;

            # Run dotter. Offset ensures that annotators see the global
            # coordinates of the whole assembly in dotter.
            my $offset = $start - 1;
            my $dotter_command = "dotter -q $offset $query_file $subject_file ; rm $query_file $subject_file ; echo 'Dotter finished'";
            warn "RUNNING: $dotter_command\n";
            exec($dotter_command) or warn "Failed to exec '$dotter_command' : $!";
        };
        if ($@) {
            warn $@;
            # Exec'ing rm here, which replaces the perl process
            # with rm, ensures that the perl DESTROY methods
            # don't get called by this child.
            unlink $query_file, $subject_file
              or warn "Some input file(s) not tidied up: $!\n";
        }
        warn "dotter launch aborted\n";
        POSIX::_exit(127); # avoid triggering DESTROY
    }
    else {
        confess "Can't fork: $!";
    }
}

sub change_dashes_to_n {
    my( $self, $seq ) = @_;

    my $str = $seq->sequence_string;
    $str =~ tr/-/n/;
    $seq->sequence_string($str);
}

1;

__END__

=head1 NAME - Bio::Otter::Utils::DotterLauncher

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

