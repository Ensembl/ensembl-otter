
### Bio::Otter::GeneFilter

package Bio::Otter::GeneFilter;

use strict;
use warnings;

use Carp;

use base 'Bio::Otter::GFFFilter';

sub transcript_analyses {
    my ($self, $transcript_analyses) = @_;
    $self->{_transcript_analyses} = $transcript_analyses if $transcript_analyses;
    return $self->{_transcript_analyses};
}

sub translation_xref_dbs {
    my ($self, $translation_xref_dbs) = @_;
    $self->{_translation_xref_dbs} = $translation_xref_dbs if $translation_xref_dbs;
    return $self->{_translation_xref_dbs};
}

sub server_params {
    my ($self) = @_;
    
    my $params = $self->SUPER::server_params;
    
    $params->{transcript_analyses} = $self->transcript_analyses;
    $params->{translation_xref_dbs} = $self->translation_xref_dbs;
       
    return $params;
}

1;

__END__

=head1 NAME - Bio::Otter::GeneFilter

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk
