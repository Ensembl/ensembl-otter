
### EditWindow::LoadColumns

package EditWindow::LoadColumns;

use strict;
use warnings;
use Carp;
use Scalar::Util 'weaken';

use Tk::HListplusplus;
use Tk::Checkbutton;
use Tk::LabFrame;
use Tk::Balloon;

use MenuCanvasWindow::XaceSeqChooser;
use Hum::Sort 'ace_sort';

use base 'EditWindow';

my %STATE_COLORS = (
    default => 'gold',
    done    => 'green',
    failed  => 'red',
);

sub initialize {
    my( $self ) = @_;
    
    # set the default selection
    
    my $dsc_default = $self->DataSetChooser->default_selection($self->species);

    if ($dsc_default) {
        $self->default_selection($dsc_default);
    }
    else {
        # this is the first time we've opened a slice from this species, so make
        # the current 'wanted' settings (which come from the otter_config) the
        # default selection 
        
        $self->default_selection(
            { map { $_ => $self->n2f->{$_}->wanted } keys %{ $self->n2f } }
            );
        
        # and store these settings in the DataSetChooser
        
        $self->DataSetChooser->default_selection(
            $self->species,
            $self->default_selection
            );
    }
    
    # reset the last selection (if one exists)
    
    my $dsc_last = $self->DataSetChooser->last_selection($self->species);
    
    # directly set the private hash variable to avoid updating the DSC
    # with the same data, and use the default selection if we don't have
    # a last selection
    
    $self->{_last_selection} = $dsc_last || $self->default_selection;
    
    # reset the last sorted by
    
    my $dsc_last_sorted = $self->DataSetChooser->last_sorted_by($self->species);
    
    $self->{_last_sorted_by} = $dsc_last_sorted || $self->default_selection;
    
    # and actually set the wanted flags on the filters accordingly
    
    $self->set_filters_wanted($self->last_selection);
    
    my $top = $self->top;

    my $filter_count = scalar keys %{$self->n2f};
    my $max_rows = 28;
    my $height = $filter_count > $max_rows ? $max_rows : $filter_count;
    my $hlist = $top->Scrolled("HListplusplus",
                               -header => 1,
                               -columns => 3,
                               -scrollbars => 'ose',
                               -width => 100,
                               -height => $height,
                               -selectmode => 'single',
                               -selectbackground => 'light grey',
                               -borderwidth => 1,
        )->pack(-expand => 1, -fill => 'both');

    $hlist->configure(
        -browsecmd => sub {
            $hlist->anchorClear;
            my $i = shift;
            my $cb = $self->hlist->itemCget($i, 0, '-widget');
            $cb->invoke unless $cb->cget('-selectcolor') eq $STATE_COLORS{'done'}
        }
        );

    my $i = 0;

    $hlist->header('create', $i++,  
                   -itemtype => 'resizebutton', 
                   -command => sub {
                       $self->sort_by_filter_method('wanted');
                   }
        );

    $hlist->header('create', $i++, 
                   -text => 'Name', 
                   -itemtype => 'resizebutton', 
                   -command => sub { $self->sort_by_filter_method('name') }
        );
    
    $hlist->header('create', $i++, 
                   -text => 'Description', 
                   -itemtype => 'resizebutton', 
                   -command => sub { $self->sort_by_filter_method('description') }
        );

    $self->hlist($hlist);

    my $bottom_frame = $top->Frame->pack(
        -side => 'bottom', 
        -expand => 0,
        -fill => 'x'    
        );

    my $but_frame = $bottom_frame->pack(
        -side => 'top',
        #-expand => 0,
        #-fill => 'x'
        );
    
    my $select_frame = $but_frame->Frame->pack(
        -side => 'top', 
        -expand => 0
        );
    
    $select_frame->Button(
        -text => 'Default',
        -command => sub { $self->set_filters_wanted($self->default_selection) },
        )->pack(-side => 'left');
    
    $select_frame->Button(
        -text => 'Previous',
        -command => sub { $self->set_filters_wanted($self->last_selection) },
        )->pack(-side => 'left');
    
    $select_frame->Button(
        -text => 'All', 
        -command => sub { $self->change_checkbutton_state('select') },
        )->pack(-side => 'left');
    
    $select_frame->Button(
        -text => 'None', 
        -command => sub { $self->change_checkbutton_state('deselect') },
        )->pack(-side => 'left');
    
    $select_frame->Button(
        -text => 'Invert', 
        -command => sub { $self->change_checkbutton_state('toggle') },
        )->pack(-side => 'left');
    
    $select_frame->Button(
        -text => 'Reselect failed', 
        -command => sub { $self->change_checkbutton_state('invoke', $STATE_COLORS{'failed'}) },
        )->pack(-side => 'right');

    my $progress_frame = $bottom_frame->Frame->pack(
        -side   => 'bottom', 
        -fill   => 'x', 
        -expand => 1
    );

    my $control_frame = $progress_frame->Frame->pack(
        -side => 'bottom', 
        -expand => 0, 
        -fill => 'x'
        );
    
    $control_frame->Button(
        -text => 'Load',
        -command => sub { $self->load_filters },
        )->pack(-side => 'left', -expand => 0);
    
    # The user can press the Cancel button either before the AceDatabase is made
    # (in which case we destroy ourselves) or during an edit session (in which
    # case we just withdraw the window).
    my $wod_cmd = sub { $self->withdraw_or_destroy };
    $control_frame->Button(
        -text => 'Cancel', 
        -command => $wod_cmd,
        )->pack(-side => 'right', -expand => 0);
    $top->protocol( 'WM_DELETE_WINDOW', $wod_cmd );
    
    $self->{_default_sort_method} = 'name';
    
    $self->sort_by_filter_method(
        $self->DataSetChooser->last_sorted_by($self->species) ||
        $self->{_default_sort_method}
        );
    
    
    $control_frame->Label(
        -textvariable => \$self->{_label_text}
        )->pack(-side => 'top');
    
    $self->{_filters_done} = 0;
    
    my $prog_bar = $progress_frame->ProgressBar(
        -width       => 20,
        -from        => 0,
        -blocks      => 1,
        -variable    => \$self->{_filters_done}
        )->pack( 
        -fill   => 'x',
        -expand => 1,
        -padx   => 5,
        -pady   => 5,
        -side => 'top'
            );
    
    $self->pipeline_progress_bar($prog_bar);
    $self->reset_progress;
    
    # Prevents window being made so small that controls disappear
    $self->set_minsize;
    
    $top->bind('<Destroy>', sub{
        $self = undef;
               });

    return;
}

sub num_filters {
    my ( $self, $num_filters ) = @_;
    
    if (defined $num_filters) {
        $self->{_num_filters} = $num_filters;
        $self->pipeline_progress_bar->configure(
            -to     => $num_filters,
            );
    }

    return $self->{_num_filters};
}

sub pipeline_progress_bar {
    my ( $self, $pipeline_progress_bar ) = @_;
    $self->{_pipeline_progress_bar} = $pipeline_progress_bar if $pipeline_progress_bar;
    return $self->{_pipeline_progress_bar};
}

sub reset_progress {
    my ($self) = @_;
    
    my ($num_done, $num_failed) = (0, 0);
    
    for my $key (keys %{ $self->n2f }) {
        my $filter = $self->n2f->{$key};
        $num_done++ if $filter->done && !$filter->failed;
        $num_failed++ if $filter->failed;
    }
    
    my $label_text = "$num_done columns loaded";
    $label_text .= " ($num_failed failed)" if $num_failed;
    
    $self->label_text($label_text);
    $self->{_filters_done} = 0;
    $self->{_num_filters} = 0;

    return;
}

sub label_text {
    my ( $self, $label_text ) = @_;
    $self->{_label_text} = $label_text if defined $label_text;
    return $self->{_label_text};
}

sub loading_filter {
    my ($self, $filter) = @_;
    $self->{_current_filter} = $filter;
    $filter->load_time(time);
    $self->label_text("Loading: ".$filter->name." (".($self->{_filters_done}+1)." of ".$self->{_num_filters}.")");
    $self->update_tk_preserve_grab;
    return;
}

