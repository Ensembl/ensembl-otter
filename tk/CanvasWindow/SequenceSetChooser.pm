
### CanvasWindow::SequenceSetChooser

package CanvasWindow::SequenceSetChooser;

use strict;
use Carp;
use base 'CanvasWindow';
use CanvasWindow::SequenceNotes;
use CanvasWindow::SequenceNotes::SearchedSequenceNotes ;
use Hum::Sort 'ace_sort';

sub new {
    my( $pkg, @args ) = @_;
    
    my $self = $pkg->SUPER::new(@args);
    
    my $canvas = $self->canvas;
    $canvas->Tk::bind('<Button-1>', sub{
            $self->deselect_all;
            $self->select_sequence_set;
        });
    my $edit_command = sub{ $self->open_sequence_set; };
    $canvas->Tk::bind('<Double-Button-1>',  $edit_command);
    $canvas->Tk::bind('<Return>',           $edit_command);
    $canvas->Tk::bind('<KP_Enter>',         $edit_command);
    $canvas->Tk::bind('<Control-o>',        $edit_command);
    $canvas->Tk::bind('<Control-O>',        $edit_command);
    $canvas->Tk::bind('<Escape>', sub{ $self->deselect_all });
    
    my $close_window = sub{
	my $top = $self->DataSetChooser->canvas->toplevel;
	$top->deiconify;
	$top->raise;
	$self->canvas->toplevel->destroy;
	$self->clean_SequenceNotes();
	$self = undef;  # $self will not get DESTROY'd without this
    };
    $canvas->Tk::bind('<Control-w>',                $close_window);
    $canvas->Tk::bind('<Control-W>',                $close_window);
    $canvas->toplevel->protocol('WM_DELETE_WINDOW', $close_window);

        
    my $top = $canvas->toplevel;
    my $button_frame = $top->Frame->pack(-side => 'top', -fill => 'x');
    my $open = $button_frame->Button(
        -text       => 'Open',
        -command    => sub {
            unless ($self->open_sequence_set) {
                $self->message("No SequenceSet selected - click on one to select");
            }
        },
        )->pack(-side => 'left');
    
    my $search_command = sub { $self->search_window };
    my $search = $button_frame->Button(
        -text       => 'Search' ,
        -command    => $search_command,
    )->pack(-side =>'left') ;
    $canvas->Tk::bind('<Control-f>', $search_command);
    $canvas->Tk::bind('<Control-F>', $search_command);
    
    my $quit = $button_frame->Button(
        -text       => 'Close',
        -command    => $close_window,
        )->pack(-side => 'right');
    
    return $self;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub Client {
    my( $self, $Client ) = @_;
    
    if ($Client) {
        $self->{'_Client'} = $Client;
    }
    return $self->{'_Client'};
}

sub DataSet {
    my( $self, $DataSet ) = @_;
    
    if ($DataSet) {
        $self->{'_DataSet'} = $DataSet;
    }
    return $self->{'_DataSet'};
}

sub DataSetChooser {
    my( $self, $DataSetChooser ) = @_;
    
    if ($DataSetChooser) {
        $self->{'_DataSetChooser'} = $DataSetChooser;
    }
    return $self->{'_DataSetChooser'};
}

sub draw {
    my( $self ) = @_;
    
    my $font    = $self->font;
    my $size    = $self->font_size;
    my $canvas  = $self->canvas;

    my $font_def = [$font,       $size, 'bold'];
    my $helv_def = ['Helvetica', $size, 'normal'];

    my $ds = $self->Client->get_DataSet_by_name($self->name);
    my $ss_list = $ds->get_all_SequenceSets;
    my $row_height = int $size * 1.5;
    my $x = $size;

    $ss_list = [ sort { ace_sort($a->name, $b->name) } @$ss_list];

    for (my $i = 0; $i < @$ss_list; $i++) {
        my $set = $ss_list->[$i];
        my $row = $i + 1;
        my $y = $row_height * $row;
        $canvas->createText(
            $x, $y,
            -text   => $set->name,
            -font   => $font_def,
            -anchor => 'nw',
            -tags   => ["row=$row", 'SetName', 'SequenceSet=' . $set->name],
            );
    }
    
    $x = ($canvas->bbox('SetName'))[2] + ($size * 2);
    for (my $i = 0; $i < @$ss_list; $i++) {
        my $set = $ss_list->[$i];
        my $row = $i + 1;
        my $y = $row_height * $row;
        $canvas->createText(
            $x, $y,
            -text   => $set->description,
            -font   => $helv_def,
            -anchor => 'nw',
            -tags   => ["row=$row", 'SetDescription', 'SequenceSet=' . $set->name],
            );
    }
    
    $x = $size;
    my $max_x = ($canvas->bbox('SetDescription'))[2];
    for (my $i = 0; $i < @$ss_list; $i++) {
        my $set = $ss_list->[$i];
        my $row = $i + 1;
        my $y = $row_height * $row;
        my $rec = $canvas->createRectangle(
            $x, $y, $max_x, $y + $size,
            -fill       => undef,
            -outline    => undef,
            -tags   => ["row=$row", 'SetBackground', 'SequenceSet=' . $set->name],
            );
        $canvas->lower($rec, "row=$row");
    }
    
    
    $self->fix_window_min_max_sizes;
}

sub select_sequence_set {
    my( $self ) = @_;
    
    return if $self->delete_message;
    my $canvas = $self->canvas;
    if (my ($current) = $canvas->find('withtag', 'current')) {
        my( $ss_tag );
        foreach my $tag ($canvas->gettags($current)) {
            if ($tag =~ /^SequenceSet=/) {
                $ss_tag = $tag;
                last;
            }
        }
        if ($ss_tag) {
            $self->highlight($ss_tag);
        }
    } else {
        $self->deselect_all;
    }
}

sub add_SequenceNotes{
    my ($self, $sn) = @_;
    if ($sn){
	$self->{'_sequence_notes'}->{"$sn"} = $sn;
    }
    return $self->{'_sequence_notes'}->{"$sn"};
}

sub get_SequenceNotes_by_name{
    my ($self, $name) = @_;
    my $seqNotes = $self->{'_sequence_notes'} || {};
    foreach my $hash_id(keys %$seqNotes){
	next unless $seqNotes->{$hash_id};
	my $sn = $seqNotes->{$hash_id};
	my $sn_name = $sn->name();
	next unless $name eq $sn_name;
	# See bind_close_window method of SequenceNotes.
	# $sn->SequenceSetChooser($self);
	$sn->canvas->toplevel->deiconify();
	$sn->canvas->toplevel->raise();
	return 1;
    }
    return 0;
}
sub clean_SequenceNotes{
    my ($self) = @_;
    my $seqNotes = $self->{'_sequence_notes'} || {};
     
    foreach my $hash_id(keys %$seqNotes){
#	warn $hash_id ;
        $seqNotes->{"$hash_id"} = undef;
	delete $seqNotes->{"$hash_id"};
    }
    return 0;
}

sub open_sequence_set {
    my( $self ) = @_;
    
    my ($obj) = $self->list_selected;
    my $canvas = $self->canvas;
    foreach my $tag ($canvas->gettags($obj)) {
        if ($tag =~ /^SequenceSet=(.+)/) {
            my $name = $1;

	    # there's already a SequenceNotes obj available.
            return 1 if $self->get_SequenceNotes_by_name($name);

            my $this_top = $canvas->toplevel;
            
            ### in this case Busy() seems to globally grab pointer - why?
            ### grabStatus reports 'local' - but it is a global grab.
            #$this_top->Busy(
            #    -recurse    => 1,
            #    );   
            #my $status = $this_top->grabStatus;
            #warn "grab = $status\n";
            
            ## Using this instead:
            $this_top->configure(-cursor => 'watch');
            
            my $top = $this_top->Toplevel(-title => "SequenceSet $name");
            my $ss = $self->DataSet->get_SequenceSet_by_name($name);


            
            my $sn = CanvasWindow::SequenceNotes->new($top);
            $sn->name($name);
            $sn->Client($self->Client);
            $sn->SequenceSet($ss);
            $sn->SequenceSetChooser($self);
            $sn->initialise;
            $sn->draw;   
            $self->add_SequenceNotes($sn);
           
            #$this_top->Unbusy;
            $this_top->configure(-cursor => undef);
            
            return 1;
        }
    }
    return;
}

# brings up a window for searching for loci / clones
sub search_window{
    my ($self) = @_ ;
    
    my $search_window = $self->{'_search_window'} ; 
  
    unless (defined ($search_window) ){
        ## make a new window
        my $master = $self->canvas->toplevel;
        $search_window = $master->Toplevel(-title => 'Find loci or clones');
        $search_window->transient($master);
        
        $search_window->protocol('WM_DELETE_WINDOW', sub{$search_window->withdraw});
    
        my $label           =   $search_window->Label(-text     =>  "Use spaces to separate multiple names"
                )->pack(-side   =>  'top');
        
        my $search_entry    =   $search_window->Entry(   
                                                    -width      => 30       ,
                                                    -relief     => 'sunken' ,
                                                    -borderwidth=> 2        ,
                                                    #-font       =>   'Helvetica-14',   
                )->pack(    -side => 'top' , 
                            -padx => 5 ,
                            -fill => 'x'    
                            ) ;
                            
        $search_entry->bind('<Return>' , sub {$self->search}) ;
        $self->{'search_entry'} = $search_entry ;
        
        
        ## radio buttons        
        my $radio_variable = 'locus' ;         
        my $radio_frame = $search_window->Frame(    
                )->pack(    -side   =>  'top'   ,
                            -pady   =>  5       ,
                            -fill   =>  'x'     ,) ; 
        my $locus_radio = $radio_frame->Radiobutton(  -text       =>  'locus',
                                                      -variable   =>  \$radio_variable  ,
                                                      -value      =>  'locus' ,       
                )->pack(    -side    =>  'left' ,
                            -padx    =>   5  ,
                        ) ; 
        my $clone_radio = $radio_frame->Radiobutton(    -text       =>  'intl. clone name or accession'  , 
                                                        -variable   =>  \$radio_variable    ,
                                                        -value      =>  'clone'
                )->pack(    -side   =>  'right' ,
                            -padx   =>  5
                        );
        
        
        ## search cancel buttons
        my $search_cancel_frame = $search_window->Frame(
                )->pack(-side => 'bottom'   , 
                        -padx =>  5         ,
                        -pady =>  5         , 
                        -fill => 'x'        , ) ;   
        my $find_button     =   $search_cancel_frame->Button(   -text       => 'Search' ,
                                                                -command    =>  sub{$self->search($radio_variable)}    
                )->pack(    -side    => 'left') ;
        my $cancel_button   =   $search_cancel_frame->Button(   -text       => 'cancel'   ,
                                                                -command    => sub { $search_window->withdraw }
                )->pack(-side => 'right');
           
        $self->{'_search_window'} = $search_window ;
        $search_window->bind('<Destroy>' , sub { $self = undef }  ) ;
    }
    
    $search_window->deiconify;
    $search_window->raise ;
    $search_window->focus ;
    $self->{'search_entry'}->focus;
}


sub search{
    my ($self , $search_type) = @_ ;
    
    $search_type = 'locus' unless defined $search_type ; # defaults to locus search 
    
    my $rs = Bio::Otter::Lace::ResultSet->new ;
    $rs->DataSet($self->DataSet) ;
    my $search = $self->{'search_entry'}->get   ;
    my @search_names = split /\s+/ ,  $search ;
        
    if ($search_type eq 'clone') {
        $rs->search_type('clone') ;
    } else {
        $rs->search_type('locus') ; # defaults to locus 
    }
    
    my $clones_found = $rs->execute_search(\@search_names) ;
    
    if ( $clones_found > 0 ){
    my $top = $self->canvas->toplevel->Toplevel(  -title  =>  'Search results for ' . $self->{'search_entry'}->get );
        my $sn = CanvasWindow::SequenceNotes::SearchedSequenceNotes->new($top);

        $sn->name('Search Results'); 
        $sn->Client($self->Client);
        $sn->ResultSet($rs);
        $sn->SequenceSetChooser($self);
        $sn->initialise;
        $sn->draw;
        $top->raise ;
        $self->add_SequenceNotes($sn) ;              
    }
    else{
        ## send mesasage to main window
        $self->message("no $search_type matched your search criteria") ;
    }
    
    # remove the window from viewing
    my $search_window = $self->{'_search_window'} ;
    $search_window->withdraw();   

}




sub DESTROY {
    my( $self ) = @_;

    my ($type) = ref($self) =~ /([^:]+)$/;
    my $name = $self->name;
    warn "Destroying $type $name\n";
}

1;

__END__

=head1 NAME - CanvasWindow::SequenceSetChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

