package Bio::Otter::Server;

use strict;
use warnings;

=head1 NAME

Bio::Otter::Server - common parent for MFetcher/ServerScriptSupport and LocalServer

=cut

use Bio::Otter::Server::Config;

sub new { # just to make it possible to instantiate an object
    my ($pkg, @arguments) = @_;

    my $self = bless { @arguments }, $pkg;
    return $self;
}

sub SpeciesDat {
    my ($self) = @_;
    return $self->{_SpeciesDat} ||= Bio::Otter::Server::Config->SpeciesDat;
}

sub dataset {
    my ($self, $dataset) = @_;

    if($dataset) {
        $self->{'_dataset'} = $dataset;
    }

    return $self->{'_dataset'} ||=
        $self->dataset_default;
}

sub dataset_default {
    my ($self) = @_;
    my $dataset_name = $self->dataset_name;
    die "dataset_name not set" unless $dataset_name;
    my $dataset = $self->SpeciesDat->dataset($dataset_name);
    die "no dataset" unless $dataset;
    return $dataset;
}

sub dataset_name {
    die "no default dataset name";
}

sub otter_dba {
    my ($self, @args) = @_;

    if($self->{'_odba'} && !scalar(@args)) {   # cached value and no override
        return $self->{'_odba'};
    }

    my $adaptor_class = 'Bio::Vega::DBSQL::DBAdaptor';

    if(@args) { # let's check that the class is ok
        my $odba = shift @args;
        if(eval { $odba->isa($adaptor_class) }) {
            return $self->{'_odba'} = $odba;
        } else {
            die "The object you assign to otter_dba must be a '$adaptor_class'";
        }
    }

    return $self->{'_odba'} ||=
        $self->dataset->otter_dba;
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
