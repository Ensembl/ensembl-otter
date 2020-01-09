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

package Evi::EviDisplay;

# A window showing a transcript and supporting evidence
#
# lg4

use strict;

my $bind_ok = 1;

my $ystep = 16;
my $abs_arrow_length   = 2;   # in pixels
my $rel_exon_thickness = 0.5; # in practice - from 0.1 to 0.9
my $half_delta  = $ystep*$rel_exon_thickness/2;

my $current_contour_color = 'red';
my $selection_color    = '#ffe4b5';
my $highlighting_color = 'yellow';

my @alternating_colors = ('white','#eeeeee');

my $color_scheme = {      #  OUTLINE,       FILL
    'transcript'       => [ 'orange',       'red'       ],

    # 'translation'      => [ 'DarkGreen',  'green'     ],

    'Est2genome_human' => [ 'blue',         'violet'    ],
    'Est2genome_mouse' => [ 'blue',         'violet'    ],
    'Est2genome_other' => [ 'blue',         'violet'    ],
    'vertrna'          => [ 'black',        '#a05000'   ],

    # 'Uniprot'        => [ 'DarkGreen',    'green'     ],

    'frame_0'          => ['DarkGreen',     '#3cb371' ], # #32cd32
    'frame_1'          => ['darkblue',      '#00ced1' ],
    'frame_2'          => ['darkblue',      '#8470ff' ],
};

my $type_to_optpairs = { # canvas-dependent stuff
    'line'      => [ ['-fill','-disabledfill'] ],
    'text'      => [ ['-fill','-disabledfill'] ],
    'rectangle' => [ ['-fill','-disabledfill'], ['-outline','-disabledoutline'] ],
    'polygon'   => [ ['-fill','-disabledfill'], ['-outline','-disabledoutline'] ],
};

use Evi::CF_Set;            # a list of CollectionFilters
use Evi::SortFilterDialog;  # window that selects the sorting order

use Evi::LogicalSelection;  # keeps the information about selection and visibility

use Evi::ScaleQuantum;      # a scaler that exaggerates the small differences in lengths
use Evi::ScaleMinexon;      # a scaler that limits the minimum length of an exon
use Evi::ScaleFitwidth;     # a scaler that fits everything into given width

use Tk::ROText;             # for the status line
use MenuCanvasWindow;       # recommended self-resizing window mgr
use Tk::HeadedCanvas;

use Evi::Tictoc;            # a simple stopwatch

use Evi::BlixemLauncher;    # the name says it all

use base ('MenuCanvasWindow',
    'Tk::DestroyReporter',     # we want to track the destruction event
    'Evi::BlackSpot',           # and be able to break the links
);

sub after_filtering_sorting_callback {
    my $self = shift @_;

    $self->{_evichains_lp} = $self->{_cfset}->results_lp();

    $self->evi_redraw();
}

sub new {
    my $pkg = shift @_;

    my $parentwindow            = shift @_;
    my $title                   = shift @_;

        # create the window with widgets
    my $top_window = $parentwindow->Toplevel(-title => $title);
    my $self = $pkg->SUPER::new($top_window,undef,undef,'','HeadedCanvas');

    $self->{_evicoll}           = shift @_;
    $self->{_transcript}        = shift @_;

    $self->{_scale_type}        = shift @_ || 'Evi::ScaleFitwidth';

    $self->{_cfset} = Evi::CF_Set->new( $self->{_evicoll} ); # we use the default_filterlist
    $self->{_cfset}->current_transcript( $self->{_transcript} ); # may be changed later

    $self->{_sortfilterdialog} = Evi::SortFilterDialog->new(
                $top_window,
                "$title| Sort data",
                $self->{_cfset},
                $self,
                'after_filtering_sorting_callback'
    );

    $self->{_lselection}        = Evi::LogicalSelection->new($self->{_evicoll},$self->{_transcript});

    $self->{_statusline} = $top_window->ROText(-height=>1)->pack(-side => 'bottom');

    $self->{_blixem} = Evi::BlixemLauncher->new($self->{_evicoll}->pipeline_slice(),$self->{_transcript});

    my $menu_file = $self->make_menu('File');
    $menu_file->command(
        -label      => 'Save and exit',
        -command    => [ \&exit_callback, ($self, 1, 0) ],
    );
    $menu_file->command(
        -label      => 'Exit without saving',
        -command    => [ \&exit_callback, ($self, 0, 0) ],
    );

    my $menu_data = $self->make_menu('Data');
    $menu_data->command(
        -label      => 'Change ~sorting/filtering order ...',
        -command => [ $self->{_sortfilterdialog} => 'open' ],
    );

    my $menu_view = $self->make_menu('View');
    $menu_view->command(
        -label   => 'Launch Nucleotide Blixem',
        -command => [ \&launch_blixem_callback, ($self, 1) ],
    );
    $menu_view->command(
        -label   => 'Launch Protein Blixem',
        -command => [ \&launch_blixem_callback, ($self, 3) ],
    );
    $menu_view->separator();
    $menu_view->radiobutton(
        -label  => '~Proportional view',
        -value  => 'Evi::ScaleFitwidth',
        -variable => \$self->{_scale_type},
        -command => [ \&evi_redraw, ($self) ],
    );
    $menu_view->radiobutton(
        -label  => '~Quantum view',
        -value  => 'Evi::ScaleQuantum',
        -variable => \$self->{_scale_type},
        -command => [ \&evi_redraw, ($self) ],
    );
if(0) {
    $menu_view->radiobutton(
        -label  => '~MinExon view',
        -value  => 'Evi::ScaleMinexon',
        -variable => \$self->{_scale_type},
        -command => [ \&evi_redraw, ($self) ],
    );
    $menu_view->radiobutton(
        -label  => '~Proportional 1:1 view',
        -value  => 'Evi::ScaleBase',
        -variable => \$self->{_scale_type},
        -command => [ \&evi_redraw, ($self) ],
    );
}

    $self->{_menu_selection} = $self->make_menu('Selection');

    $top_window->protocol('WM_DELETE_WINDOW', [ $self => 'exit_callback', 1, 1 ]);

    $self->after_filtering_sorting_callback(); # "activate the sorting"

    return $self;
}

sub exit_callback {
    my ($self, $save, $interactive) = @_;

    if($save && $self->{_lselection}->any_changes_in_selection()) {
        warn "There were changes in the selection";
        if(!$interactive || ($self->top_window()->messageBox(
                                -title => 'Please reply',
                                -message => 'Do you want to save the changes?',
                                -type => 'YesNo',
                                -icon => 'question',
                                -default => 'Yes',
                        ) eq 'Yes')
        ) {
            $self->{_lselection}->save_to_transcript();
            print "The list of selected evidence changed.";
            print "The new list of selected evidence is:\n";

            use Data::Dumper;
            print Dumper($self->{_transcript}->transcript_info);
            if (my $transcript_window = $self->TranscriptWindow) {
                $transcript_window->_save_OtterTranscript_evidence($self->{_transcript});
            }
        } else {
            warn "Refused to save the changes";
        }
    } else {
        warn "No changes in the selection or ignoring them";
    }

    $self->{_sortfilterdialog}->break_the_links();
    my $top_window = $self->top_window();
    $self->break_the_links();
    warn "closing the EviDisplay window";
    $top_window->destroy();
}

sub launch_blixem_callback {
    my $self = shift @_;
    my $unit = shift @_;

    my @chains_to_show =
        map { $self->{_evichains_lp}[$_]; }
            @{$self->{_lselection}->get_all_visible_indices()};

     $self->{_blixem}->chains(\@chains_to_show);
     $self->{_blixem}->forklaunch($unit);
}

sub TranscriptWindow {
    my( $self, $TranscriptWindow ) = @_;
    
    if ($TranscriptWindow) {
        $self->{'_TranscriptWindow'} = $TranscriptWindow;
    }
    return $self->{'_TranscriptWindow'};
}

sub populate_scale {
    my $self = shift @_;

        # $self->{_scale_type} contains the class name
    $self->{_scale} = $self->{_scale_type}->new();

        # first, collect all transcript's boundaries
    for my $exon (@{ $self->{_transcript}->get_all_Exons() }) {
        $self->{_scale}->add_pair( $exon->start(), $exon->end() );
    }

    if($self->{_transcript}->translation()) { # both ends of the translation
        $self->{_scale}->add_pair(
            $self->{_transcript}->coding_region_start(),
            $self->{_transcript}->coding_region_end()
        );
    }

        # then, collect all the matches' boundaries
    for my $evichain (@{$self->{_evichains_lp}}) {
        for my $af (@{$evichain->afs_lp()}) {
            $self->{_scale}->add_pair( $af->start(), $af->end() );
        }
    }
}

sub evi_redraw {
    my $self = shift @_;

my $tt_redraw = Evi::Tictoc->new("EviDisplay layout");

    $self->populate_scale();

    $self->canvas()->delete('all'); # to make it reentrant

    my $tran_strand = $self->{_transcript}->get_all_Exons()->[0]->strand();

        # show the transcript
    $self->draw_exons(
            $self->canvas()->Subwidget('top_canvas'),
            $self->canvas()->Subwidget('main_canvas'),
            $self->canvas()->Subwidget('topleft_canvas'),
            $self->{_transcript}->get_all_Exons(),
            1,
            undef,
            undef,
            -1,
            $self->{_transcript}->transcript_info()->name(),
            $tran_strand,
            1,
            [   "Name: ".$self->{_transcript}->transcript_info()->name(),
                "Strand: ".strand2name($tran_strand),
            ],
            'transcript',
            0,
            $half_delta+1,
            1
            );

        # show the translation
    if($self->{_transcript}->translation()) {
        $self->draw_exons(
            $self->canvas()->Subwidget('top_canvas'),
            $self->canvas()->Subwidget('main_canvas'),
            $self->canvas()->Subwidget('topleft_canvas'),
            $self->{_transcript}->get_all_Exons(),
            0,
            $self->{_transcript}->coding_region_start(),
            $self->{_transcript}->coding_region_end(),
            -1,
            $self->{_transcript}->transcript_info()->name(),
            $tran_strand,
            1,
            [   "Name: ".$self->{_transcript}->transcript_info()->name(),
                "Strand: ".strand2name($tran_strand),
            ],
            'translation',
            1,
            $half_delta-1,
            0
            );
    }

        # force the canvas to resize just once and speed up the whole process of drawing:
    $self->canvas()->Subwidget('main_canvas')->createLine(
        $self->{_scale}->get_scaled_min(),
        0,
        $self->{_scale}->get_scaled_max(),
        scalar(@{$self->{_evichains_lp}})*$ystep,
        -fill => $self->canvas()->Subwidget('main_canvas')->cget(-bg), # transparent
    );

    for my $screendex (0..@{$self->{_evichains_lp}}-1) {

        my $evichain = $self->{_evichains_lp}[$screendex];

        my $analysis_name = $evichain->analysis();
        $analysis_name=~s/^df_//;

        $self->draw_exons(
            $self->canvas()->Subwidget('main_canvas'),
            $self->canvas()->Subwidget('top_canvas'),
            $self->canvas()->Subwidget('left_canvas'),
            $evichain->afs_lp(),
            ($analysis_name ne 'Uniprot'),
            undef,
            undef,
            $screendex,
            $evichain->name(), # it MUST be the name itself for the selection mechanism to work
            $evichain->strand(),
            $evichain->hstrand(),
            [
                (map { $_->{_name}.':  '.$_->compute($evichain); }
                    @{$self->{_cfset}->filterlist()->[0]->all_criteria()}), # FIXME: should match the class!
                "QStrand: ".strand2name($evichain->strand()),
                "HStrand: ".strand2name($evichain->hstrand()),
            ],
            $analysis_name,
            ($analysis_name eq 'Uniprot'),
            $half_delta,
            1
            );
    }

    $self->canvas()->fit_everything();
    $self->fix_window_min_max_sizes;

    $self->fix_ribbon_widths(
        $self->canvas()->Subwidget('topleft_canvas'),
        $self->canvas()->Subwidget('left_canvas'),
        0,
        5, # make the right edge invisible
    );
    $self->fix_ribbon_widths(
        $self->canvas()->Subwidget('top_canvas'),
        $self->canvas()->Subwidget('main_canvas'),
        5, # make the left edge invisible
        0,
    );

    $self->redraw_selection();

$tt_redraw->done();
}

sub fix_ribbon_widths {
    my ($self,$from_canvas,$to_canvas,$left_delta,$right_delta) = @_;

    my ($left,$y1,$right,$y2) = $from_canvas->cget(-scrollregion);
    $left   -= $left_delta;
    $right  += $right_delta-1;

    for my $canvas ($to_canvas, $from_canvas) {
        for my $id ($canvas->find('withtag','backribbon')) {
            my @coords = $canvas->coords($id);
            $coords[0]=$left;
            $coords[2]=$right;
            $canvas->coords($id,@coords);
        }
    }
}

sub strand2arrow {
    return ((shift @_) == 1) ? '=>' : '<=';
}

sub strand2name {
    return ((shift @_) == 1) ? 'forward' : 'reverse';
}

sub draw_exons {
    my ($self,$where,$where_alt,$where_text,$exons_lp,$show_introns,$start_at,$end_at,
        $screendex,$name_tag,$chain_qstrand,$chain_hstrand,$infotext,
        $scheme,$want_in_frame,$hd,$draw_stripes) = @_;

    my ($ocolor,$fcolor);
    my $stripecolor = $alternating_colors[$screendex % 2];

    my $ribbon_top  = $ystep*$screendex;
    my $ribbon_bot  = $ystep*($screendex+1)-1;
    my $mid_y       = $ystep*($screendex+1/2);

    my $combined_strand = $chain_hstrand*$chain_qstrand;
    my $signed_arrow    = $combined_strand*$abs_arrow_length;

    my $exon_top    = $mid_y - $hd;
    my $exon_bot    = $mid_y + $hd;
    my $intron_top  = $mid_y - $half_delta;
    my $intron_bot  = $mid_y + $half_delta;

    my $chain_tag = "rowindex_$screendex";  # make it unique (i.e. differ from non-unique $name_tag)

    if($draw_stripes) {
            # white-lightgrey background stripes for the chains themselves
        $where->createRectangle(
            $self->{_scale}->get_scaled_min(),
            $ribbon_top,
            $self->{_scale}->get_scaled_max(),
            $ribbon_bot,
            -outline => $stripecolor,
            -fill => $stripecolor,
            -disabledoutline => $current_contour_color,
            -disabledfill => $stripecolor,
            -tags =>    [ $name_tag, $chain_tag, 'backribbon' ],
        );

            # white-lightgrey background stripes for text labels
        $where_text->createRectangle(
            0, # to be substituted later
            $ribbon_top,
            0, # to be substituted later
            $ribbon_bot,
            -outline => $stripecolor,
            -fill => $stripecolor,
            -disabledoutline => $current_contour_color,
            -disabledfill => $stripecolor,
            -tags =>    [ $name_tag, $chain_tag, 'backribbon' ],
        );

        $where_text->createText(0, $mid_y,
            -fill => 'black',
            -disabledfill => $current_contour_color,
            -text =>    $name_tag,
            -anchor =>  'e',
            -tags =>    [ $chain_tag, $name_tag ],
        );
    }

    my @all_exon_intron_tags = ();

    my ($i_start,$i_from);

        # Transcript's order of exons is natural (head to tail)
        # EviChain's order of exons is ascending, independently of the strand
        #
        # This may mean that we'll have to change the order when making Transcripts from EviChains
        #
    for my $exon (sort {$a->start() <=> $b->start()} @$exons_lp) { # left to right

        my $e_start = $exon->start();
        my $e_end   = $exon->end();

        if($start_at) {
            if($e_end<$start_at) { # skip exons to the left
                next;
            } elsif(($e_start<=$start_at) && ($start_at<=$e_end)) { # trim it
                $e_start = $start_at;
            }
        }

        if($end_at) {
            if($end_at<$e_start) { # skip exons to the right
                next;
            } elsif(($e_start<=$end_at) && ($end_at<=$e_end)) { # trim it
                $e_end = $end_at;
            }
        }

        my $from = $self->{_scale}->scale_point($e_start);
        my $to   = $self->{_scale}->scale_point($e_end);
        my $exonc_tag = 'e_'.$e_start.'_'.$e_end; # must be scale-independent

            # draw the preceding intron, if there is one:
        if($show_introns && defined($i_start)) {
            my $intronc_tag = 'i_'.$i_start.'_'.($e_start-1);
            my $i_mid_x = ($i_from+$from)/2;

                # highlightable background rectangle behind an intron:
            my $rect = $where->createRectangle(
                    $i_from + (($signed_arrow > 0) ? $signed_arrow : 0),
                    $intron_top,
                    $from + (($signed_arrow > 0) ? 0 : $signed_arrow),
                    $intron_bot,
                -outline => $stripecolor,
                -fill =>    $stripecolor,
                -disabledoutline => $stripecolor,
                -disabledfill => $highlighting_color,
                -tags =>    [ $intronc_tag, $chain_tag, $name_tag ],
            );

            ($ocolor,$fcolor) = @{$color_scheme->{$scheme || 'default'}}; # frame-independent

            $where->createPolygon(  # the intron itself (angular line pointing upwards)
                    $i_from+$signed_arrow, $mid_y,
                    $i_mid_x+$signed_arrow, $intron_top,
                    $from+$signed_arrow, $mid_y,
                    $from+$signed_arrow, $mid_y,
                    $i_mid_x+$signed_arrow, $intron_top,
                    $i_from+$signed_arrow, $mid_y,
                -outline => $ocolor,
                -fill    => $fcolor,
                -disabledoutline => $current_contour_color,
                -disabledfill    => $highlighting_color,
                -tags =>    [ $intronc_tag, $chain_tag, $name_tag ],
            );

            push @all_exon_intron_tags, $intronc_tag;

if($bind_ok) {
            $where->bind($intronc_tag,'<ButtonPress-1>',
                [\&highlight_bindcallback, (1, [$where,$where_alt], $intronc_tag)] # FIXME: copy to clipboard
                                            # or substitute by a popup
            );
            $where->bind($intronc_tag,'<ButtonRelease-1>',
                [\&highlight_bindcallback, (0, [$where,$where_alt], $intronc_tag)] # FIXME: copy to clipboard
            );
}
        }

        my $scheme_key = $scheme;
        my $show_in_frame = $want_in_frame && $exon->can('frame');
        if($show_in_frame) { # set the frame-dependent scheme
            my $frame = $exon->frame();
            $scheme_key = 'frame_'.$frame;
        }
        ($ocolor,$fcolor) = @{$color_scheme->{$scheme_key}};
        my $cstrand_name = strand2name($combined_strand);

            # now, draw the exon itself:
        # $where->createRectangle($from, $exon_top, $to, $exon_bot, # NOT MUCH FASTER, ACTUALLY!
        $where->createPolygon(
                $from, $exon_top,
                $to,   $exon_top,
                $to+$signed_arrow, $mid_y,
                $to,   $exon_bot,
                $from, $exon_bot,
                $from+$signed_arrow, $mid_y,
            -outline => $ocolor,
            -fill =>    $fcolor,
            -disabledoutline => $current_contour_color,
            -disabledfill => $highlighting_color,
            -tags =>    [ 'exon', $exonc_tag, $chain_tag, $name_tag, $show_in_frame
                            ? ($scheme_key, $cstrand_name)
                            : ()
                        ],
        );
        push @all_exon_intron_tags, $exonc_tag;


        # Show coordinates
if(0) {
        $where->createText($from, $exon_top,
            -fill => 'black',
            -text =>    $e_start,
            -anchor =>  'c',
        );
        $where->createText($to, $exon_bot,
            -fill => 'black',
            -text =>    $e_end,
            -anchor =>  'c',
        );
}

if($bind_ok) {
        $where->bind($exonc_tag,'<ButtonPress-1>',
            [\&highlight_bindcallback, (1, [$where,$where_alt], $show_in_frame
                                        ? ("exon&&${scheme_key}&&${cstrand_name}",$e_start,$e_end)
                                        : ($exonc_tag) )]
        );
        $where->bind($exonc_tag,'<ButtonRelease-1>',
            [\&highlight_bindcallback, (0, [$where,$where_alt], $show_in_frame
                                        ? ("exon&&${scheme_key}&&${cstrand_name}",$e_start,$e_end)
                                        : ($exonc_tag) )]
        );
}

            # prepare for the next intron:
        ($i_start,$i_from) = ($e_end+1,$to+1);
    }

    # ------------[the "chain-wide" event bindings]----------------------:

    my $tag_expr = join('||',@all_exon_intron_tags);

if($bind_ok) {
        # show *all* similar exons and introns:
    $where_text->bind($chain_tag,'<ButtonPress-1>',
        [\&highlight_bindcallback, (1, [$where,$where_alt], $tag_expr)]
    );
    $where_text->bind($chain_tag,'<ButtonRelease-1>',
        [\&highlight_bindcallback, (0, [$where,$where_alt], $tag_expr)]
    );

    for my $c ($where, $where_text) {
            # highlight the current chain:
        $c->bind($chain_tag,'<Enter>',
            [\&highlight_bindcallback, (1, [$where,$where_text], "$chain_tag||(!backribbon&&$name_tag)")]
        );
        $c->bind($chain_tag,'<Leave>',
            [\&highlight_bindcallback, (0, [$where,$where_text], "$chain_tag||(!backribbon&&$name_tag)")]
        );

            # perform the selection (based on $name_tag)
            #   currently it works on evidence names,
            #   but should be re-written to support full evidence chains (via $chain_tag?)
            #   once they get stored in the database:
        if($screendex>=0) { # do it only for evidences, not for transcript(s)
            $c->bind($name_tag,'<Double-1>',
                [\&toggle_select_by_name_bindcallback, ($self, $name_tag)]
            );
        }
    }

    $self->info_popup($where,$chain_tag,$infotext);
    $self->info_popup($where_text,$chain_tag,$infotext);
}

}

sub info_popup {
    my ($self,$where,$tag,$text) = @_;

    my $info_m = $where->Menu(
        -tearoff => 0,
        -menuitems => [
            map { my $line=$_; [
                    Button => $line,
                    # -command => [ $self => 'set_statusline', ($line)], # may be needed if called from other class
                    -command => [ \&set_statusline, ($self, $line)], # GarbageCollector-ok
            ]; } @$text
        ]
    );
    $where->bind($tag,'<ButtonPress-3>',
        [ $info_m => 'Popup', (-popover => 'cursor', -popanchor => 'ne') ]
    );
    $where->toplevel()->bind('<ButtonRelease-3>',
        sub { warn "Button 3 released"; }
    );
}

# -------------------------------[status line]-------------------------------------------

sub set_statusline {
        # because of the difference in callback orders
        # IT IS SAFER to parse the args starting from the other end:
    my $line    = pop @_;
    my $self    = pop @_;

    $self->{_statusline}->delete('1.0', 'end');
    $self->{_statusline}->insert('end', $line);
}

sub get_statusline {
    my $self = shift @_;

    return $self->{_statusline}->get(1,'end');
}

# ------------------------------[highlighting]-------------------------------------------

sub intersects_tag { # not a method
    my ($canvas,$id,$left,$right) = @_;

    for my $tag ($canvas->gettags($id)) {
        if($tag=~/^[ei]\_(\d+)\_(\d+)$/) {
            return ($1<=$right)&&($left<=$2);
        }
    }
    return 0;
}

sub highlight_bindcallback { # not a method!
    my ($bound_canvas, $wanted_state, $canvases_lp, $from_tag_expr, $left, $right) = @_;

    for my $canvas (@$canvases_lp) {
         for my $id ( $canvas->find('withtag',$from_tag_expr) ) {
            my ($from, $to);
            if( (!defined($right))
            || intersects_tag($canvas,$id,$left,$right)
            ) {
                my $old_state = $canvas->{_highlighted}{$id};

                if( ((not $old_state) and $wanted_state)
                 or ((not $wanted_state) and $old_state)) {
                    visual_toggle_highlighting_by_id($canvas,$id);
                    $canvas->{_highlighted}{$id} = not $canvas->{_highlighted}{$id};
                }
            }
        }
    }
}

        # all canvas items behave differently when highlighted,
        # so we have to store the "highlighted" colours in the items themselves
        # and swap them when they are (de)highlighted:
sub visual_toggle_highlighting_by_id { # not a method
    my ($canvas, $id) = @_;

        # flip the outline<->fill colors for all the affected canvas items:
    for my $op ( @{ $type_to_optpairs->{$canvas->type($id)} }) {

            # swap them:
        my $ocol = $canvas->itemcget($id, $op->[0]);
        my $dcol = $canvas->itemcget($id, $op->[1]);

        $canvas->itemconfigure($id, $op->[0] => $dcol);
        $canvas->itemconfigure($id, $op->[1] => $ocol);
    }
}

# ----------------------------------[de/selection]-------------------------------------------

sub visual_select_by_nametag {
    my ($self, $name_tag) = @_;

    for my $canvas (@{ $self->canvas()->canvases() }) {
        for my $id ($canvas->find('withtag',"$name_tag&&backribbon")) {
            for my $opt ('-fill','-disabledfill') {
                my $orig_color = $canvas->itemcget($id,$opt);
                $self->{_selected_ids}{$canvas}{$id}{$opt} = $orig_color;
                $canvas->itemconfigure($id, $opt => $selection_color);
            }
        }
    }
}

sub visual_deselect_by_nametag {
    my ($self, $name_tag) = @_;

    for my $canvas (@{ $self->canvas()->canvases() }) {
        for my $id ($canvas->find('withtag',"$name_tag&&backribbon")) {
            for my $opt ('-fill','-disabledfill') {
                my $orig_color = $self->{_selected_ids}{$canvas}{$id}{$opt};
                $canvas->itemconfigure($id, $opt => $orig_color);
            }
        }
    }
}

sub deselect_by_name { # NB: sometimes it is a method, sometimes it is not!
        # Because of the difference in callback orders
        # IT IS SAFER to parse the args starting from the other end:
    my $name_tag    = pop @_;
    my $self        = pop @_;

    $self->visual_deselect_by_nametag($name_tag);

    $self->{_lselection}->deselect_byname($name_tag);

    my $ms = $self->{_menu_selection}; # unconditionally remove  from the menu
    for my $ind (0..$ms->index('last')) { # if the beginning matches...
        if( $ms->entrycget($ind,-label)=~/^$name_tag/ ) {
            $ms->delete($ind);
        }
    }
}

sub select_by_name { # NB: sometimes it is a method, sometimes it is not!
        # Because of the difference in callback orders
        # IT IS SAFER to parse the args starting from the other end:
    my $name_tag    = pop @_;
    my $self        = pop @_;

        # select logically, invisible by default:
    $self->{_lselection}->select_byname($name_tag);
    
        # set logical visibility:
    for my $screendex (0..@{$self->{_evichains_lp}}-1) {
        my $evichain = $self->{_evichains_lp}[$screendex];
        if($evichain->name() eq $name_tag) {
            $self->{_lselection}->set_visibility($name_tag, 1, $screendex);
        }
    }

    $self->visual_select_by_nametag($name_tag);

    my $is_vis = $self->{_lselection}->is_visible($name_tag);

        # unconditionally add the removal command to the menu:
    my $submenu = $self->{_menu_selection}->cascade(
            -label      => ($is_vis
                                ? $name_tag
                                : "$name_tag (invisible)"),
            -tearoff    => 0,
    );
    if($is_vis) {
        $submenu->command(
            -label      => "ScrollTo",
            -command    => [ $self => 'scroll_to_obj', ($name_tag) ],
        );
    }
    $submenu->command(
        -label      => "Remove",
        -command    => [\&deselect_by_name, ($self, $name_tag) ],
    );
}

sub toggle_select_by_name_bindcallback { # not a method!
    my ($bound_canvas, $self, $name_tag) = @_;

    if($self->{_lselection}->is_selected($name_tag)) { # (definitely visible) deselect it:
        $self->deselect_by_name($name_tag);
    } else { # select it:
        $self->select_by_name($name_tag);
    }
}

sub redraw_selection {
    my $self = shift @_;

    $self->{_menu_selection}->delete(0,'last'); # start from the empty menu

    for my $eviname (@{ $self->{_lselection}->get_namelist() }) {

        $self->select_by_name($eviname); # try to make it visible
        if(not $self->{_lselection}->is_visible($eviname)) {
            warn "$eviname is not currently visible and so cannot be selected on the EviDisplay\n";
        }
    }
}

1;

