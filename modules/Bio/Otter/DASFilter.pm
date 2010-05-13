
### Bio::Otter::DASFilter

package Bio::Otter::DASFilter;

use strict;
use warnings;

use Carp;

use base 'Bio::Otter::GFFFilter';

sub grouplabel {
    my ($self, $grouplabel) = @_;
    $self->{_grouplabel} = $grouplabel if $grouplabel;
    return $self->{_grouplabel};
}

sub dsn {
    my ($self, $dsn) = @_;
    $self->{_dsn} = $dsn if $dsn;
    return $self->{_dsn};
}

sub sieve {
    my ($self, $sieve) = @_;
    $self->{_sieve} = $sieve if $sieve;
    return $self->{_sieve};
}

sub source {
    my ($self, $source) = @_;
    $self->{_source} = $source if $source;
    return $self->{_source};
}

sub server_params {
    my ($self) = @_;
    
    my $params = $self->SUPER::server_params;
    
    for my $meth (qw( grouplabel dsn sieve source )) {
        $params->{$meth} = $self->$meth;
    }
    
    $params->{server_script} = 'nph-get_gff_das_features';
    
    $params->{gff_source} = $self->name;
       
    return $params;
}

1;

__END__

=head1 NAME - Bio::Otter::DASFilter

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk
