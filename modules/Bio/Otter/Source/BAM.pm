
### Bio::Otter::Source::BAM

package Bio::Otter::Source::BAM;

use strict;
use warnings;

use Carp;
use URI;
use URI::Escape qw( uri_escape );

use base 'Bio::Otter::Source';

my @keys = qw( description file csver );

sub new {
    my ($pkg, $name, $config) = @_;

    for (@keys) {
        confess "missing BAM configuration parameter: $_"
            unless defined $config->{$_};
    }

    my $self = { name => $name, %{$config} };
    bless $self, $pkg;

    if (my $class = delete $self->{classification}) {
        $self->classification($class);
    }

    return $self;
}

sub parent_column {
    my ($self) = @_;
    return $self->{parent_column};
}

sub parent_featureset {
    my ($self) = @_;
    return $self->{parent_featureset};
}

sub coverage_plus {
    my ($self) = @_;
    return $self->{coverage_plus};
}

sub coverage_minus {
    my ($self) = @_;
    return $self->{coverage_minus};
}

# source methods

sub featuresets {
    my ($self) = @_;
    return [ $self->name ];
}

sub zmap_style  { return 'short-read'; }

sub content_type { return; }

sub _url_query_string { ## no critic(Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self, $session) = @_;
    return _query_string($self->url_query($session));
}

sub script_name {
    return "bam_get";
}

# GFF methods

my $bam_parameters = [
    qw(
        file
        gff_source
        ),
    [ qw( csver csver_remote ) ],
    ];

sub url_query {
    my ($self, $session) = @_;
    my $slice = $session->slice;
    my $DataSet = $session->DataSet;
    my $query = {
        chr   => $slice->ssname,
        start => $slice->start,
        end   => $slice->end,
        dataset => $DataSet->name,
        ( map { $self->_param_value($_) } @{$bam_parameters} ),
        gff_version => $DataSet->gff_version,
    };
    return $query;
}

# Resource bins

sub init_resource_bin {
    my ($self) = @_;

    my $resource_bin = $self->resource_bin;
    $resource_bin and return $resource_bin; # already explicitly set

  SWITCH: {
      my $uri = URI->new($self->file);
      if ($uri->can('host')) {
          $resource_bin = $uri->host and last SWITCH; # use host if it's set
      }
      my @path_segs = $uri->path_segments;
      $resource_bin = $path_segs[0] and last SWITCH; # relative, use first seg
      $resource_bin = $path_segs[1] and last SWITCH; # absolute, use first seg ([0] will be undef for leading /)
      $resource_bin = $self->file;                   # fallback
    }
    # warn "setting '", $self->name, "' resource_bin to: '", $resource_bin, "'\n";
    return $self->resource_bin($resource_bin);
}

# NB: the following subroutines are *not* methods

sub _query_string {
    my ($query) = @_;
    my $arguments = [ ];
    for my $key (sort keys %{$query}) {
        my $value = $query->{$key};
        next unless defined $value;
        push @{$arguments}, sprintf '--%s=%s', $key, uri_escape($value);
    }
    my $query_string = join '&', @{$arguments};
    return $query_string;
}

1;

__END__

=head1 NAME - Bio::Otter::Source::BAM

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

