=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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
            my $error = $_;
            $adb->error_flag(0);
            $adb->write_access(0);  # Stops AceDatabase DESTROY from trying to unlock clones

            # This is nasty as it relies on and repeats error literal thrown from:
            #  Bio::Otter::ServerAction::Region->lock_region() - which includes another thrown from:
            #  Bio::Vega::SliceLockBroker->exclusive_work()
            my $server_action_region_msg = qr/\QLocking slice failed during locking\E/;
            my $slice_lock_broker_msg    = qr/\Qdo_lock failed <lost the race\E/;
            my $locked_re = qr/
                $server_action_region_msg
                .*
                $slice_lock_broker_msg
                /sx;

            if ($error =~ $locked_re) {
                $self->message("The region you are trying to open is locked\n");
            } else {
                $self->exception_message($error, 'Error initialising database');
            }
            return 0;
        }
        finally {
            try { $self->refresh_lock_display($slice) };
        }
          or return;
    }

    my $cc = $self->make_ColumnChooser($adb);
    $cc->init_flag(1);
    return $cc;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

