
### Bio::Otter::Lace::TempFile

package Bio::Otter::Lace::TempFile;

use strict;

sub new {
    my( $pkg ) = @_;
    
    
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
        $self->{'_full_name'} = $full_name;
    }
    return $self->{'_full_name'} ||
        join('/'
            $self->root,
            $self->name,
            $$);
}


1;

__END__

=head1 NAME - Bio::Otter::Lace::TempFile

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk
