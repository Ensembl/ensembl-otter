
### Bio::Otter::GFFFilter

package Bio::Otter::GFFFilter;

use strict;
use warnings;

use Carp;

use base 'Bio::Otter::Filter';

sub zmap_column {
    my ($self, $zmap_column) = @_;
    
    if ($zmap_column) {
        $self->{'_zmap_column'} = $zmap_column;
    }
    return $self->{'_zmap_column'};
}

sub zmap_style {
    my ($self, $zmap_style) = @_;
    
    if ($zmap_style) {
        $self->{'_zmap_style'} = $zmap_style;
    }
    return $self->{'_zmap_style'};
}

sub ditypes {
    my ($self, $ditypes) = @_;
    
    if ($ditypes) {
        $self->{'_ditypes'} = $ditypes;
    }
    return $self->{'_ditypes'};
}

sub process_gff_file {
    my($self, $flag) = @_;
    
    if (defined $flag) {
        $self->{'_process_gff_file'} = $flag ? 1 : 0;
    }
    return $self->{'_process_gff_file'};
}

sub server_params {
    my ($self) = @_;
    
    my $params = $self->SUPER::server_params;
    
    $params->{server_script} = 'get_gff_features';
    $params->{ditypes} = $self->ditypes if $self->ditypes;
    
    return $params;
}

1;

__END__

=head1 NAME - Bio::Otter::GFFFilter

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk
