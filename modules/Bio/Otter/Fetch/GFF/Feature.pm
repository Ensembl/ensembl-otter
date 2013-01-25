
### Bio::Otter::Fetch::GFF::Feature

package Bio::Otter::Fetch::GFF::Feature;

use strict;
use warnings;

use Carp;

# constructor

sub new {
    my ($pkg, $line) = @_;
    my $new = bless { }, $pkg;
    $new->_init($line);
    return $new;
}

sub _init {
    my ($self, $line) = @_;
    my ($seq_id, $source, $type, $start, $end, @rest) = split "\t", $line;
    @rest or croak sprintf "truncated line: '%s'", $line;
    @{$self}{qw( seq_id source type start end rest )} =
        ( $seq_id, $source, $type, $start, $end, \@rest );
    return;
}

# attributes

sub seq_id {
    my ($self) = @_;
    my $seq_id = $self->{'seq_id'};
    return $seq_id;
}

sub source {
    my ($self) = @_;
    my $source = $self->{'source'};
    return $source;
}

sub type {
    my ($self) = @_;
    my $type = $self->{'type'};
    return $type;
}

sub start {
    my ($self) = @_;
    my $start = $self->{'start'};
    return $start;
}

sub end {
    my ($self) = @_;
    my $end = $self->{'end'};
    return $end;
}

sub rest {
    my ($self) = @_;
    my $rest = $self->{'rest'};
    return $rest;
}

1;

__END__

=head1 NAME - Bio::Otter::Fetch::GFF::Feature

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

