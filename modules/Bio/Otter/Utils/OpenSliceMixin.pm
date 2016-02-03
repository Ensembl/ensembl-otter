
### Bio::Otter::Utils::OpenSliceMixin

package Bio::Otter::Utils::OpenSliceMixin;

use strict;
use warnings;

use Carp;
use Try::Tiny;

=pod

=head1 NAME - Bio::Otter::Utils::OpenSliceMixin

Common code for opening a slice and building a column chooser.

=over 4

=item open_Slice

Consumer must supply the following methods:

=over 4

=item Client()

=item make_ColumnChooser($ace_database)

=item refresh_lock_display($slice)

=item message()

=item exception_message()

=back

=back

=cut

sub open_Slice {
    my ($self, %args) = @_;

    my $slice        = $args{slice}        ||  confess "must provide slice";
    my $write_access = $args{write_access} //= 0;
    my $name         = $args{name};

    my $adb = $self->Client->new_AceDatabase_from_Slice($slice);
    $adb->write_access($write_access);
    $adb->name        ( $name       ) if $name;

    if ($write_access) {
        # only lock the region if we have write access.
        try { $adb->try_to_lock_the_block }
        catch {
            $adb->error_flag(0);
            $adb->write_access(0);  # Stops AceDatabase DESTROY from trying to unlock clones
            if (/Locking slice failed during locking.*do_lock failed <lost the race/s) {
                # a message concatenated in the lock_region action, from the SliceLockBroker
                $self->message("The region you are trying to open is locked\n");
            } else {
                $self->exception_message($_, 'Error initialising database');
            }
            return 0;
        }
        finally {
            try { $self->refresh_lock_display($slice) };
        }
          or return;
    }

    my $cc = $self->make_ColumnChoser($adb);
    $cc->init_flag(1);
    return $cc;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