sub filter_done {
    my ($self) = @_;
    $self->{_filters_done}++;
    $self->update_tk_preserve_grab; # to move the progress bar
    #if ($self->{_filters_done} == $self->{_num_filters}) {}
    return;
}

sub filter_loaded {
    my ($self, $filter) = @_;
    $self->filter_done;
    $filter->load_time(time - $filter->load_time);
    $self->show_filters;
    
    $self->{_loaded_filters} ||= [];
    
    if ($filter->can('required_ace_method_names')) {
        push @{ $self->{_loaded_filters} }, @{ $filter->required_ace_method_names };
    }
    else {
        push @{ $self->{_loaded_filters} }, $filter->name;
    }

    return;
}

sub filter_failed {
    my ($self, $filter, $msg) = @_;
    $filter->failed(1);
    $filter->fail_msg($msg);
    $self->filter_done;
    return;
}

sub withdraw_or_destroy {
    my ($self) = @_;
    
    if ($self->init_flag) {
        # Destroy ourselves
        $self->AceDatabase->error_flag(0);
        $self->top->destroy;
    } else {
        $self->top->withdraw;
    }

    return;
}

sub init_flag {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_init_flag'} = $flag ? 1 : 0;
    }
    return $self->{'_init_flag'};
}


sub load_filters {
    my $self = shift;

    my $top = $self->top;
    $top->Busy(-recurse => 1);
    
    # save off the current selection as the last selection
    $self->last_selection(
        { map { $_ => $self->n2f->{$_}->wanted } keys %{ $self->n2f } }
    );

    my @to_fetch = grep { 
        $self->n2f->{$_}->wanted && !$self->n2f->{$_}->done && !$self->n2f->{$_}->failed
    } keys %{ $self->n2f };

    if ($self->init_flag) {
        my $adb = $self->AceDatabase;
        # now initialise the database
        eval{
            $adb->init_AceDatabase;
        };
        if ($@) {
            $self->SequenceNotes->exception_message($@, "Error initialising database");
            $adb->error_flag(0);
            $top->destroy;
            return;
        } else {
            $self->init_flag(0);
        }
    }

    $self->{_loaded_filters} = [];
    
    if (@to_fetch) {
        for my $filter (@to_fetch) {
            my $gff_filter = $self->gff_filters_hash->{$filter};
            if ($gff_filter) {
                my @to_load = $gff_filter->featuresets;
                push @{ $self->{_loaded_filters} }, @to_load;
            }
        }
        $self->AceDatabase->smart_slice->DataSet->save_gff_filter_state;
    }
    
    if ($self->XaceSeqChooser) {
        if (@to_fetch) {
            $self->XaceSeqChooser->zMapLoadFeatures(@{ $self->{_loaded_filters} });
        }
        else {
            $top->messageBox(
                -title      => 'Nothing to fetch',
                -icon       => 'warning',
                -message    => 'All selected columns have already been loaded',
                -type       => 'OK',
                );            
        }
    } else {
        # we need to set up and show an XaceSeqChooser        
        my $xc = MenuCanvasWindow::XaceSeqChooser->new(
            $self->top->Toplevel(
                -title => $self->AceDatabase->title,
            )
        );
        
        $self->XaceSeqChooser($xc);
        $xc->AceDatabase($self->AceDatabase);
        $xc->SequenceNotes($self->SequenceNotes);
        $xc->LoadColumns($self);
        $xc->initialize;
    }
    
    $top->Unbusy;
    $top->withdraw;
    $self->reset_progress;

    return;
}

sub update_tk_preserve_grab {
    my ($self) = @_;
    
    my $top = $self->top;
    # printf STDERR "\nGrab status of top before update is: '%s'\n", $top->grabStatus;
    $top->update;
    # printf STDERR "\nGrab status of top after update is:  '%s'\n", $top->grabStatus;

    return;
}

sub set_filters_wanted {
    my ($self, $wanted_hash) = @_;
    map { $self->n2f->{$_}->wanted($wanted_hash->{$_}) } keys %{ $self->n2f };
    return;
}

