
### Bio::Otter::Lace::Source::SearchHistory

package Bio::Otter::Lace::Source::SearchHistory;

use strict;
use warnings;
use Carp;

use Bio::Otter::Lace::Source::Collection;

sub new {
    my ($pkg, $cllctn) = @_;

    confess "No Collection object" unless $cllctn;

    return bless {
        _collection_list    => [$cllctn],
        _index              => 0,
    }, $pkg;
}

sub search {
    my ($self) = @_;

    my $i = $self->{'_index'};
    my $cllctn_list = $self->{'_collection_list'};
    my $cllctn = $cllctn_list->[$i];
    my $new_cllctn = $cllctn->filter($cllctn_list->[$i + 1]);
    push(@{$self->{'_collection_list'}}, $new_cllctn);
    $self->{'_index'}++;
    return $new_cllctn;
}

sub back {
    my ($self) = @_;

    my $i = $self->{'_index'};
    if ($i == 0) {
        return; # Already at start
    }
    else {
        $i--;
        $self->{'_index'} = $i;
        return $self->{'_collection_list'}[$i];        
    }
}

sub current_Collection {
    my ($self) = @_;

    return $self->{'_collection_list'}[$self->{'_index'}];
}

sub snail_trail_text {
    my ($self) = @_;

    my $i = $self->{'_index'};
    if ($i == 0) {
        return '';
    }
    else {
        return join ' > ', map $_->search_string, @{$self->{'_collection_list'}}[0 .. $self->{'_index'} - 1];
    }
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::Source::SearchHistory

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

