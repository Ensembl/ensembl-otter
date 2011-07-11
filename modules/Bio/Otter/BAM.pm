
### Bio::Otter::BAM

package Bio::Otter::BAM;

use strict;
use warnings;

use Carp;

my @keys = qw( description file csver );

sub new {
    my ($pkg, $name, $config) = @_;

    for (@keys) {
        confess "missing BAM configuration parameter: $_"
            unless defined $config->{$_};
    }

    my $self = { name => $name, %{$config} };
    bless $self, $pkg;

    return $self;
}

sub name {
    my ($self) = @_;
    return $self->{name};
}

sub description {
    my ($self) = @_;
    return $self->{description};
}

sub file {
    my ($self) = @_;
    return $self->{file};
}

sub csver {
    my ($self) = @_;
    return $self->{csver};
}

sub gff_feature_source {
    my ($self) = @_;
    return $self->{gff_feature_source};
}

sub chr_prefix {
    my ($self) = @_;
    return $self->{chr_prefix};
}

1;

__END__

=head1 NAME - Bio::Otter::BAM

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

