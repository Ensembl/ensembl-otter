=head1 LICENSE

Copyright [2018-2020] EMBL-European Bioinformatics Institute

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

## MenuCanvasWindow::GenomicFeaturesWindow

package MenuCanvasWindow::GenomicFeaturesWindow;

use strict;
use warnings;
use Carp;
use Try::Tiny;
use base 'MenuCanvasWindow';

use Tk::NoPasteEntry;
use Tk::SmartOptionmenu;

use Bio::Otter::Lace::Client;
use Hum::Ace::Assembly;
use Hum::Ace::SeqFeature::Simple;
use Bio::Otter::ZMap::XML::SeqFeature::Simple;

my %strand_name = (
     1 => 'Fwd',
    -1 => 'Rev',
);

my $def_score = 0.5;

# --------------- order-encoded-strand manipulation subroutines ------------

sub order_coords_by_strand {
    my ($coord1, $coord2, $strand) = @_;

    my @strands = sort { ($a <=> $b)*$strand } ($coord1, $coord2);
    return @strands;
}

sub get_strand_from_order {
    my ($coord1, $coord2) = @_;

    return ($coord1>$coord2) ? -1 : 1;
}

# ---------------[EUCOMM]----------------

sub paste_eucomm_data {
    my ($self, $genomic_feature) = @_;

    my ($class, $name, $clip_start, $clip_end) =
      $self->class_object_start_end_from_clipboard;
    if ($class and $class ne 'Sequence') {
        return;
    }

    if ($clip_start > $clip_end) {
        ($clip_start, $clip_end) = ($clip_end, $clip_start);
    }

    # Parse the old otter exon IDs from the existing text field
    my $display_otter = {};
    my $text = $genomic_feature->{'display_label'} || '';
    foreach my $id (grep { /E\d{11}$/ } split /[^A-Z0-9]+/, $text) {
        $display_otter->{$id} = 1;
    }

    my ($otter, $start, $end, $strand, $exon_length) =
      $self->get_overlapping_exon_otter_id_start_end($name, $clip_start, $clip_end, $display_otter);

    # Don't change anything if search failed
    return unless $otter;

    ($genomic_feature->{fiveprime}, $genomic_feature->{threeprime})
        = order_coords_by_strand($start, $end, $strand);

    # Default the score to 1 if not set
    $genomic_feature->{score} ||= 1;

    my $count = keys %$otter;
    my $str = sprintf "%d exon%s phase %d from %s (%s)",
        $count,
        $count > 1 ? 's' : '',
        $exon_length % 3,
        $name,
        join(' ', sort keys %$otter);
    $genomic_feature->{'display_label'} = $str;

    return;
}

sub get_overlapping_exon_otter_id_start_end {
    my ($self, $name, $search_start, $search_end, $display_otter) = @_;

    #warn "Looking for CDS exons in '$name' that overlap $start -> $end";

    my $search_exon = Hum::Ace::Exon->new;
    $search_exon->start($search_start);
    $search_exon->end($search_end);

    my $subseq = $self->SessionWindow->get_SubSeq($name) or return;
    return unless $subseq->translation_region_is_set;

    my $strand = $subseq->strand();
    my $new_otter = {};
    my $exon_length_total = 0;
    my ($start, $end);
    my $in_zone = 0;
    #warn "Looking for $search_start - $search_end and (", join(', ', map "'$_'", keys %$display_otter), ")";
    foreach my $exon ($subseq->get_all_Exons) {
        my $id = $exon->otter_id
          or next;
        #warn "Looking at '$id'\n";
        if ($display_otter->{$id} or $exon->overlaps($search_exon)) {
            #warn "Found exon '$id'\n";
            $in_zone = 1;
            $new_otter->{$id} = 1;
            $exon_length_total += $exon->length;
            if ($start) {
                $start = $exon->start if $exon->start < $start;
            } else {
                $start = $exon->start;
            }
            if ($end) {
                $end = $exon->end if $exon->end > $end;
            } else {
                $end = $exon->end;
            }
        } else {
            # Makes it impossible to select non-consecutive exons
            last if $in_zone;
        }
    }
    if ($in_zone) {
        return ($new_otter, $start, $end, $strand, $exon_length_total);
    } else {
        return;
    }
}

# ---------------[getters/setters]----------------

sub SessionWindow{
    my ($self, $SessionWindow) = @_;
    if ($SessionWindow){

        $self->{'_SessionWindow'} = $SessionWindow;
    }
    return $self->{'_SessionWindow'} ;
}

sub AceDatabase {
    my ($self) = @_;

    return $self->SessionWindow->AceDatabase;
}

sub Assembly {
    my ($self) = @_;

    return $self->SessionWindow->Assembly;
}

sub get_all_Methods {
    my ($self) = @_;

    my $feat_meths;
    unless ($feat_meths = $self->{'_Method_objects'}) {
        $feat_meths = $self->{'_Method_objects'} = [];
        my $collection = $self->SessionWindow->Assembly->MethodCollection;
        @$feat_meths = $collection->get_all_mutable_non_transcript_Methods;
        $self->{'_Method_index'} = {map {$_->name, $_} @$feat_meths};
    }
    return @$feat_meths;
}

sub get_Method_by_name {
    my ($self, $name) = @_;

    my $method = $self->{'_Method_index'}{$name}
      or confess "No Method with name '$name'";
    return $method;
}

# -------------[create ace representation]---------------------


sub Assembly_from_tk {
    my ($self) = @_;

    my $old_assembly = $self->Assembly;

    my $new_assembly = Hum::Ace::Assembly->new;
    $new_assembly->name($old_assembly->name);
    $new_assembly->MethodCollection($old_assembly->MethodCollection);
    $new_assembly->Sequence($old_assembly->Sequence);
    ### Can copy more properties of old_assembly if needed

    my @sf_list;
    foreach my $hash (values %{$self->{'_gfs'}}) {
        try {
            my $feat = $self->SimpleFeature_from_gfs_hash($hash);
            push(@sf_list, $feat);            
        }
        catch {
            $self->exception_message($_);
        }
    }
    $new_assembly->set_SimpleFeature_list(@sf_list);

    return $new_assembly;
}

sub new_SimpleFeature_from_method_name {
    my ($self, $method_name) = @_;

    my $feat = Hum::Ace::SeqFeature::Simple->new;
    $feat->Method($self->get_Method_by_name($method_name));
    return $feat;
}

sub SimpleFeature_from_gfs_hash {
    my ($self, $hash) = @_;

    my $fiveprime  = $hash->{'fiveprime'}  or confess "missing left coordinate";
    my $threeprime = $hash->{'threeprime'} or confess "missing right coordinate";
    my $strand     = $hash->{'strand'}     or confess "strand not set";
    my $gf_type    = $hash->{'gf_type'}    or confess "Feature type not set";

    my $method = $self->get_Method_by_name($gf_type)
      or confess "Do not have method '$gf_type'";

    unless (defined($hash->{'display_label'}) and $hash->{'display_label'} =~ /\w/) {
        # Cannot have an empty name for a feature.  Default to feature type.
        $hash->{'display_label'} = $gf_type;
    }

    my $feat = $self->new_SimpleFeature_from_method_name($gf_type);
    if ($strand == 1) {
        $feat->seq_start($fiveprime);
        $feat->seq_end($threeprime);
    }
    else {
        $feat->seq_start($threeprime);
        $feat->seq_end($fiveprime);
    }
    $feat->seq_strand($strand);

    $feat->score($method->edit_score        ? $hash->{'score'}         : $def_score);
    $feat->text($method->edit_display_label ? $hash->{'display_label'} : $hash->{'gf_type'});

    return $feat;
}

# -------------[adding things]-------------------------------

sub create_genomic_feature {
    my ($self, $subframe, $feat) = @_;

    my $gf_type       = $feat->method_name;
    my $strand        = $feat->seq_strand || 1;
    my $score         = $self->get_Method_by_name($gf_type)->edit_score
                      ? $feat->score
                      : $def_score;
    my $display_label = $feat->text;

    my $fiveprime  = $strand == 1 ? $feat->seq_start : $feat->seq_end;
    my $threeprime = $strand == 1 ? $feat->seq_end   : $feat->seq_start;

    my $gfid =
      ++$self->{'_gfid'};    # will be uniquely identifying items in the list

    $self->{'_gfs'}{$gfid} = {
        'fiveprime'     => $fiveprime,
        'threeprime'    => $threeprime,
        'strand'        => $strand,
        'score'         => $score,
        'display_label' => $display_label,
        'gf_type'       => $gf_type,
        'subframe'      => $subframe,
    };

    return ($gfid, $self->{'_gfs'}{$gfid});
}

sub recalc_coords_callback {
    my ($self, $genomic_feature, $this_key) = @_;

    my $this_value = $genomic_feature->{$this_key};
    my $gf_type    = $genomic_feature->{'gf_type'};
    my $length     = $self->get_Method_by_name($gf_type)->valid_length;

    if ($length && ($this_value =~ /^\d+$/)) {

        my ($other_key, $diff_sign) =
          ($this_key eq 'fiveprime') ? ('threeprime', 1) : ('fiveprime', -1);

        $genomic_feature->{$other_key} =
          $this_value + $diff_sign * $genomic_feature->{strand} * ($length - 1);
    }

    return;
}

sub show_direction_callback {
    my ($genomic_feature) = @_;

    $genomic_feature->{direction_button}->configure(
        -text => $strand_name{$genomic_feature->{strand}}
    );

    return;
}

sub paste_label_callback {
    my ($self, $genomic_feature, $this, $x) = @_;

    if ($genomic_feature->{'gf_type'} eq 'EUCOMM') {
        $self->paste_eucomm_data($genomic_feature);
        return 1;
    }
    else {
        # We allow the Entry's built in paste behaviour.
        $genomic_feature->{$this}->Paste($x);
    }

    return;
}

sub paste_coords_callback {
    my ($self, $genomic_feature, $this) = @_;

    my @ints = $self->integers_from_clipboard();
    if (!@ints) {
        return;
    }

    my $length =
      $self->get_Method_by_name($genomic_feature->{gf_type})->valid_length;

    if (scalar(@ints) == 1) {    # trust the strand information:

        $this ||=
          ($genomic_feature->{strand} == 1) ? 'fiveprime' : 'threeprime';

        $genomic_feature->{$this} = shift @ints;
        if ($length) {
            $self->recalc_coords_callback($genomic_feature, $this);
        }

    }
    else {                       # acquire strand information:

        ($genomic_feature->{fiveprime}, $genomic_feature->{threeprime}) =
          ($ints[0], $ints[1]);
        $genomic_feature->{strand} = get_strand_from_order($ints[0], $ints[1]);

        show_direction_callback($genomic_feature);
    }

    return;
}

sub flip_direction_callback {
    my ($genomic_feature) = @_;

    $genomic_feature->{strand} *= -1;

    if( $genomic_feature->{fiveprime} && $genomic_feature->{threeprime} ) {
        ($genomic_feature->{fiveprime}, $genomic_feature->{threeprime}) = 
            order_coords_by_strand(map { $genomic_feature->{$_} } ('fiveprime', 'threeprime', 'strand'));
    } else { # just swap them
        ($genomic_feature->{fiveprime}, $genomic_feature->{threeprime}) =
            ($genomic_feature->{threeprime}, $genomic_feature->{fiveprime});
    }

    show_direction_callback($genomic_feature);

    return;
}

sub change_of_gf_type_callback {
    my ($self, $genomic_feature, $wanted_type) = @_;

    my $method = $self->get_Method_by_name($wanted_type);
    my @enable  = (-state => 'normal',   -background => 'white');
    my @disable = (-state => 'disabled', -background => 'grey' );

    unless ($method->edit_display_label) {
        $genomic_feature->{'display_label'} = $method->remark || $method->name;
    }

    $genomic_feature->{'score_entry'}
      ->configure($method->edit_score         ? @enable : @disable);
    $genomic_feature->{'display_label_entry'}
      ->configure($method->edit_display_label ? @enable : @disable);

    return;
}

