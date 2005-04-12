package Evi::EviDisplay;

# A window showing a transcript and supporting evidence
#
# lg4, 7.Apr'2005

my $ystep = 16;
my $rel_exon_thickness = 0.5; # in practice - from 0.1 to 0.9

my $current_contour_color = 'red';
my $selection_color    = '#9ea2ff';
my $highlighting_color = 'yellow';

my @alternating_colors = ('white','#eeeeee');

my $color_scheme = {      #  OUTLINE,		FILL
	'transcript'       => [ 'darkgreen',	'green'		],
	'Est2genome_human' => [ 'blue',			'violet'	],
	'Est2genome_mouse' => [ 'blue',			'violet'	],
	'Est2genome_other' => [ 'blue',			'violet'	],
	'vertrna'          => [ 'black',		'#a05000'	],
	'Uniprot'          => [ 'cyan',			'darkblue'	],
};

my $type_to_optpairs = { # canvas-dependent stuff
	'line'		=> [ ['-fill','-disabledfill'] ],
	'text'		=> [ ['-fill','-disabledfill'] ],
	'rectangle'	=> [ ['-fill','-disabledfill'], ['-outline','-disabledoutline'] ],
	'polygon'	=> [ ['-fill','-disabledfill'], ['-outline','-disabledoutline'] ],
};

use strict;
use Evi::SortCriterion;		# method/params to be called on data to compute the key, direction, threshold...
use Evi::Sorter;				# performs multicriterial sorting, filtering and uniq

use Evi::ScaleQuantum;		# scaler that exaggerates the small differences in lengths
use Evi::ScaleMinexon;		# scaler that fixes the minimum length of an exon
use Evi::ScaleFitwidth;		# scaler that fits everything into given width

use Tk::ROText;			# for the status line
use Tk::WrappedOSF;		# frame that selects the sorting order
use MenuCanvasWindow;	# recommended self-resizing window mgr

use Evi::Tictoc;				# a simple stopwatch

use base ('MenuCanvasWindow','Evi::DestroyReporter'); # we want to track the destruction event

sub init_filter_and_sort_criteria {
	my $self = shift @_;

		# ALLOW: switch on showing all available analyses
	for my $analysis (	@{ $self->{_evicoll}->rna_analyses_lp() },
						@{ $self->{_evicoll}->protein_analyses_lp() }) {
		$self->{_show_analysis}{$analysis} = 1;
	}
		# DENY: switch off certain analyses
	for my $analysis (@{ $self->{_hide_analyses_lp} }) {
			# be careful not to create unwanted hash values:
		if($self->{_show_analysis}{$analysis}) {
			$self->{_show_analysis}{$analysis} = 0;
		}
	}

		# create and initialize the sorter
    $self->{active_criteria_lp} = [
		Evi::SortCriterion->new('Analysis','analysis',
					[],'alphabetic','ascending'),
		Evi::SortCriterion->new('Taxon','taxon_name',
					[],'alphabetic','ascending'),
		Evi::SortCriterion->new('Evidence name','name',
					[],'alphabetic','ascending'),
    ];
    $self->{remaining_criteria_lp} = [
			# transcript-dependent criteria:
		Evi::SortCriterion->new('Supported introns', 'trans_supported_introns',
					[$self->{_transcript}], 'numeric','descending',1),
		Evi::SortCriterion->new('Supported junctions', 'trans_supported_junctions',
					[$self->{_transcript}], 'numeric','descending'),
		Evi::SortCriterion->new('Supported % of transcript','transcript_coverage',
					[$self->{_transcript}], 'numeric','descending'),
		Evi::SortCriterion->new('Dangling ends (bases)','contrasupported_length',
					[$self->{_transcript}], 'numeric','ascending',0),

			# transcript-independent criteria:
		Evi::SortCriterion->new('Evidence sequence coverage (%)','eviseq_coverage',
					[], 'numeric','descending',50),
		Evi::SortCriterion->new('Minimum % of identity','min_percent_id',
					[], 'numeric','descending'),
		Evi::SortCriterion->new('Start of match (slice coords)','start',
					[], 'numeric','ascending'),
		Evi::SortCriterion->new('End of match (slice coords)','end',
					[], 'numeric','descending'),
		Evi::SortCriterion->new('Source database','db_name',
					[], 'alphabetic','ascending'),
    ];
}

sub filter_and_sort {
	my $self = shift @_;

my $tt_fs = Evi::Tictoc->new("Filtering and sorting");
		# find everything that intersects with the transcript
	my $left_matches_lp = $self->{_evicoll}->find_intersecting_matches($self->{_transcript});

		# show only certain types of analyses:
	$left_matches_lp = [ grep { $self->{_show_analysis}{$_->analysis()} } @$left_matches_lp ];

		# from the matching chains with equal names take the ones with best coverage
	if($self->{_uniq}) {
			$left_matches_lp = Evi::Sorter::uniq($left_matches_lp,
				[ Evi::SortCriterion->new('unique by EviSeq name',
										'name', [],'alphabetic','ascending') ],
				[ Evi::SortCriterion->new('optimal by EviSeq coverage',
										'eviseq_coverage', [], 'numeric','descending') ]
			);
	}

    my $sorter = Evi::Sorter->new( @{ $self->{active_criteria_lp} } );

	if(0) { # IF SORTER "gets inherited" FROM ANOTHER TRANSCRIPT,
			# re-set the transcript parameter in (active-only!) criteria:
		for my $criterion (@{ $sorter->get_criteria() }) {
			$criterion->internalFeature('_params',[$self->{_transcript}]);
		}
	}
		# finally, cut off by thresholds and sort
	$self->{_evichains_lp} = $sorter->cutsort($left_matches_lp);

$tt_fs->done();
}

sub new {
	my $pkg = shift @_;

	my $parentwindow			= shift @_;
	my $title					= shift @_;

		# create the window with widgets
	my $top_window = $parentwindow->Toplevel(-title => $title);
	my $self = $pkg->SUPER::new($top_window,undef,undef,'','HeadedCanvas');

	$self->{_evicoll}			= shift @_;
	$self->{_transcript}		= shift @_;
	$self->{_uniq}				= shift @_ || 1;
	$self->{_hide_analyses_lp}	= shift @_ || [ 'Uniprot' ];
	$self->{_scale_type}		= shift @_ || 'Evi::ScaleFitwidth';

	$self->init_filter_and_sort_criteria();
	$self->load_selection_from_transcript();

	$self->{_statusline} = $top_window->ROText(-height=>1)->pack(-side => 'bottom');

	my $menu_file = $self->make_menu('File');
	$menu_file->command(
        -label      => 'Save and exit',
        -command    => sub {
                            print STDERR "Saving to transcript\n";
							$self->save_selection_to_transcript();
                            print STDERR "Closing window\n";
							$self->top_window()->destroy();
						},
	);
	$menu_file->command(
        -label      => 'Exit without saving',
        -command    => sub {
							$self->top_window()->destroy();
						},
	);

	my $menu_data = $self->make_menu('Data');
	for my $analysis (sort keys %{ $self->{_show_analysis} }) {
		$menu_data->checkbutton(
			-label  => "Show $analysis",
			-variable => \$self->{_show_analysis}{$analysis},
			-command => sub {
							$self->filter_and_sort();
							$self->evi_redraw();
						},
		);
	}
	$menu_data->separator();
	$menu_data->radiobutton(
        -label  => 'Show uni~que matches',
        -value  => 1,
        -variable => \$self->{_uniq},
		-command => sub {
						$self->filter_and_sort();
						$self->evi_redraw();
					},
    );
    $menu_data->radiobutton(
        -label  => 'Show ~all matches',
        -value  => 0,
        -variable => \$self->{_uniq},
		-command => sub {
						$self->filter_and_sort();
						$self->evi_redraw();
					},
    );
	$menu_data->separator();
	$menu_data->command(
        -label      => 'Change ~sorting/filtering order ...',
        -command    => sub {
			my $sort_w = $top_window->Toplevel(-title => "$title| Sort data");
			$sort_w->minsize(700,150);

			$sort_w->Label('-text' => 'Please select the sorting order:')
				->pack('-side' => 'top');
			my $wosf = $sort_w->WrappedOSF()
				->pack('-fill' => 'both', '-expand' => 1);

			$wosf->link_data( $self->{active_criteria_lp}, $self->{remaining_criteria_lp} );

			my $done_b = $sort_w->Button(
							'-text' => 'Done',
							'-command' => sub{
								$self->filter_and_sort();
								$self->evi_redraw();
								$sort_w->destroy(); # it IS better to get rid of it
							}
			)->pack('-side' => 'bottom', '-anchor' => 'se');
			$done_b->bind('<Destroy>', sub { $sort_w=$wosf=undef; });
		}
    );

	my $menu_view = $self->make_menu('View');
	$menu_view->radiobutton(
		-label	=> '~Proportional 1:1 view',
		-value	=> 'Evi::ScaleBase',
		-variable => \$self->{_scale_type},
		-command => sub { $self->evi_redraw(); }
	);
	$menu_view->radiobutton(
		-label	=> '~Fitting view',
		-value	=> 'Evi::ScaleFitwidth',
		-variable => \$self->{_scale_type},
		-command => sub { $self->evi_redraw(); }
	);
	$menu_view->radiobutton(
		-label	=> '~MinExon view',
		-value	=> 'Evi::ScaleMinexon',
		-variable => \$self->{_scale_type},
		-command => sub { $self->evi_redraw(); }
	);
	$menu_view->radiobutton(
		-label	=> '~Quantum view',
		-value	=> 'Evi::ScaleQuantum',
		-variable => \$self->{_scale_type},
		-command => sub { $self->evi_redraw(); }
	);

	$self->{_menu_selection} = $self->make_menu('Selection');

	$top_window->protocol('WM_DELETE_WINDOW', sub {
										$self->save_selection_to_transcript();
										$self->top_window()->destroy();
									});

	$top_window->bind('<Destroy>', sub { $self=undef; });

	$self->filter_and_sort();
	$self->evi_redraw();

	return $self;
}

sub ExonCanvas {
    my( $self, $ExonCanvas ) = @_;
    
    if ($ExonCanvas) {
        $self->{'_ExonCanvas'} = $ExonCanvas;
    }
    return $self->{'_ExonCanvas'};
}

sub populate_scale {
	my $self = shift @_;

		# $self->{_scale_type} contains the class name
	$self->{_scale} = $self->{_scale_type}->new();

		# first, collect all transcript's boundaries
	for my $exon (@{ $self->{_transcript}->get_all_Exons() }) {
		$self->{_scale}->add_pair( $exon->start(), $exon->end() );
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
			-1,
			$self->{_transcript}->transcript_info()->name(),
			$tran_strand,
			[	"Name: ".$self->{_transcript}->transcript_info()->name(),
				"Strand: ".strand2name($tran_strand),
			],
			'transcript'
			);

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
		$self->draw_exons(
			$self->canvas()->Subwidget('main_canvas'),
			$self->canvas()->Subwidget('top_canvas'),
			$self->canvas()->Subwidget('left_canvas'),
			$evichain->afs_lp(),
			$screendex,
			$evichain->name(),
			$evichain->strand(),
			[
				(map { $_->{_name}.':  '.$_->compute($evichain); }
					@{$self->{active_criteria_lp}}),
				'-----------------------',
				(map { $_->{_name}.':  '.$_->compute($evichain); }
					@{$self->{remaining_criteria_lp}}),
				"Strand: ".strand2name($evichain->strand()),
			],
			$evichain->analysis()
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
	$left	-= $left_delta;
	$right	+= $right_delta-1;

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
	my ($self,$where,$where_alt,$where_text,$exons_lp,$screendex,$name_tag,$chain_strand,$infotext,$scheme) = @_;

	my ($ocolor,$fcolor) = @{$color_scheme->{$scheme}};
	my $stripecolor = $alternating_colors[$screendex % 2];

	my $ribbon_top	= $ystep*$screendex;
	my $ribbon_bot	= $ystep*($screendex+1)-1;
	my $mid_y		= $ystep*($screendex+1/2);

	my $half_delta	= $ystep*$rel_exon_thickness/2;
	my $exon_top	= $mid_y - $half_delta;
	my $exon_bot	= $mid_y + $half_delta;

	my $chain_tag = "rowindex:.$screendex";	# make it unique (i.e. differ from non-unique $name_tag)

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
		-tags =>	[ $name_tag, $chain_tag, 'backribbon' ],
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
		-tags =>	[ $name_tag, $chain_tag, 'backribbon' ],
	);

	$where_text->createText(0, $mid_y,
		-fill => 'black',
		-disabledfill => $current_contour_color,
		-text =>	$name_tag.' '.strand2arrow($chain_strand),
		-anchor =>	'e',
		-tags =>	[ $chain_tag, $name_tag ],
	);

	my @all_exon_intron_tags = ();

	my ($i_start,$i_from);

		# Transcript's order of exons is natural (head to tail)
		# EviChain's order of exons is ascending, independently of the strand
		#
		# This may mean that we'll have to change the order when making Transcripts from EviChains
		#
	for my $exon (sort {$a->start() <=> $b->start()} @$exons_lp) {

		my $from = $self->{_scale}->scale_point($exon->start());
		my $to   = $self->{_scale}->scale_point($exon->end());
		my $exon_tag = $exon->start().','.$exon->end(); # must be scale-independent

		push @all_exon_intron_tags, $exon_tag;

			# draw the preceding intron, if there is one:
		if(defined($i_start)) {
			my $intron_tag = $i_start.','.($exon->start()-1);
			my $i_mid_x = ($i_from+$from)/2;

			push @all_exon_intron_tags, $intron_tag;

				# highlightable background rectangle behind an intron:
			my $rect = $where->createRectangle(
					$i_from,$exon_top,$from,$exon_bot,
				-outline => $stripecolor,
				-fill =>    $stripecolor,
				-disabledoutline => $stripecolor,
				-disabledfill => $highlighting_color,
				-tags =>	[ $intron_tag, $chain_tag, $name_tag ],
			);

			$where->createPolygon(	# the intron itself (angular line pointing upwards)
					$i_from, $mid_y,
					$i_mid_x, $exon_top,
					$from, $mid_y,
					$from, $mid_y,
					$i_mid_x, $exon_top,
					$i_from, $mid_y,
				-outline => $ocolor,
				-fill    => $fcolor,
				-disabledoutline => $current_contour_color,
				-disabledfill    => $highlighting_color,
				-tags =>	[ $intron_tag, $chain_tag, $name_tag ],
			);

			$where->bind($intron_tag,'<ButtonPress-1>',
				[\&highlight, (1, [$where,$where_alt], $intron_tag)] # FIXME: copy to clipboard
											# or substitute by a popup
			);
			$where->bind($intron_tag,'<ButtonRelease-1>',
				[\&highlight, (0, [$where,$where_alt], $intron_tag)] # FIXME: copy to clipboard
			);
		}

			# now, draw the exon itself:
		$where->createRectangle($from, $exon_top, $to, $exon_bot,
			-outline => $ocolor,
			-fill =>    $fcolor,
			-disabledoutline => $current_contour_color,
			-disabledfill => $highlighting_color,
			-tags =>	[ $exon_tag, $chain_tag, $name_tag ],
		);

		$where->bind($exon_tag,'<ButtonPress-1>',
			[\&highlight, (1, [$where,$where_alt], $exon_tag)] # FIXME: copy to clipboard
																# or substitute by a popup
		);
		$where->bind($exon_tag,'<ButtonRelease-1>',
			[\&highlight, (0, [$where,$where_alt], $exon_tag)] # FIXME: copy to clipboard
		);

			# prepare for the next intron:
		($i_start,$i_from) = ($exon->end()+1,$to+1);
	}

	# ------------[the "chain-wide" event bindings]----------------------:

	my $tag_expr = join('||',@all_exon_intron_tags);

		# show *all* similar exons and introns:
	$where_text->bind($chain_tag,'<ButtonPress-1>',
		[\&highlight, (1, [$where,$where_alt], $tag_expr)]
	);
	$where_text->bind($chain_tag,'<ButtonRelease-1>',
		[\&highlight, (0, [$where,$where_alt], $tag_expr)]
	);

	for my $c ($where, $where_text) {
			# highlight the current chain:
		$c->bind($chain_tag,'<Enter>',
			[\&highlight, (1, [$where,$where_text], "$chain_tag||(!backribbon&&$name_tag)")]
		);
		$c->bind($chain_tag,'<Leave>',
			[\&highlight, (0, [$where,$where_text], "$chain_tag||(!backribbon&&$name_tag)")]
		);

			# perform the selection (based on $name_tag)
			#	currently it works on evidence names,
			#	but should be re-written to support full evidence chains (via $chain_tag?)
			#	once they get stored in the database:
		if($screendex>=0) { # do it only for evidences, not for transcript(s)
			$c->bind($name_tag,'<Double-1>',
				[\&toggle_select_by_name, $self, $name_tag]
			);
		}
	}

	$self->info_popup($where,$chain_tag,$infotext);
	$self->info_popup($where_text,$chain_tag,$infotext);
}

sub info_popup {
	my ($self,$where,$tag,$text) = @_;

	my $info_m = $where->Menu(
		-tearoff => 0,
		-menuitems => [
			map { my $line=$_; [
					Button => $line,
					-command => [ $self => 'set_statusline', ($line)], # GC ok
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
	my $line	= pop @_;
	my $self	= pop @_;

	$self->{_statusline}->delete('1.0', 'end');
	$self->{_statusline}->insert('end', $line);
}

sub get_statusline {
	my $self = shift @_;

	return $self->{_statusline}->get(1,'end');
}

# ------------------------------[highlighting]-------------------------------------------

sub highlight { # not a method, but called as such sometimes
		# because of the difference in callback orders
		# IT IS SAFER to parse the args starting from the other end:
	my $tag_expr	= pop @_;
	my $canvases_lp = pop @_;
	my $wanted_state= pop @_;

	for my $canvas (@$canvases_lp) {
		for my $id ($canvas->find('withtag',$tag_expr)) {
			my $old_state = $canvas->{_highlighted}{$id};

			if( ((not $old_state) and $wanted_state)
			 or ((not $wanted_state) and $old_state)) {
					toggle_highlighting_by_id($canvas,$id);
					$canvas->{_highlighted}{$id} = not $canvas->{_highlighted}{$id};
			}
		}
	}
}

sub toggle_highlighting_by_id { # not a method
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

# ----------------------------------[selection]-------------------------------------------

sub deselect_by_name { # FIXME: may try to (invisibly) select the actual transcript.
		# Because of the difference in callback orders
		# IT IS SAFER to parse the args starting from the other end:
	my $name_tag	= pop @_;
	my $self		= pop @_;

	for my $canvas (@{ $self->canvas()->canvases() }) {
		for my $id ($canvas->find('withtag',"$name_tag&&backribbon")) {
			for my $opt ('-fill','-disabledfill') {
				my $orig_color = $self->{_selected_items}{$name_tag}{$id}{$opt};
				$canvas->itemconfigure($id, $opt => $orig_color);
			}
		}
	}
	delete $self->{_name2selevidence}{$name_tag}; # unconditionally remove from the selected set

	my $ms = $self->{_menu_selection}; # unconditionally remove  from the menu
	for my $ind (0..$ms->index('last')) { # if the beginning matches...
		if( $ms->entrycget($ind,-label)=~/^$name_tag/ ) {
			$ms->delete($ind);
		}
	}
}

sub select_by_name { # FIXME: may try to (invisibly) select the actual transcript.
		# Because of the difference in callback orders
		# IT IS SAFER to parse the args starting from the other end:
	my $name_tag	= pop @_;
	my $self		= pop @_;

	my $representative_chain = $self->{_evicoll}->get_all_matches_by_name($name_tag)->[0];
	$self->{_name2selevidence}{$name_tag} = { # make it selected, but invisible by default
		'data' => Bio::Otter::Evidence->new(
					-NAME => $representative_chain->prefixed_name(),
					-TYPE => $representative_chain->evitype(),
				),
		'visible' => 0,
	};
	for my $canvas (@{ $self->canvas()->canvases() }) {
		for my $id ($canvas->find('withtag',"$name_tag&&backribbon")) {
			for my $opt ('-fill','-disabledfill') {
				my $orig_color = $canvas->itemcget($id,$opt);
				$self->{_selected_items}{$name_tag}{$id}{$opt} = $orig_color;
				$canvas->itemconfigure($id, $opt => $selection_color);
			}
			$self->{_name2selevidence}{$name_tag}{visible} = 1; # something was found and visibly selected
		}
	}

	$self->{_menu_selection}->command( # unconditionally add the removal command to the menu
				-label		=> ($self->{_name2selevidence}{$name_tag}{visible}
									? $name_tag
									: "$name_tag (invisible)"),
				-command	=> [\&deselect_by_name, $self, $name_tag],
	);
}

sub toggle_select_by_name {
		# Because of the difference in callback orders
		# IT IS SAFER to parse the args starting from the other end:
	my $name_tag= pop @_;
	my $self	= pop @_;

	if(exists $self->{_name2selevidence}{$name_tag}) { # (definitely visible) deselect it:
		$self->deselect_by_name($name_tag);
	} else { # select it:
		$self->select_by_name($name_tag);
	}
}

sub strip_colonprefix { # not a method
	my $name = shift @_;

	return ($name=~/:(.*)$/)
			? $1
			: $name;
}

sub load_selection_from_transcript {
	my $self = shift @_;

	$self->{_name2selevidence} = {};
	for my $evientry (@{ $self->{_transcript}->transcript_info()->get_all_Evidence() }) {
		my $name = strip_colonprefix($evientry->name());

		$self->{_name2selevidence}{$name} = {
			'data' => $evientry, # just grab them as they are
			'visible' => 0,
		};
	}
}

sub redraw_selection {
	my $self = shift @_;

	$self->{_menu_selection}->delete(0,'last'); # start from the empty menu

	for my $eviname (keys %{ $self->{_name2selevidence}}) {
		$self->select_by_name($eviname); # try to make it visible
		if(! $self->{_name2selevidence}{$eviname}{visible}) {
			warn "$eviname cannot be selected as it is not visible on the EviDisplay\n";
		}
	}
}

sub any_changes_in_selection {
	my $self = shift @_;

	my $old_selection = join(',', sort map { strip_colonprefix($_->name()); }
									@{ $self->{_transcript}->transcript_info()->get_all_Evidence() });

	my $curr_selection = join(',', sort (keys %{ $self->{_name2selevidence}}) );

	return $old_selection ne $curr_selection;
}

sub save_selection_to_transcript {
	my $self = shift @_;

	if( $self->any_changes_in_selection() ) {
		print "The list of selected evidence changed.\n";
		print "The new list of selected evidence is:\n";

		$self->{_transcript}->transcript_info()->flush_Evidence();

		for my $eviname (keys %{$self->{_name2selevidence}}) {
			print "\t".$self->{_name2selevidence}{$eviname}{data}->name();
			print "\t".$self->{_name2selevidence}{$eviname}{visible}."\n";
		}
        
		$self->{_transcript}->transcript_info()->add_Evidence(
			map { $self->{_name2selevidence}{$_}{data}; }
					(keys %{ $self->{_name2selevidence}})
		);
        use Data::Dumper;
        print STDERR Dumper($self->{_transcript}->transcript_info);
        if (my $ec = $self->ExonCanvas) {
            $ec->save_OtterTranscript_evidence($self->{_transcript});
        }
	} else {
		print "The list of selected evidence did not change.\n";
		print "Nothing to be saved back to the database\n";
	}
}

1;

