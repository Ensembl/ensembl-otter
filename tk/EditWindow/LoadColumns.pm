
### EditWindow::LoadColumns

package EditWindow::LoadColumns;

use strict;
use Carp;

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
    		# (schwartzian) hack to get done filters sorted before wanted but 
    		# undone filters - note that '/' is ascii-betically before 1 or 0!
    		map {$self->n2f->{$_}->wanted('/') if $self->n2f->{$_}->done} keys %{ $self->n2f };
    		$self->sort_by_filter_method('wanted');
    		map {$self->n2f->{$_}->wanted(1) if $self->n2f->{$_}->done} keys %{ $self->n2f };
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
	
	$control_frame->Button(
	    -text => 'Close', 
	    -command => sub { $top->withdraw }
	)->pack(-side => 'right', -expand => 0);
    
    $self->{_default_sort_method} = 'method_tag';
    
    $self->sort_by_filter_method('method_tag');
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
		# we need to set up and show an XaceSeChooser
        
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
	
	$self->{_sorted_by} ||= '';
	
	my $flip = $self->{_sorted_by} eq $method;
	
	my @sorted_names = sort { 
		$cmp_filters->($n2f{$a}, $n2f{$b}, $method, $flip) || 
		$cmp_filters->($n2f{$a}, $n2f{$b}, $self->{_default_sort_method})	
	} keys %n2f;
	
	$self->{_sorted_by} = $flip ? $method.'_rev' : $method;
	
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
	return $self->{_hlist};
}

sub XaceSeqChooser {
    my ($self , $xc) = @_ ;
    $self->{_XaceSeqChooser} = $xc if $xc;
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

1;

__END__

=head1 NAME - EditWindow::LoadColumns

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk

