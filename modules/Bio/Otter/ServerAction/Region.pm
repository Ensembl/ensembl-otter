package Bio::Otter::ServerAction::Region;

use strict;
use warnings;

use Readonly;
use Try::Tiny;

use Bio::Vega::ContigLockBroker;
use Bio::Vega::Transform::Otter;
use Bio::Vega::Transform::XML;

=head1 NAME

Bio::Otter::ServerAction::Region - server requests on a region

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

sub new_no_slice {
    my ($pkg, $server, $params) = @_;

    my $self = {
        _server => $server,
        _params => $params,
    };
    my $class = ref($pkg) || $pkg;
    bless $self, $class;

    return $self;
}

sub new {
    my ($pkg, $server, $params) = @_;

    my $self = $pkg->new_no_slice($server, $params);

    my $slice = $self->_get_requested_slice($params);
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

# Really the XML generation should be factored out to the apache script, but
# for now we treat the XML as a black-box token to be returned to unlock_region.
#
sub lock_region {
    my $self = shift;

    my $server = $self->server;
    my $odba = $server->otter_dba();
    $odba->begin_work;

    my $cb = Bio::Vega::ContigLockBroker->new;
    $cb->client_hostname($self->param('cl_host'));

    my $slice = $self->slice;
    my $author_obj = $server->make_Author_obj();

    my ($xml, $action);
    try {
        $action = 'locking';
        $cb->lock_clones_by_slice($slice, $author_obj, $odba);

        $action = 'result setup';
        my $formatter = Bio::Vega::Transform::XML->new;
        $formatter->otter_dba($odba);
        $formatter->slice($slice);
        $formatter->fetch_species;
        $formatter->fetch_CloneSequences;

        $action = 'output';
        $xml = $formatter->generate_OtterXML;
        $odba->commit;
    } catch {
        $odba->rollback;
        die "Locking clones failed during $action \[$_]";
    };

    return $xml;
}

# This doesn't really need the services of ServerAction::Region, but for symmetry it
# should live here.
#
sub unlock_region {
    my $self = shift;

    my $server = $self->server;
    my $odba   = $server->otter_dba();

    $odba->begin_work;
    my $author_obj = $server->make_Author_obj();
    my $slice;

    # the original string lives here:
    my $xml_string = $self->param('data');

    my $action;
    try {
        $action = 'converting XML to otter';

        my $parser = Bio::Vega::Transform::Otter->new;
        $parser->parse($xml_string);

        my $chr_slice    = $parser->get_ChromosomeSlice;
        my $seq_reg_name = $chr_slice->seq_region_name;
        my $start        = $chr_slice->start;
        my $end          = $chr_slice->end;
        my $strand       = $chr_slice->strand;
        my $cs           = $chr_slice->coord_system->name;
        my $cs_version   = $chr_slice->coord_system->version;

        $slice = $odba->get_SliceAdaptor()->fetch_by_region(
            $cs, $seq_reg_name, $start, $end, $strand, $cs_version);
        warn "Processed incoming xml file with slice: [$seq_reg_name] [$start] [$end]\n";

        $action = 'checking locks';
        warn "Checking region is locked...\n";
        my $cb=Bio::Vega::ContigLockBroker->new;
        $cb->check_locks_exist_by_slice($slice,$author_obj,$odba);
        warn "Done checking region is locked.\n";

        $action = 'to unlock clones';
        warn "Unlocking clones...\n";
        $cb->remove_by_slice($slice,$author_obj,$odba);
        warn "Done unlocking clones.\n";

        $odba->commit;
    } catch {
        $odba->rollback;
        die "Failed $action \[$_]";
    };

    return;
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

sub param {
    my ($self, $key) = @_;
    return $self->{_params}->{$key};
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
