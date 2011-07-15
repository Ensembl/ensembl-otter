
### Bio::Otter::BAM

package Bio::Otter::BAM;

use strict;
use warnings;

use Carp;

use URI::Escape qw( uri_escape );

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

# source methods

sub featuresets {
    my ($self) = @_;
    return [ $self->name ];
}

sub zmap_column { return; }
sub zmap_style  { return 'feat'; }

sub delayed {
    return 1;
};

sub url {
    my ($self, $session) = @_;
    my $query_string = _query_string($self->url_query($session));
    return sprintf "pipe:///%s?%s", $self->script_name, $query_string,
}

sub script_name {
    return "bam_get";
}

my $bam_parameters = [
    #     key                method (optional)
    [ qw( bam_path           file  ) ],
    [ qw( bam_cs             csver ) ],
    [ qw( gff_feature_source name  ) ],
    qw(
          chr_prefix
    ),
    ];

sub bam_parameters {
    return $bam_parameters;
}

my $slice_parameters = [
    #   key
    [ qw( chr  ssname ) ],
    qw(
        start
        end
    ) ];

sub url_query {
    my( $self, $session ) = @_;
    my $slice = $session->smart_slice;
    my $query = {
        _query($self,  $bam_parameters),
        _query($slice, $slice_parameters),
        gff_version => 2,
    };
    return $query;
}

# NB: the following subroutines are *not* methods

sub _query_string {
    my ($query) = @_;
    my $arguments = [ ];
    for my $key (sort keys %{$query}) {
        my $value = $query->{$key};
        next unless defined $value;
        $key = "-${key}";
        push @{$arguments}, join "=", uri_escape($key), uri_escape($value);
    }
    my $query_string = join '&', @{$arguments};
    return $query_string;
}

sub _query {
    my ($obj, $parameters) = @_;
    return map { _query_pair($obj, ref $_ ? @{$_} : $_ ) } @{$parameters};
}

sub _query_pair {
    my ($obj, $key, $method) = @_;
    $method ||= $key;
    my $value = $obj->$method;
    return ( $key, $value );
}

1;

__END__

=head1 NAME - Bio::Otter::BAM

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