sub sort_by_filter_method {
    
    my $self = shift;
    
    my $method = shift || $self->{_default_sort_method};
    
    my %n2f = %{ $self->n2f };
    
    if ($method =~ /wanted/) {
        # hack to get done filters sorted before wanted but undone 
        # filters - note that '/' is ascii-betically before 1 or 0!
        map { $n2f{$_}->wanted('/') if $n2f{$_}->done } keys %n2f;
        map { $n2f{$_}->wanted('9') if $n2f{$_}->failed } keys %n2f;
        $self->{_default_sort_method} = 'load_time';
    }
    
    my $cmp_filters = sub {
        
        my ($f1, $f2, $method, $invert) = @_;
        
        my $res;
        
        if ($f1->$method && !$f2->$method) {
            $res = -1;
        }
        elsif (!$f1->$method && $f2->$method) {
            $res = 1;
        }
        elsif (!$f1->$method && !$f2->$method) {
            $res = 0;
        }
        else {
            $res = ace_sort($f1->$method, $f2->$method);
        }
        
        return $invert ? $res * -1 : $res;
    };
    
    my $flip = 0;
    
    # if we are being launched for the first time we don't want 
    # to reverse the last_sorted_by method, but if the user has
    # clicked on the button twice though we do - this flag marks this
    if ($self->{_internally_sorted}) {
        $flip = $self->last_sorted_by eq $method;
    }
    else {
        $self->{_internally_sorted} = 1;
    }
    
    if ($method =~  s/_rev$//) {
        $flip = 1;
    }
    
    my @sorted_names = sort { 
        $cmp_filters->($n2f{$a}, $n2f{$b}, $method, $flip) || 
            $cmp_filters->($n2f{$a}, $n2f{$b}, $self->{_default_sort_method})
    } keys %n2f;
    
    $self->last_sorted_by($flip ? $method.'_rev' : $method);
    
    if ($method =~ /wanted/) {
        # patch the real values back again!
        map { $n2f{$_}->wanted(1) if $n2f{$_}->done } keys %n2f;
        map { $n2f{$_}->wanted(1) if $n2f{$_}->failed } keys %n2f;
    }
    
    $self->show_filters(\@sorted_names);

    return;
}

sub change_checkbutton_state {
    my ($self, $fn, $state_color) = @_;
    
    $state_color ||= $STATE_COLORS{'default'};
    
    for (my $i = 0; $i < scalar(keys %{ $self->n2f }); $i++) {
        my $cb = $self->hlist->itemCget($i, 0, '-widget');
        $cb->$fn if $cb->cget('-selectcolor') eq $state_color;
    }

    return;
}

sub show_filters {
   
    my $self = shift;
    my $names_in_order = shift || $self->{_last_names_in_order} || keys %{ $self->n2f };

    $self->{_last_names_in_order} = $names_in_order;
    
    my $hlist = $self->hlist;
    
    my $i = 0;
    
    for my $name (@$names_in_order) {

        # eval because delete moans if entry doesn't exist
        eval{ $hlist->delete('entry', $i) };
        
        $hlist->add($i);
        
        my $cb_color = $STATE_COLORS{'default'};
        
        if ($self->n2f->{$name}->failed) {
            $cb_color = $STATE_COLORS{'failed'};
        }
        elsif ($self->n2f->{$name}->done) {
            $cb_color = $STATE_COLORS{'done'};
        }
        
        $hlist->itemCreate($i, 0, 
                           -itemtype => 'window', 
                           -widget => $hlist->Checkbutton(
                               -variable => \$self->n2f->{$name}->{_wanted},
                               -onvalue => 1,
                               -offvalue => 0,
                               -anchor => 'w',
                               -selectcolor => $cb_color,
                           ),
            );
        
        if ($self->n2f->{$name}->done) {
            my $cb = $hlist->itemCget($i, 0, '-widget');
            $cb->configure(-command => sub { $cb->select() });
            if (! $self->n2f->{$name}->{_wanted}) {
                warn "filter '$name' done but not wanted ???";
                $self->n2f->{$name}->{_wanted} = 1;
            }
            
            if (!$self->n2f->{$name}->failed) {
                my $balloon = $self->balloon;
                if (defined $self->n2f->{$name}->load_time) {
                    $balloon->attach($cb,
                                     -balloonmsg => sprintf('Loaded in %d seconds', $self->n2f->{$name}->load_time),
                        );
                }
            }
        }
        
        if ($self->n2f->{$name}->failed) {
            my $cb = $hlist->itemCget($i, 0, '-widget');
            my $balloon = $self->top->Balloon;
            $balloon->attach($cb, -balloonmsg => $self->n2f->{$name}->fail_msg || '');
            
            # configure the button such that the user can reselect 
            # a failed filter to try again
            $cb->configure(
                -command => sub {
                    $self->n2f->{$name}->failed(0);
                    $cb->configure(
                        -selectcolor => $STATE_COLORS{'default'}, 
                        -command => undef,
                        );
                    $cb->select;
                },
                );
        }

        $hlist->itemCreate($i, 1, 
                           -text => $self->n2f->{$name}->name,
            );
        
        $hlist->itemCreate($i, 2,
                           -text => $self->n2f->{$name}->description,
            );

        $i++;
    }

    return;
}

