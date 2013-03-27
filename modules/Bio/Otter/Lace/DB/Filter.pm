
### Bio::Otter::Lace::DB::Filter

package Bio::Otter::Lace::DB::Filter;

use strict;
use warnings;

use Carp;

sub new {
    my ($pkg, %args) = @_;

    confess "filter_name must be supplied" unless $args{filter_name};

    my $self = bless {}, $pkg;

    foreach my $attrib (qw(filter_name wanted failed done gff_file process_gff is_stored)) {
        if (exists $args{$attrib}) {
            $self->$attrib($args{$attrib});
            delete $args{$attrib};
        }
    }

    confess "unexpected attributes: ", join(',', keys %args) if %args;

    return $self;
}

sub filter_name {
    my ($self, @args) = @_;
    ($self->{'filter_name'}) = @args if @args;
    my $filter_name = $self->{'filter_name'};
    return $filter_name;
}

sub wanted {
    my ($self, @args) = @_;
    ($self->{'wanted'}) = @args if @args;
    my $wanted = $self->{'wanted'};
    return $wanted;
}

sub failed {
    my ($self, @args) = @_;
    ($self->{'failed'}) = @args if @args;
    my $failed = $self->{'failed'};
    return $failed;
}

sub done {
    my ($self, @args) = @_;
    ($self->{'done'}) = @args if @args;
    my $done = $self->{'done'};
    return $done;
}

sub gff_file {
    my ($self, @args) = @_;
    ($self->{'gff_file'}) = @args if @args;
    my $gff_file = $self->{'gff_file'};
    return $gff_file;
}

sub process_gff {
    my ($self, @args) = @_;
    ($self->{'process_gff'}) = @args if @args;
    my $process_gff = $self->{'process_gff'};
    return $process_gff;
}

sub is_stored {
    my ($self, @args) = @_;
    ($self->{'is_stored'}) = @args if @args;
    my $is_stored = $self->{'is_stored'};
    return $is_stored;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::DB::Filter

=head1 DESCRIPTION

Represents the state of a filter column as stored
in the otter_filter table in the SQLite database.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
