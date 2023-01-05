=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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


### Bio::Otter::Lace::Chooser::Collection

package Bio::Otter::Lace::Chooser::Collection;

use strict;
use warnings;
use Carp;
use Text::ParseWords qw{ quotewords };
use Hum::Sort qw{ ace_sort array_ace_sort };
use Bio::Otter::Lace::Chooser::Item::Bracket;
use Bio::Otter::Lace::Chooser::Item::Column;

sub new {
    my ($pkg) = @_;

    my $new = {
        '_item_list'        => [],
        '_search_string'    => '',
    };

    return bless $new, $pkg;
}

sub new_from_Filter_list {
    my ($pkg, @list) = @_;

    @list = sort { array_ace_sort([$a->classification], [$b->classification])
                   || ace_sort($a->name, $b->name) } @list;

    my $self = Bio::Otter::Lace::Chooser::Collection->new;
    my $bkt_path = [];
    foreach my $filter (@list) {
        my $col = Bio::Otter::Lace::Chooser::Item::Column->new;
        $col->name($filter->name);
        $col->Filter($filter);
        $col->selected($filter->wanted);

        my @new_bkt = __maintain_Bracket_array($bkt_path, [ $filter->classification ]);
        foreach my $bkt (@new_bkt) {
            $self->add_Item($bkt);
        }

        $col->indent(@$bkt_path || 0);
        $self->add_Item($col);
    }
    $self->update_all_Bracket_selection;

    return $self;
}

sub __maintain_Bracket_array {
    my ($bkt_path, $clss) = @_;

    my @new_bkt;
    my $disabled;
    for (my $i = 0; $i < @$clss; $i++) {

        my $name =     $clss->[$i];
        if ($name =~ /^~/) { # e.g. ~ Otter  - leading ~ denotes disabled, denotes system, and sorts after alphanum.
            $disabled = 1;
        }

        my $bkt  = $bkt_path->[$i];

        # Since shorter classification arrays sort before longer ones
        # we don't need to deal with shortening the array of Brackets
        # if the classification list is shorter than the array of
        # Brackets, since it must contain a new name.
        unless (($bkt && defined($name)) && lc($bkt->name) eq lc($name)) {
            $bkt = Bio::Otter::Lace::Chooser::Item::Bracket->new;
            $bkt->name($name);  # We use the capitalisation of the fist occurrence of this name
            $bkt->disabled($disabled);
            $bkt->indent($i);
            # Clip array at this postion and replace with new Bracket
            splice(@$bkt_path, $i, @$bkt_path - $i, $bkt);
            push(@new_bkt, $bkt);
        }
    }

    return @new_bkt;
}

sub search_string {
    my ($self, $search_string) = @_;

    if (defined $search_string) {
        $self->{'_search_string'} = $search_string;
        $self->construct_regex_list;
    }
    return $self->{'_search_string'};
}

sub construct_regex_list {
    my ($self) = @_;

    # Make a fresh new reference
    my $r_list = $self->{'_regex_list'} = [];

    my $string = $self->search_string;
    $string =~ s{\\}{\\\\};     # So that perl regex escapes survive quotewords()
    foreach my $term (quotewords('\s+', 0, $string)) {
        my $test = 1;
        if ($term ne '-' && $term =~ s/^-//) {
            $test = 0;
        }
        push(@$r_list, [$test, qr{$term}im]);
    }

    return;
}

sub regex_list {
    my ($self) = @_;

    my $r_list = $self->{'_regex_list'}
        or confess "No regex list - construct_regex_list() not called?";
    return @$r_list;
}

sub add_Item {
    my ($self, $item) = @_;

    my $name = $item->name or confess "No name in item";
    if (not $item->is_Bracket) { # Column
        $self->get_Column_by_name($name) and confess "Already have column named '$name'";
        $self->{'_columns_by_name'}{$name} = $item;
    }

    my $i_ref = $self->{'_item_list'};
    push @$i_ref, $item;

    return;
}

sub get_Column_by_name {
    my ($self, $name) = @_;

    return $self->{'_columns_by_name'}{$name};
}

sub list_Items {
    my ($self) = @_;

    if (my $i_ref = $self->{'_item_list'}) {
        return @$i_ref;
    }
    else {
        return;
    }
}

sub list_Items_exclude_internal {
    my ($self) = @_;
    return grep { $_->is_Bracket or not $_->internal_type } $self->list_Items;
}

sub list_Brackets {
    my ($self) = @_;

    return grep { $_->is_Bracket } $self->list_Items;
}

sub list_Columns {
    my ($self) = @_;

    return grep { ! $_->is_Bracket } $self->list_Items;
}

sub list_Columns_with_status {
    my ($self, @statuses) = @_;

    my @all_columns = $self->list_Columns;
    my @columns;

    foreach my $status (@statuses) {
        Bio::Otter::Lace::Chooser::Item::Column->confess_if_not_valid_status($status);
        push @columns, grep { $_->status eq $status } @all_columns;
    }
    return @columns;
}

sub segment_Columns_by_status {
    my ($self) = @_;
    my %by_status;
    map { push @{$by_status{$_->status} ||= []}, $_ } $self->list_Columns;
    return \%by_status;
}

sub count_Columns_by_status {
    my ($self) = @_;
    my %count_by_status;
    my $by_status = $self->segment_Columns_by_status;
    map { $count_by_status{$_} = scalar(@{$by_status->{$_}}) } keys %$by_status;
    return \%count_by_status;
}

sub list_Columns_with_internal_type {
    my ($self, @internal_types) = @_;

    my @all_columns = $self->list_Columns;
    my @columns;

    foreach my $internal_type (@internal_types) {
        push @columns, grep { my $it = $_->internal_type; $it and $it eq $internal_type } @all_columns;
    }
    return @columns;
}

sub save_Columns_selected_flag_to_Filter_wanted {
    my ($self) = @_;

    foreach my $col ($self->list_Columns) {
        $col->Filter->wanted($col->selected);
    }

    return;
}

sub clear_Items {
    my ($self) = @_;

    $self->{'_item_list'} = [];
    $self->{'_columns_by_name'} = {};
    $self->{'_is_matched'} = {};
    $self->{'_is_collapsed'} = {};
    return;
}

sub list_visible_Items {
    my ($self) = @_;

    my $hide_level = 0;
    my @all = $self->list_Items;
    my @visible;
    while (my $item = shift @all) {
        push @visible, $item;
        if ($self->is_collapsed($item)) {
            my $level = $item->indent;
            # Remove everything inside this Bracket from the list
            while (my $item = shift @all) {
                if ($item->indent <= $level) {
                    # We're back outside the Bracket. Put this one back.
                    unshift(@all, $item);
                    last;
                }
            }
        }
    }
    return @visible;
}

sub is_matched {
    my ($self, $item, $flag) = @_;

    if (defined $flag) {
        $self->{'_is_matched'}{$item} = $flag ? 1 : 0;
    }
    return $self->{'_is_matched'}{$item};
}

sub is_collapsed {
    my ($self, $item, $flag) = @_;

    if (defined $flag) {
        confess "Not a Bracket" unless $item->is_Bracket;
        $self->{'_is_collapsed'}{$item} = $flag ? 1 : 0;
    }
    return $self->{'_is_collapsed'}{$item};
}

sub get_Bracket_contents {
    my ($self, $bracket) = @_;

    confess "Not a Bracket: $bracket" unless $bracket->is_Bracket;

    my @item_list = $self->list_Items;
    while (my $item = shift @item_list) {
        last if $item == $bracket;
    }
    my @contents;
    while (my $item = shift @item_list) {
        last if $item->indent <= $bracket->indent;
        push(@contents, $item);
    }
    return @contents;
}

sub select_Bracket {
    my ($self, $bracket) = @_;

    my $flag = $bracket->selected;
    foreach my $item ($self->get_Bracket_contents($bracket)) {
        $item->selected($flag);
    }

    return;
}

sub update_all_Bracket_selection {
    my ($self) = @_;

    my @item_list = $self->list_Items_exclude_internal; # should this be all??
    my @bracket_path;
    my $skip_to_next_bracket = 0;
    while (my $item = shift @item_list) {
        if ($item->is_Bracket) {
            $item->selected(1);
            $skip_to_next_bracket = 0;
            splice(@bracket_path, $item->indent, @bracket_path - $item->indent, $item);
        }
        elsif (! $skip_to_next_bracket && ! $item->selected) {
            # There's an unselected column at this level, so
            # unselect all brackets down to this level 
            foreach my $bkt (@bracket_path) {
                $bkt->selected(0);
            }
            $skip_to_next_bracket = 1;
        }
    }

    return;
}

sub filter {
    my ($self, $new) = @_;

    if ($new) {
        $new->clear_Items;
    }
    else {
        $new = ref($self)->new;
    }

    my @tests = $self->regex_list;
    my @item_list = $self->list_Items;
    my @hit_i;
    for (my $i = 0; $i < @item_list; $i++) {
        if (defined $hit_i[$i]) {
            # Already included or excluded as part of a bracket.
            next;
        }
        my $item = $item_list[$i];

        my $hit  = 0;
        my $miss = 0;
        foreach my $t (@tests) {
            my ($true, $regex) = @$t;
            if ($item->string =~ /$regex/) {
                if ($true) {
                    $hit = 1;
                }
                else {
                    $miss = 1;
                }
                last;
            }
            elsif (! $true && ! $item->is_Bracket) {
                # Keep each column which doesn't match negated search terms
                $hit = 1;
                last;
            }
        }

        if ($hit or $miss) {
            $hit_i[$i] = $hit ? 1 : 0;
            $new->is_matched($item, 1);
            my $this_indent = $item->indent;
            if ($item->is_Bracket) {
                # Flag every following item with an indent great than this
                for (my $j = $i + 1; $j < @item_list; $j++) {
                    my $other = $item_list[$j];
                    if ($other->indent > $this_indent) {
                        $hit_i[$j] = $hit ? 1 : 0;
                    }
                    else {
                        # We're back to an item at the same level as the match
                        last;
                    }
                }
            }
            # Add every prevous Bracket with an intent less than this so that
            # the new collection has all the branches which lead to this node.
            if ($hit) {
                for (my $j = $i - 1; $j >= 0; $j--) {
                    my $other = $item_list[$j];
                    if ($other->is_Bracket) {
                        my $other_indent = $other->indent;
                        if ($other_indent < $this_indent) {
                            $hit_i[$j] = 1;
                            $this_indent--;     # or we would add all brackets at highter level!
                        }
                        last if $other_indent == 0;
                    }
                }
            }
        }
    }

    # Loop through @hit_i because it will usually be shorter than @item_list
    for (my $i = 0; $i < @hit_i; $i++) {
        if ($hit_i[$i]) {
            # Copy matched item into new object
            my $item = $self->{'_item_list'}[$i];
            $new->add_Item($item);
        }
    }
    return $new;
}

sub expand_all {
    my ($self) = @_;

    foreach my $bracket (grep { $_->is_Bracket } $self->list_Items) {
        $self->is_collapsed($bracket, 0);
    }

    return;
}

sub collapse_all {
    my ($self) = @_;

    foreach my $bracket (grep { $_->is_Bracket } $self->list_Items) {
        $self->is_collapsed($bracket, 1);
    }

    return;
}

sub select_default {
    my ($self) = @_;

    foreach my $col ($self->list_Columns) {
        $col->selected($col->Filter->wanted_default);
    }
    $self->update_all_Bracket_selection;

    return;
}

sub select_all {
    my ($self) = @_;

    foreach my $item ($self->list_Items_exclude_internal) {
        $item->selected(1);
    }

    return;
}

sub select_none {
    my ($self) = @_;

    foreach my $item ($self->list_Items_exclude_internal) {
        $item->selected(0);
    }

    return;
}

sub select_by_status {
    my ($self, $status) = @_;

    foreach my $col ($self->list_Columns_with_status($status)) {
        $col->selected(1, { force => 1 });
    }

    return;
}

sub set_search_entry {
    my ($self, $string) = @_;

    $self->{'_entry_search_string'} = $string;
    $self->{'_search_Entry'}->icursor('end');    

    return;
}


1;

__END__

=head1 NAME - Bio::Otter::Lace::Chooser::Collection

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

