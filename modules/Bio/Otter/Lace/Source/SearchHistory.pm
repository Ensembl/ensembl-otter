
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
    my ($self, $search_string) = @_;

    unless (defined $search_string and $search_string =~ /\S/) {
        return;
    }

    my $i = \$self->{'_index'};
    my $cllctn_list = $self->{'_collection_list'};
    my $cllctn = $cllctn_list->[$$i];
    return unless $cllctn->list_Items;
    $cllctn->search_string($search_string);
    $$i++;
    my $new_cllctn = $cllctn->filter($cllctn_list->[$$i]);
    splice(@{$self->{'_collection_list'}}, $$i, 1, $new_cllctn);
    return $new_cllctn;
}

sub back {
    my ($self) = @_;

    my $i = \$self->{'_index'};
    if ($$i == 0) {
        return; # Already at start
    }
    else {
        $$i--;
        return $self->{'_collection_list'}[$$i];        
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
        return 'Column list is unfiltered';
    }
    else {
        return 'Filtered on: ' . join(' > ',
            map $_->search_string,
            @{$self->{'_collection_list'}}[0 .. $self->{'_index'} - 1]
            );
    }
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::Source::SearchHistory

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