sub add_genomic_feature {
    my ($self, $feat) = @_;

    # Frame to contain row
    my $subframe = $self->{_metaframe}->Frame()->pack(
        -fill   => 'x',
        -expand => 1,
    );

    my ($gfid, $genomic_feature) = $self->create_genomic_feature($subframe, $feat);

    my @pack = (-side => 'left', -padx => 2);

    # Popup menu for choosing type of feature
    $genomic_feature->{'gf_type_menu'} = $subframe->SmartOptionmenu(
       -options  => [ map { [ $_->remark => $_->name ] } ($self->get_all_Methods) ],
       -variable => \$genomic_feature->{'gf_type'},
       -command  => sub { $self->change_of_gf_type_callback($genomic_feature, shift @_); },
    )->pack(@pack);

    # Entry for "start" position
    $genomic_feature->{'fiveprime_entry'} = $subframe->NoPasteEntry(
       -textvariable => \$genomic_feature->{'fiveprime'},
       -width        => 7,
       -justify      => 'right',
    )->pack(@pack);
    my $recalc_fiveprime = sub { $self->recalc_coords_callback($genomic_feature, 'fiveprime'); };
    $genomic_feature->{'fiveprime_entry'}->bind('<Return>', $recalc_fiveprime);
    $genomic_feature->{'fiveprime_entry'}->bind('<Up>',     $recalc_fiveprime);
    $genomic_feature->{'fiveprime_entry'}->bind('<Down>',   $recalc_fiveprime);

    # Right or left pointing arrow for forward or reverse strand indicator
    $genomic_feature->{'direction_button'} = $subframe->Button(
        -command => sub { flip_direction_callback($genomic_feature); },
    )->pack(-side => 'left');
    show_direction_callback($genomic_feature); # show it once

    # Entry for "end" position
    $genomic_feature->{'threeprime_entry'} = $subframe->NoPasteEntry(
       -textvariable => \$genomic_feature->{threeprime},
       -width        => 7,
       -justify      => 'right',
    )->pack(@pack);
    my $recalc_threeprime = sub { $self->recalc_coords_callback($genomic_feature, 'threeprime'); };
    $genomic_feature->{'threeprime_entry'}->bind('<Return>', $recalc_threeprime);
    $genomic_feature->{'threeprime_entry'}->bind('<Up>',     $recalc_threeprime);
    $genomic_feature->{'threeprime_entry'}->bind('<Down>',   $recalc_threeprime);

    # Entry for score
    $genomic_feature->{'score_entry'} = $subframe->NoPasteEntry(
       -textvariable => \$genomic_feature->{score},
       -width        => 4,
    )->pack(@pack);

    # Delete button
    my $delete_button = $subframe->Button(
        -text    => 'Delete',
        -command => sub {
            $self->delete_genomic_feature($gfid);
            $self->set_scroll_region_and_maxsize;
            },
    )->pack(@pack);

    # Break circular reference caused by closure
    $delete_button->bind('<Destroy>', sub{ $self = undef });

    # Entry for display label / comment text
    $genomic_feature->{'display_label_entry'} = $subframe->NoPasteEntry(
       -textvariable => \$genomic_feature->{'display_label'},
       -width        => 24,
    )->pack(@pack);

    # Add callbacks for pasting and middle button paste
    foreach my $event ('<<Paste>>', '<Button-2>') {
        $genomic_feature->{'fiveprime_entry'}->bind(
            $event,
            sub {
                $self->paste_coords_callback($genomic_feature, 'fiveprime');
            }
        );
        $genomic_feature->{'threeprime_entry'}->bind(
            $event,
            sub {
                $self->paste_coords_callback($genomic_feature, 'threeprime');
            }
        );
        $genomic_feature->{'direction_button'}->bind(
            $event,
            sub {
                $self->paste_coords_callback($genomic_feature);
            }
        );
        $genomic_feature->{'display_label_entry'}->bind(
            $event,
            [
                sub {
                    my ($widget, $x) = @_;
                    $self->paste_label_callback($genomic_feature,
                        'display_label_entry', $x);
                },
                Tk::Ev('x') # Needed by default Entry paste handler
            ]
        );
    }

    ### I don't think we need a destroy for all of these?
    for my $widget ('fiveprime_entry', 'threeprime_entry', 'direction_button', 'display_label_entry') {
        $genomic_feature->{$widget}->bind('<Destroy>', sub{ $self = $genomic_feature = undef; } );
    }

    $self->change_of_gf_type_callback($genomic_feature, $feat->method_name);

    #    # unfortunately, you cannot bind these before the whole widget is made,
    #    # as it tends to activate the -command on creation
    #$genomic_feature->{gf_type_menu}->configure(
    #   -command => sub { change_of_gf_type_callback($genomic_feature, shift @_); },
    #);

    return;
}

sub load_genomic_features {
    my ($self) = @_;

    my $assembly = $self->Assembly;

    foreach my $feat ($assembly->get_all_SimpleFeatures) {
        $self->add_genomic_feature($feat);
    }

    $self->fix_window_min_max_sizes;

    return;
}

# -------------[removing things]-------------------------------

sub delete_genomic_feature {
    my ($self, $gfid) = @_;

    $self->{_gfs}{$gfid}{subframe}->packForget();
    delete $self->{_gfs}{$gfid};

    return;
}

sub clear_genomic_features {
    my ($self) = @_;

    for my $gfid (keys %{$self->{_gfs}}) {
        $self->delete_genomic_feature($gfid);
    }
    $self->{_gfs} = {};

    return;
}

# -------------[save if needed (+optional interactivity) ]-------------------

sub save_to_ace {
    my ($self, $force) = @_;

    my $new_assembly = $self->Assembly_from_tk;
    my $new_ace = $new_assembly->ace_string;

    if ($new_ace ne $self->Assembly->ace_string) {

        # Ok, we may need saving - but do we want it?
        unless ($force) {

            my $save_changes = $self->top_window->messageBox(
                -title      => $Bio::Otter::Lace::Client::PFX.'Save Genomic Features?',
                -message    => "Do you wish to save the changes for '" . $new_assembly->name . "'?",
                -type       => 'YesNo',
                -icon       => 'question',
                -default    => 'Yes',
            );

            if ($save_changes eq 'No') {
                return;
            }
        }

        $self->SessionWindow->save_Assembly($new_assembly);
    }

    return;
}

# ---[attempt to save if needed, then destroy the window]------

sub try2save_and_quit {
    my ($self) = @_;

    if($self->SessionWindow()) {
        $self->save_to_ace(0); # '0' means do it interactively
    } else {
        warn "No SessionWindow, nowhere to write\n";
    }

    $self->top_window->destroy();

    return;
}

# -------------[fill it in]------------------------------------

sub initialise {
    my ($self) = @_;

    my $top_window = $self->top_window();

    my $file_menu = $self->make_menu('File');
    my $reload = sub {
        $self->clear_genomic_features();
        $self->load_genomic_features()
        };
    $file_menu->command(
        -label          => 'Reload',
        -command        => $reload,
        -accelerator    => 'Ctrl+R',
        -underline      => 1,
    );
    $top_window->bind('<Control-R>', $reload) ;
    $top_window->bind('<Control-r>', $reload) ;

    my $save = sub { $self->save_to_ace(1); }; # '1' means skip interactivity
    $file_menu->command(
        -label          => 'Save',
        -command        => $save,
        -accelerator    => 'Ctrl+S',
        -underline      => 1,
    );    
    $top_window->bind('<Control-S>', $save);
    $top_window->bind('<Control-s>', $save);

    my $close_command = $self->bind_WM_DELETE_WINDOW('try2save_and_quit');
    $file_menu->command(
        -label          => 'Close',
        -command        => $close_command,
        -accelerator    => 'Ctrl+W',
        -underline      => 1,
    );
    $top_window->bind('<Control-W>', $close_command);
    $top_window->bind('<Control-w>', $close_command);

    my $add_menu = $self->make_menu('Add feature');
    foreach my $method ($self->get_all_Methods) {
        my $gf_type  = $method->name;
        my $fullname = $method->remark;
        my $length   = $method->valid_length;

        $add_menu->command(
            -label   => $fullname.($length ? " (${length}bp)" : ''),
            -command => sub {
                my $feat = $self->new_SimpleFeature_from_method_name($gf_type);
                $self->add_genomic_feature($feat);
                # $self->fix_window_min_max_sizes;
                $self->set_scroll_region_and_maxsize;

                # Scroll window so new widgets are visible
                $self->canvas->yviewMoveto(1);
                },
        );
    }

    if(! $self->AceDatabase->write_access()) {
        $self->menu_bar()->Label(
            -text       => 'Read Only',
            -foreground => 'red',
            -padx       => 6,
        )->pack(
            -side       => 'right',
        );
    }

    $self->{_metaframe} = $self->canvas->Frame();
    $self->canvas->createWindow( 5, 5,
        -window => $self->{_metaframe},
        -anchor => 'nw',
        -tags => 'metaframe',
    );
    $self->canvas->configure(-background => $self->{_metaframe}->cget('-background') );

    $self->_colour_init;
    $self->load_genomic_features();


    my $tl = $self->top_window;
    $tl->title($Bio::Otter::Lace::Client::PFX.
               'Genomic Features on '. $self->Assembly->name);

    $self->canvas->Tk::bind('<Destroy>', sub{ $self = undef });

    return;
}

sub _colour_init {
    my ($self) = @_;
    return $self->SessionWindow->colour_init($self->top_window);
}

1;

__END__

=head1 NAME - MenuCanvasWindow::GenomicFeaturesWindow

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

