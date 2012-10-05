package Bio::Otter::Server::Slice;

use strict;
use warnings;

use Readonly;

use Bio::Vega::Transform::XML;

=head1 NAME

Bio::Otter::Server::Slice - server requests on a slice

=cut

Readonly our @REQUIRED_PARAMS => qw(
    dataset
    cs
    csver
    type
    start
    end
);

### Constructors

sub new {
    my ($pkg, $server, $slice_params) = @_;

    my $self = {
        _server => $server,
    };
    my $class = ref($pkg) || $pkg;
    bless $self, $class;

    my $slice = $self->_get_requested_slice($slice_params);
    $self->slice($slice);

    return $self;
}

sub _get_requested_slice {
    my ($self, $params) = @_;

    my $strand  = 1;

    return $self->server->otter_dba->get_SliceAdaptor->fetch_by_region(
        $params->{cs},
        $params->{type},
        $params->{start},
        $params->{end},
        $strand,
        $params->{csver}
        );
}

### Methods

sub get_assembly_dna {
    my $self = shift;

    my $slice = $self->slice;
    my $output_string = $slice->seq . "\n";

    my $posn = 0;
    foreach my $tile (@{ $slice->project('seqlevel') }) {
        my $tile_slice = $tile->to_Slice;
        my $start = $tile->from_start;
        my $end   = $tile->from_end;

        # Is there a gap before this piece?
        if (my $gap = $start - $posn - 1) {
            # Debugging.  Show the char immediately before and after the string of "N".
            # $output_string .= substr($output_string, $posn == 0 ? 0 : $posn - 1, $posn == 0 ? $gap + 1 : $gap + 2) . "\n";
            # Change assembly gaps to dashes.
            substr($output_string, $posn, $gap, '-' x $gap);
        }
        $posn = $end;

        # To save copying large strings, we append onto the
        # end of the sequence in the output string.
        $output_string .= join("\t",
                               $tile->from_start,
                               $tile->from_end,
                               $tile_slice->seq_region_name,
                               $tile_slice->start,
                               $tile_slice->end,
                               $tile_slice->strand,
                               $tile_slice->seq_region_Slice->length,
            ) . "\n";
    }
    if (my $gap = $slice->length - $posn) {
        # If the slice ends in a gap, turn to dashes too
        substr($output_string, $posn, $gap, '-' x $gap);
    }

    return $output_string;
}

sub get_region {
    my $self = shift;

    my $odba  = $self->server->otter_dba;
    my $slice = $self->slice;

    my $formatter = Bio::Vega::Transform::XML->new;
    $formatter->otter_dba($odba);
    $formatter->slice($slice);
    $formatter->fetch_data_from_otter_db;

    return $formatter;
}

### Accessors

sub server {
    return shift->{_server};
}

sub slice {
    my ($self, @args) = @_;
    ($self->{_slice}) = @args if @args;
    return $self->{_slice};
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
