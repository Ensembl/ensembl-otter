
### Bio::Otter::Lace::DB::OTFRequest

package Bio::Otter::Lace::DB::OTFRequest;

use strict;
use warnings;

sub new {
    my ($pkg, %args ) = @_;
    my $self = bless { %args }, $pkg;
    return $self;
}

sub id {
    my ($self, @args) = @_;
    ($self->{'id'}) = @args if @args;
    my $id = $self->{'id'};
    return $id;
}

sub logic_name {
    my ($self, @args) = @_;
    ($self->{'logic_name'}) = @args if @args;
    my $logic_name = $self->{'logic_name'};
    return $logic_name;
}

sub target_start {
    my ($self, @args) = @_;
    ($self->{'target_start'}) = @args if @args;
    my $target_start = $self->{'target_start'};
    return $target_start;
}

sub command {
    my ($self, @args) = @_;
    ($self->{'command'}) = @args if @args;
    my $command = $self->{'command'};
    return $command;
}

sub completed {
    my ($self, @args) = @_;
    my $completed;
    if (@args) {
        ($completed) = @args;
        $completed //= 0;
        $self->{'completed'} = $completed;
    }
    $completed = $self->{'completed'} // 0;
    return $completed;
}

sub n_hits {
    my ($self, @args) = @_;
    ($self->{'n_hits'}) = @args if @args;
    my $n_hits = $self->{'n_hits'};
    return $n_hits;
}

sub is_stored {
    my ($self, @args) = @_;
    ($self->{'is_stored'}) = @args if @args;
    my $is_stored = $self->{'is_stored'};
    return $is_stored;
}

sub args {
    my ($self, @args) = @_;
    ($self->{'args'}) = @args if @args;
    my $args = $self->{'args'};
    return $args;
}

sub missed_hits {
    my ($self, @args) = @_;
    ($self->{'missed_hits'}) = @args if @args;
    my $missed_hits = $self->{'missed_hits'};
    return $missed_hits;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::DB::OTFRequest

=head1 DESCRIPTION

Represents the state of an OTF request as stored
in the otter_otf_request table in the SQLite db.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
