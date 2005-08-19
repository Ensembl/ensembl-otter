
### Bio::Otter::Lace::PipelineStatus

package Bio::Otter::Lace::PipelineStatus;

use strict;
use Carp;
use Data::Dumper;
use Bio::EnsEMBL::Analysis;


sub new {
    return bless {}, shift;
}

# Can have single copy of the list of analyses and
# the order they are in because the interface only
# allows the user to connect to a single dataset
# at a time.
my( @rule_list );

sub set_rule_list {
    my( $pkg, $list ) = @_;
    
    @rule_list = @$list;
}

sub add_completed_analysis {
    my( $self, $name, $created, $version ) = @_;
    
    $self->{$name}{'created'} = $created;
    $self->{$name}{'version'} = $version;
}

# Returns an array used by CanvasWindow::SequenceNotes::Status
# to display status information.
sub display_list {
    my( $self ) = @_;
    
    my $display_list = [];
    foreach my $name (@rule_list) {
        my $stat_hash = { name => $name };
        if (my $ana = $self->{$name}) {
            $stat_hash->{'status'} = 'completed';
            while (my ($key, $val) = each %$ana) {
                $stat_hash->{$key} = $val;
            }
        } else {
            $stat_hash->{'status'}  = 'missing';
            $stat_hash->{'created'} = '-';
            $stat_hash->{'version'} = '-';
        }
        push(@$display_list, $stat_hash);
    }
    return $display_list;
}

# Called by CanvasWindow::SequenceNotes for displaying overall status of clone
sub short_display {
    my( $self ) = @_;
        
    return keys %$self == @rule_list ? 'completed' : 'missing';
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::PipelineStatus

=head1 SYNOPSIS

=head1 DESCRIPTION

Designed to have hold information on the status of a 
CloneSequence in the pipeline.

=head1 AUTHOR

Roy Storey B<email> rds@sanger.ac.uk