# (g|s)etters

sub last_selection {
    my ($self, $last) = @_;
    
    if ($last) {
        
        $self->{_last_selection} = $last;
        
        # also update the DataSetChooser
        
        $self->DataSetChooser->last_selection(
            $self->species,
            $last,
            );
    }
    
    return $self->{_last_selection};
}

sub last_sorted_by {
    my ($self, $last) = @_;
    
    if ($last) {
        
        $self->{_last_sorted_by} = $last;
        
        # also update the DataSetChooser
        
        $self->DataSetChooser->last_sorted_by(
            $self->species,
            $last,
            );
    }
    
    return $self->{_last_sorted_by};
}

sub default_selection {
    my ($self, $default) = @_;
    
    $self->{_default_selection} = $default if $default;
    
    return $self->{_default_selection};
}

sub species {
    my ($self) = @_;
    
    return $self->AceDatabase->smart_slice->dsname;
}

sub n2f {
    my ($self, $n2f) = @_;
    return $self->gff_filters_hash;
}

sub gff_filters_hash {
    my ($self) = @_;
    unless ($self->{_gff_filters_hash}) {
        my $gff_filters =
            $self->AceDatabase->smart_slice->DataSet->gff_filters;
        $self->{_gff_filters_hash} = {
            map { $_->name => $_ } @{$gff_filters},
        };
    }
    return $self->{_gff_filters_hash};
}

sub hlist {
    my ($self, $hlist) = @_;
    $self->{'_hlist'} = $hlist if $hlist;
    # weaken($self->{'_hlist'}) if $hlist;
    return $self->{'_hlist'};
}

sub XaceSeqChooser {
    my ($self, $xc) = @_ ;
    
    if ($xc) {
        $self->{'_XaceSeqChooser'} = $xc;
        weaken($self->{'_XaceSeqChooser'});
    }
    
    return $self->{'_XaceSeqChooser'} ;
}

sub AceDatabase {
    my ($self, $db) = @_ ;
    $self->{'_AceDatabase'} = $db if $db;
    return $self->{'_AceDatabase'} ;
}

sub drop_AceDatabase {
    my ($self) = @_;
    
    $self->{'_AceDatabase'} = undef;

    return;
}

sub SequenceNotes {
    my ($self, $sn) = @_ ;
    $self->{'_SequenceNotes'} = $sn if $sn;
    return $self->{'_SequenceNotes'} ;
}

sub DataSetChooser {
    my ($self, $dc) = @_ ;
    $self->{'_DataSetChooser'} = $dc if $dc;
    return $self->{'_DataSetChooser'} ;
}

sub DESTROY {
    my( $self ) = @_;
    
    warn "Destroying LoadColumns\n";
    if (my $sn = $self->SequenceNotes) {
        my $adb = $self->AceDatabase;
        $adb->post_exit_callback(sub{
            $sn->refresh_lock_columns;    
        });
    }

    return;
}

1;

__END__

=head1 NAME - EditWindow::LoadColumns

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk

