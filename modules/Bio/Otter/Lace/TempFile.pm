
### Bio::Otter::Lace::TempFile

package Bio::Otter::Lace::TempFile;

use strict;
use Carp;
use Symbol 'gensym';
use Fcntl qw{ O_WRONLY O_CREAT O_RDONLY };

sub new {
    my( $pkg, $name ) = @_;
    
    return bless {}, $pkg;
}

sub root {
    my( $self, $root ) = @_;
    
    if ($root) {
        $self->{'_root'} = $root;
    }
    return $self->{'_root'} || '/var/tmp';
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'} || 'TempFile';
}

sub full_name {
    my( $self, $full_name ) = @_;
    
    if ($full_name) {
        confess "Can't change full_name after filehandles opened"
            if $self->{'_read_file_handle'} || $self->{'_write_file_handle'};
        $self->{'_full_name'} = $full_name;
    }
    return $self->{'_full_name'} ||
        $self->root . '/' . $$ . '.' . $self->name;
}

sub read_file_handle {
    my( $self ) = @_;
    
    if (my $fh = $self->{'_write_file_handle'}) {
        close($fh) or confess "Error closing filehandle: $!";
        $self->{'_write_file_handle'} = undef;
    }
    my( $fh );
    unless ($fh = $self->{'_read_file_handle'}) {
        $fh = gensym();
        my $full = $self->full_name;
        sysopen($fh, $full, O_RDONLY)
            or confess "Error reading '$full' : $!";
        $self->{'_read_file_handle'} = $fh;
    }
    return $fh;
}

sub write_file_handle {
    my( $self ) = @_;
    
    my( $fh );
    unless ($fh = $self->{'_write_file_handle'}) {
        $self->{'_read_file_handle'} = undef;
        $fh = gensym();
        my $full = $self->full_name;
        sysopen($fh, $full, O_WRONLY | O_CREAT)
            or confess "Error creating '$full' : $!";
        $self->{'_write_file_handle'} = $fh;
    }
    return $fh;
}

sub DESTROY {
    my( $self ) = @_;
    
    unlink($self->full_name);
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::TempFile

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk
