
### EditWindow::LoadColumns

package EditWindow::LoadColumns;

use strict;
use Carp;
use Scalar::Util 'weaken';

use Tk::HListplus;
use Tk::Checkbutton;
use Tk::LabFrame;

use base 'EditWindow';

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

	my $hlist = $top->Scrolled("HListplus",
		-header => 1,
		-columns => 3,
		-scrollbars => 'ose',
		-width => 100,
		-height => 51,
        -selectmode => 'single',
        -selectbackground => 'light grey',
        -borderwidth => 1,
	)->pack(-expand => 1, -fill => 'both');

	$hlist->configure(
		-browsecmd => sub {
			$hlist->anchorClear;
        	my $i = shift;
        	my $cb = $self->hlist->itemCget($i, 0, '-widget');
        	$cb->toggle unless $cb->cget('-selectcolor') eq 'green';
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
    	-command => sub { $self->sort_by_filter_method('method_tag') }
	);
	
	$hlist->header('create', $i++, 
		-text => 'Description', 
    	-itemtype => 'resizebutton', 
    	-command => sub { $self->sort_by_filter_method('description') }
	);
	
#	$hlist->header('create', $i++, 
#		-text => 'Molecule type', 
#    	-itemtype => 'resizebutton', 
#    	-command => sub { $self->sort_by_filter_method('is_protein') }
#	);

	$self->hlist($hlist);

	my $but_frame = $top->Frame->pack(
		-side => 'bottom', 
		-expand => 0,
		-fill => 'x'	
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
	)->pack(-side => 'right');

	my $control_frame = $but_frame->Frame->pack(
		-side => 'bottom', 
		-expand => 1, 
		-fill => 'x'
	);

    $control_frame->Button(
	    -text => 'Load',
	    -command => sub { $self->load_filters },
	)->pack(-side => 'left', -expand => 0);
	
	# the close button just 'withdraw's the window, we will actually
	# get 'destroy'ed by the associated XaceSeqChooser
	$control_frame->Button(
	    -text => 'Close', 
	    -command => sub { $top->withdraw }
	)->pack(-side => 'right', -expand => 0);
    
    $self->{_default_sort_method} = 'method_tag';
    
    $self->sort_by_filter_method(
    	$self->DataSetChooser->last_sorted_by($self->species) ||
    	$self->{_default_sort_method}
    );
    
    $top->bind('<Destroy>', sub{
        $self = undef;
    });
}

sub load_filters {
	
	my $self = shift;
	
	my $top = $self->top;
	
	$top->Busy;
	
	# save off the current selection as the last selection
	
	$self->last_selection(
		{ map { $_ => $self->n2f->{$_}->wanted } keys %{ $self->n2f } }
	);
								
	if ($self->XaceSeqChooser) {
		# we already have an XaceSeqChooser attached
		
		my @to_fetch = grep { 
			$self->n2f->{$_}->wanted && !$self->n2f->{$_}->done 
		} keys %{ $self->n2f };
							
		if (@to_fetch) {
    		# assuming DataFactory has already been initialized by AceDatabase.pm
        	if($self->AceDatabase->topup_pipeline_data_into_ace_server()) {
        		$self->XaceSeqChooser->resync_with_db;
            	$self->XaceSeqChooser->zMapLaunchZmap;
        	}
        }
        else {
			# don't need to fetch anything
			$top->messageBox(
	        	-title      => 'Nothing to fetch',
	        	-icon       => 'warning',
	        	-message    => 'All selected columns have already been loaded',
	        	-type       => 'OK',
	    	);							
		}
	}
	else {
		# we need to set up and show an XaceSeqChooser
        
        $self->AceDatabase->topup_pipeline_data_into_ace_server();
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
}

sub set_filters_wanted {
	my ($self, $wanted_hash) = @_;
	map { $self->n2f->{$_}->wanted($wanted_hash->{$_}) } keys %{ $self->n2f };
}

sub sort_by_filter_method {
	
	my $self = shift;
	
	my $method = shift || $self->{_default_sort_method};
	
	my %n2f = %{ $self->n2f };
	
	if ($method =~ /wanted/) {
		# hack to get done filters sorted before wanted but undone 
    	# filters - note that '/' is ascii-betically before 1 or 0!
    	map { $n2f{$_}->wanted('/') if $n2f{$_}->done } keys %n2f;
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
			$res = lc($f1->$method) cmp lc($f2->$method);
		}
		
		return $invert ? $res * -1 : $res;
	};
	
	print "method: $method\n";
	
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
	
	print "flip: $flip\n";
	print "sorted_by: ",$self->last_sorted_by, "\n";
	
	if ($method =~ /wanted/) {
		# patch the real values back again!
    	map { $n2f{$_}->wanted(1) if $n2f{$_}->done } keys %n2f;
	}
	
    $self->show_filters(\@sorted_names);
}

sub change_checkbutton_state {
	my ($self, $fn) = @_;
    for (my $i = 0; $i < scalar(keys %{ $self->n2f }); $i++) {
    	my $cb = $self->hlist->itemCget($i, 0, '-widget');
        $cb->$fn unless $cb->cget('-selectcolor') eq 'green'; # don't touch done filters
    }
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
        
        $hlist->itemCreate($i, 0, 
            -itemtype => 'window', 
            -widget => $hlist->Checkbutton(
                -variable => \$self->n2f->{$name}->{_wanted},
                -onvalue => 1,
            	-offvalue => 0,
            	-anchor => 'w',
            	$self->n2f->{$name}->done ? ( -selectcolor => 'green' ) : (),
            ),
        );
        
        if($self->n2f->{$name}->done) {
        	my $cb = $hlist->itemCget($i, 0, '-widget');
            $cb->configure(-command => sub { $cb->select(); });
        }

        $hlist->itemCreate($i, 1, 
        	-text => $self->n2f->{$name}->method_tag,
        );
        
        $hlist->itemCreate($i, 2,
        	-text => $self->n2f->{$name}->description,
        );
        
#        $hlist->itemCreate($i, 3,
#        	-text => $self->n2f->{$name}->is_protein ? 'Protein' : 'DNA',
#        );
       	
        $i++;
    }
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
	
	unless ($self->{_species}) {
		$self->{_species} = 
			$self->DataSetChooser->LocalDatabaseFactory->get_species(
				$self->AceDatabase
			);
	}
	
	return $self->{_species};
}

sub n2f {
	my ($self, $n2f) = @_;
	
	unless ($self->{_n2f}) {
		$self->{_n2f} = $self->AceDatabase->
			pipeline_DataFactory->get_names2filters();
	}
	
	return $self->{_n2f};
}

sub hlist {
	my ($self, $hlist) = @_;
	$self->{_hlist} = $hlist if $hlist;
	weaken($self->{_hlist}) if $hlist;
	return $self->{_hlist};
}

sub XaceSeqChooser {
    my ($self , $xc) = @_ ;
    
    if ($xc) {
    	$self->{_XaceSeqChooser} = $xc;
    	weaken($self->{_XaceSeqChooser});
    }
    
    return $self->{_XaceSeqChooser} ;
}

sub AceDatabase {
    my ($self , $db) = @_ ;
    $self->{_AceDatabase} = $db if $db;
    return $self->{_AceDatabase} ;
}

sub SequenceNotes {
    my ($self , $sn) = @_ ;
    $self->{_SequenceNotes} = $sn if $sn;
    return $self->{_SequenceNotes} ;
}

sub DataSetChooser {
    my ($self , $dc) = @_ ;
    $self->{_DataSetChooser} = $dc if $dc;
    return $self->{_DataSetChooser} ;
}

sub DESTROY {
    my( $self ) = @_;
    warn "Destroying LoadColumns\n";
}

1;

__END__

=head1 NAME - EditWindow::LoadColumns

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk

