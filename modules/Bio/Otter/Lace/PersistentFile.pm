
### Bio::Otter::Lace::PersistentFile

package Bio::Otter::Lace::PersistentFile;

use strict;
use Carp;
use Bio::Otter::Lace::TempFile;

our @ISA = qw(Bio::Otter::Lace::TempFile);

sub rm{
    my ($self) = @_;
    unlink($self->full_name);
}
sub mv{
    my ($self, $name) = @_;
    confess q`Cannot rename if $file->full_name('/path/to/file') was called` 
        if $self->{'_full_name'};
    my $old_full_name = $self->full_name();
    #$self->close(); # no need to do this apparently
    $self->name($name);
    my $new_full_name = $self->full_name();
    rename($old_full_name, $new_full_name)
        or confess "Error renaming '$old_full_name' to '$new_full_name' : $!";
}
sub full_name{
    my( $self, $full_name ) = @_;
    
    if ($full_name) {
        confess "Can't change full_name after filehandles opened"
            if $self->{'_read_file_handle'} || $self->{'_write_file_handle'};
        $self->{'_full_name'} = $full_name;
    }
    return $self->{'_full_name'} ||
        $self->root . '/' . $self->name;
}

sub DESTROY{
    #my ($self) = @_;
    #my $name = $self->full_name();
    #print STDERR "File $name is not being removed even though it's being DESTROY'd\n";
    # $self->close(); # not needed as Perl will close it automagically
}
