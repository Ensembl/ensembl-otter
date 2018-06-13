=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


### Bio::Otter::Lace::Chooser::SearchHistory

package Bio::Otter::Lace::Chooser::SearchHistory;

use strict;
use warnings;
use Carp;

use Bio::Otter::Lace::Chooser::Collection;

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

sub root_Collection {
    my ($self) = @_;

    return $self->{'_collection_list'}[0];
}

sub snail_trail_text {
    my ($self) = @_;

    my $i = $self->{'_index'};
    my @trail = map { $_->search_string } @{$self->{'_collection_list'}};
    $trail[$i] = "{ $trail[$i] }";  # Current term is in the edit field        
    return 'Filter trail: ' . join(' > ', @trail);
}

sub index_and_search_string_list {
    my ($self) = @_;

    my @trail = map { $_->search_string } @{$self->{'_collection_list'}};
    $trail[-1] = '...';    # Last element will always be empty
    return ($self->{'_index'}, @trail);
}

sub reset_search {
    my ($self) = @_;

    my $cllctn_list = $self->{'_collection_list'};
    splice(@$cllctn_list, 1, @$cllctn_list - 1);
    $self->{'_index'} = 0;
    $self->current_Collection->search_string('');
    return 1;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::Chooser::SearchHistory

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

