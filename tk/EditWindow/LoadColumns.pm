
### EditWindow::LoadColumns

package EditWindow::LoadColumns;

use strict;
use Carp;

use Tk::HListplus;
use Tk::Checkbutton;
use Tk::LabFrame;

use base 'EditWindow';

sub initialise {
    my( $self ) = @_;
    
    my $top = $self->top;

	$self->n2f($self->XaceSeqChooser->AceDatabase->
		pipeline_DataFactory->get_names2filters());
    
    # cache the default wanted settings (from otter_config)
	
	$self->{_default_wanted} = { 
		map { $_ => $self->n2f->{$_}->wanted } keys %{ $self->n2f } 
	};

	my $hlist = $top->Scrolled("HListplus",
		-header => 1,
		-columns => 3,
		-scrollbars => 'ose',
		-width => 100,
		-height => 50,
        -selectmode => 'browse',
	)->pack(-expand => 1, -fill => 'both');

	my $i = 0;
	
	$hlist->header('create', $i++,  
    	-itemtype => 'resizebutton', 
    	-command => sub { $self->sort_by_filter_method('wanted') }
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
	    -command => sub {
	    	map { $self->n2f->{$_}->wanted($self->{_default_wanted}->{$_}) } 
	    		keys %{ $self->n2f };
	    },
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
	
	$self->{_last_selection} = { 
		map { $_ => $self->n2f->{$_}->wanted } keys %{ $self->n2f } 
	};
							
	my @to_fetch = grep { $self->n2f->{$_}->wanted && !$self->n2f->{$_}->done } 
							keys %{ $self->n2f };
								
	if (@to_fetch) {
    	# assuming DataFactory has already been initialized by AceDatabase.pm
        if($self->XaceSeqChooser->AceDatabase->topup_pipeline_data_into_ace_server()) {
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
	
    $top->Unbusy;
    $top->withdraw;
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
        $self->hlist->itemCget($i, 0, '-widget')->$fn;
    }
}

sub n2f {
	my ($self, $n2f) = @_;
	$self->{_n2f} = $n2f if $n2f;
	return $self->{_n2f};
}

sub hlist {
	my ($self, $hlist) = @_;
	$self->{_hlist} = $hlist if $hlist;
	return $self->{_hlist};
}

sub XaceSeqChooser{
    my ($self , $seq_chooser) = @_ ;
    $self->{_XaceSeqChooser} = $seq_chooser if $seq_chooser;
    return $self->{_XaceSeqChooser} ;
}

sub show_filters {
   
   	my $self = shift;
   	my $names_in_order = shift || keys %{ $self->n2f };
    
    my $hlist = $self->hlist;
    
    my $i = 0;
    
    for my $name (@$names_in_order) {
    	
    	# eval because delete moans if entry doesn't exist
        eval{ $hlist->delete('entry', $i) };
        
        $hlist->add($i);
        
        my $j = 0;
        
        $hlist->itemCreate($i, $j++, 
            -itemtype => 'window', 
            -widget => $hlist->Checkbutton(
                -variable => \$self->n2f->{$name}->{_wanted},
                -onvalue => 1,
            	-offvalue => 0,
            	-anchor => 'w'
            ),
        );
        
        $hlist->itemCreate($i, $j++, 
        	-text => $self->n2f->{$name}->method_tag
        );
        
        $hlist->itemCreate($i, $j++,
        	-text => $self->n2f->{$name}->description,
        );
        
#        $hlist->itemCreate($i, $j++,
#        	-text => $self->n2f->{$name}->is_protein ? 'Protein' : 'DNA',
#        );
       	
        $i++;
    }
}


1;

__END__

=head1 NAME - EditWindow::LoadColumns

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk

