
### ChooserCanvas::AnaNotes




package ChooserCanvas::AnaNotes;

use strict;
use base 'ChooserCanvas';

use Bio::EnsEMBL::Pipeline::AnaSubmission qw{ set_db_args sub_db prepare_statement get_db}  ;
use Hum::Submission qw{ submission_user user_has_access  get_user};
use Hum::SubmissionVersion;

use Hum::AnaStatus qw{ annotator_full_name };

use Hum::Conf qw{ HUMACESERVER_HOST HUMGIFACESERVER_PORT };
use GenomeCanvas::Band::SeqChooser;

use HistoryPopup;

use Carp;
use Tk::ROText;
use Tk::Dialog;


use Bio::Otter::Lace::PipelineDB;

sub new{
    my ($self , $mw) = @_;
    
    if (! defined $mw){
        $mw =  CanvasWindow::MainWindow->new();
    }
    $mw->title("AnaNotes");

    my $AnaNotes = $self->SUPER::new($mw);
    
        $AnaNotes->main_window($mw);
    
    return $AnaNotes;
}


sub main_window{
    my ($self , $mw) = @_;
    
    if ($mw){
        $self->{'_main_window'} = $mw ;
    }
    return $self->{'_main_window'};    
}


sub run_ana_notes{
    my ($self, $set_name , $annotator ) = @_;
    
    $self->annotator_uname('ck2');
    $set_name = "newtest1";
    
    my ($annotator_id , $user);
    $user = $self->annotator_uname;
    if ($self->is_valid_annotator($user , $set_name)){
        $annotator = $user;
        $annotator_id = annotator_id($user);
    }
    
    
    my $mw = $self->main_window;
   
    $mw->title($set_name);
    my $gc = $self;

    my $chooser = GenomeCanvas::Band::SeqChooser->new;
    $gc->sequence_chooser($chooser);


    $chooser->chooser_map($self->make_chooser_map($set_name)); # chooser map stores informaion of db results
    $chooser->chooser_tags(get_seq_chooser_tags());     # chooser tags are the tags that go with each line of the display - taken from choosermap
    my @display_list = (1,2,3,4,5,6);                  # list contains the coulmns in the order to be displayed
    # if you want to display different columns / different order , then change this list to correspont with the rows in the chooser_map 
    $chooser->chooser_display_list(\@display_list);    
    
    my $canvas = $gc->canvas;
   
    $canvas->configure(-selectbackground => 'gold');
    $canvas->CanvasBind('<Button-1>', sub {
        return if $gc->delete_message;
        $gc->deselect_all_selected_not_current();
        $gc->toggle_current;
        });
    $canvas->CanvasBind('<Shift-Button-1>', sub {
        return if $gc->delete_message;
        $gc->toggle_current;
        });
    
    {
        my( $comment );
        if ($annotator) {
            my $button_frame = $mw->Frame;
            $button_frame->pack(
                -side => 'top',
                );

            my $comment_label = $button_frame->Label(
                -text => 'Note text:',
                );
            $comment_label->pack(
                -side => 'left',
                );

            $comment = $button_frame->Entry(
                -width              => 55,
                -background         => 'white',
                -selectbackground   => 'gold',
                );
            $comment->pack(
                -side => 'left',
                );
        }
        
        
        my $button_frame2 = $mw->Frame;
        $button_frame2->pack(
            -side => 'top',
            );
        
        if ($annotator) {
            my $set_reviewed = sub{
                my $c = $comment->get;
                my @ana_seq_id_list = $gc->list_selected_unique_ids();
                return unless @ana_seq_id_list;
                set_reviewed($annotator_id, $c, @ana_seq_id_list);
                $chooser->chooser_map(make_chooser_map($set_name));
                $gc->render;
                $gc->set_scroll_region_and_maxsize;
                };
            make_button($button_frame2, 'Set note', $set_reviewed, 0);
            $mw->bind('<Control-s>', $set_reviewed);
            $mw->bind('<Control-S>', $set_reviewed);
        }
        
        my $hunter = sub{
            watch_cursor($mw);
            hunt_for_selection($gc);
            default_cursor($mw);
            };
        
        ## First call to this returns empty list!
        #my @all_text_obj = $canvas->find('withtag', 'contig_text');
        
        make_button($button_frame2, 'Hunt selection', $hunter, 0);
        $mw->bind('<Control-h>', $hunter);
        $mw->bind('<Control-H>', $hunter);
        
        my $refesher = sub{
            watch_cursor($mw);
            $chooser->chooser_map($gc->make_chooser_map($set_name));
            $gc->render;
            $gc->set_scroll_region_and_maxsize;
            default_cursor($mw);
            };
        make_button($button_frame2, 'Refresh', $refesher, 0);
        $mw->bind('<Control-r>', $refesher);
        $mw->bind('<Control-R>', $refesher);
        $mw->bind('<F5>', $refesher);

        my $run_lace = sub{
            watch_cursor($mw);
            my @sequence_name_list = list_selected_accessions($canvas);
            return unless @sequence_name_list;
            fork_lace_process($annotator, @sequence_name_list);
            default_cursor($mw);
            };
        make_button($button_frame2, 'Run lace', $run_lace, 4);
        $mw->bind('<Control-l>', $run_lace);
        $mw->bind('<Control-L>', $run_lace);

        if ($annotator) {
            
            my $do_embl_dump = sub{
                watch_cursor($mw);
                my @sequence_name_list = list_selected_sequence_names($canvas);
                foreach my $seq (@sequence_name_list) {
                    do_embl_dump($seq);
                }
                default_cursor($mw);
                };
            make_button($button_frame2, 'EMBL dump', $do_embl_dump, 0);
            $mw->bind('<Control-e>', $do_embl_dump);
            $mw->bind('<Control-E>', $do_embl_dump);
        }
        
        my $print_to_file = sub {
            $gc->page_width(591);
            $gc->page_height(841);
            my @files = $gc->print_postscript($set_name);
            warn "Printed to files:\n",
                map "  $_\n", @files;
          };
        $mw->bind('<Control-p>', $print_to_file);
        $mw->bind('<Control-P>', $print_to_file);
                    

        
        $mw->bind('<Control-Button-1>', sub{ $gc->popup_ana_seq_history });
        $mw->bind('<Double-Button-1>',  sub{ $gc->popup_ana_seq_history });
        make_button($button_frame2, 'Quit',    sub{ $self->pipeline_db( undef); # otherwise we see "potential memory leak" errors 
                                                    $mw->destroy }, 0);
    }
    
    
    $gc->render;
    $gc->fix_window_min_max_sizes;
    
    ###############
    Tk::MainLoop();
    ###############    
}



##-----------------------------------------------------------------------------------
#each row has the format ..
##  [0] clone_name
##  [1] clone_accession
##  [2] author_name
##  [3] note time
##  [4] note
##  [5] status
##  [6] contig_id

sub make_chooser_map {
    my( $self , $set_name ) = @_;
    
    my $pipeline_db = $self->pipeline_db;
    unless (defined $pipeline_db){
    ## connect to otterdb to get pipeline db details. get submission status from there
        my $otter_db = get_db();
        $pipeline_db = Bio::Otter::Lace::PipelineDB::get_pipeline_DBAdaptor($otter_db) ;
        $self->pipeline_db($pipeline_db)
    }
               
    confess "No set_id given" unless $set_name;
    
    print STDERR "Getting set notes...";
        
    my $sql = qq{
        SELECT      cl.name ,
            cl.embl_acc ,
            cl.embl_version , 
            au.author_name ,
            sn.note_time, 
            sn.note,
            cg.contig_id,
            a.chr_start,
            a.chr_end
        FROM  sequence_set ss ,
              clone cl,
              contig cg  
        LEFT JOIN assembly a ON 
            ss.assembly_type = a.type
        LEFT JOIN sequence_note sn  
            ON sn.contig_id = a.contig_id
        LEFT JOIN author au 
            ON au.author_id = sn.author_id
        WHERE cg.contig_id  = a.contig_id 
        AND cl.clone_id = cg.clone_id
        AND (sn.is_current = 'Y'
        OR sn.is_current IS NULL)
        AND ss.assembly_type = ? 
        ORDER BY chr_start , chr_end , sn.note_time        
        } ;
    
    
        
    my $sth = prepare_statement($sql);
    $sth->execute($set_name);

    my(  $clone_name,   $acc,       $ver,
         $author_name,  $note_time, $note ,
         $contig_id,         $chr_st ,   $chr_end 
          );
    $sth->bind_columns(
         \$clone_name,  \$acc,       \$ver,
         \$author_name, \$note_time, \$note ,
         \$contig_id,   \$chr_st ,     \$chr_end );
    
    my( @map );
    my $prev_end ;
    while ($sth->fetch) {
        
        # if there is a gap of more than 10 kb , add a gap band        
        if (defined $prev_end && ($chr_st - $prev_end) > 10000 )
        {  
            push(@map, ['GAP']);
        }
        $prev_end = $chr_end;
        
        # format time 
        ($note_time) = $note_time =~ /(\d{4}-\d\d-\d\d)/ if $note_time;
        

        my $status ;        
        $status = get_status($pipeline_db , $clone_name);   

        push(@map, [$contig_id , $clone_name, $acc,  $author_name, $note_time, $note , $status]);
    }
    print STDERR " got them.\n";
    
    return @map;    
}

#----------------------------------------------------------------------------------------------------

sub get_seq_chooser_tags{
    ## these chooser tags correspond to the chooser map produced below, to make the sequence_chooser work
    ##  note that item 0 is a unique id for that line - in this case the clone name
    my %tag_hash = ("dbid=" => 6 , "sequence_name="=> 0  , "accession=" => 1 , "unique_id="=>0) ;   
    
    return \%tag_hash ;
    
}

#--------------------------------------------------------------------------------------------------------
# return 1 if annotator has RW access; 0 if not;
sub is_valid_annotator {
    my( $self , $annotator, $set_name ) = @_;

    my $access_type = user_has_access($annotator, $set_name);

    # if access is restricted and this annotator has no access then report as if no such set
    if($access_type eq ''){
	die "No such set '$set_name'\n";
    }elsif($access_type eq 'RW'){
	return 1;
    }else{
	return 0;
    }
}
#----------------------------------------------------------------------------------------

sub annotator_id{
    my $username = shift @_ ;
    
    my $sth = prepare_statement(q{
        SELECT author_id FROM author WHERE author_email = ?
        });
    $sth->execute($username);
    my $id = $sth->fetchrow;
    return $id;    
}

sub annotator_uname{
    my ($self, $uname) = @_ ;
    
    if ($uname){
        $self->{'_username'} = $uname;
    }
    return $self->{'_username'};
   
}

sub default_cursor {
    my( $w ) = @_;
    
    $w->configure( -cursor => undef );
    $w->update;
}


sub get_hist_chooser_tags{
    ## these chooser tags correspond to the  2d array produced below, to make the hist_chooser work
    
    my %tag_hash = ("unique_id=" => 0) ;   
    
    return \%tag_hash ;
    
}
#--------------------------------------------------------------------------------------------------------------------------
## this next method returns a 2d array that holds most of the information for the history canvas.
## the 1st array contains information contained in each row of the display. Each row (currently) has the format 
## [0] row_id 
## [1] contig_id
## [2] contig name
## [3] note time
## [4] author name
## [5] note
## [6] db_id 

    sub get_history_for_ana_seq_id {
        my( $asid ) = @_;
    
        my $sth = prepare_statement(qq{
            SELECT  cg.contig_id ,
                    cg.name ,
                    sn.note_time ,
                    a.author_name ,
                    sn.note   
            FROM    sequence_note sn,
                    author a,
                    contig cg        
            WHERE   cg.contig_id = sn.contig_id
            AND     a.author_id = sn.author_id
            AND     cg.contig_id = ?
            ORDER BY sn.note_time DESC
        });
    
        $sth->execute($asid);
    
        my @text  ;
        my $id = 0; # for just now - used as a row_id - needs a unique identifier, as the clone name wont work in the history 
        while (my @row = $sth->fetchrow) { 
        
            unshift @row , $id;

            push (@text,[@row]);            
            $id++;
        } 
    
        # if an undefined array is returned, the choosermap get/set method will not update the previous version 
        if (! @text ){
            @text = [-1, -1 ,"no notes to go with this contig"];
        }
        return @text;
    }

#--------------------------------------------------------------------------------------------------------------------


sub get_status{
    my ($db , $name) = @_ ;
    
    my $sth = $db->prepare(q{ SELECT status 
                    FROM job j, job_status js, clone c
                    WHERE  j.job_id = js.job_id
                    AND c.name = j.input_id
                    AND is_current = 'Y'
                    AND c.name = ?
                    });
    
    $sth->execute($name);
    
    my $status = $sth->fetch();

    
    if ($status){
        return @$status->[0];
    }else {
        return "";
    }
}

sub hunt_for_selection {
    my( $gc ) = @_;
    
    my $canvas = $gc->canvas;

    ##my $ana_seq = get_current_ana_seq_id($canvas);
    ##return unless $ana_seq;

    ##my ($rec) = $canvas->find('withtag', "ana_seq_id=$ana_seq&&contig_seq_rectangle");        
    ##toggle_selection($gc, $rec);
    my( $query_str );
    eval {
        $query_str = $canvas->SelectionGet;
    };
    return if $@;
    #warn "Looking for '$query_str'";
    my $matcher = make_matcher($query_str);
    
    my $current_obj;
    foreach my $obj ($canvas->find('withtag', 'selected')) {
        $current_obj ||= $obj;
        $gc->toggle_selection($gc, $obj);
    }
    
    my $selected_text_obj = $canvas->selectItem;

    ### Weirdly, I have to call this "find" twice,
    ### or the first time it is called it returns
    ### an empty list.
    my @all_text_obj = $canvas->find('withtag', 'contig_text');
       @all_text_obj = $canvas->find('withtag', 'contig_text');
    
    if ($selected_text_obj) {
        if ($selected_text_obj == $all_text_obj[$#all_text_obj]) {
            # selected obj is last on list, so is to leave at end
        } else {
            for (my $i = 0; $i < @all_text_obj; $i++) {
                if ($all_text_obj[$i] == $selected_text_obj) {
                    my @tail = @all_text_obj[$i + 1 .. $#all_text_obj];
                    my @head = @all_text_obj[0 .. $i];
                    @all_text_obj = (@tail, @head);
                    last;
                }
            }
        }
    }

    my $found = 0;
    foreach my $obj (@all_text_obj) {
        my $text = $canvas->itemcget($obj, 'text');
        my $hit = &$matcher($text);
        if ($hit) {
            $canvas->selectClear;
            my $start = index($text, $hit);
            die "Can't find '$hit' in '$text'" if $start == -1;
            $canvas->selectFrom($obj, $start);
            $canvas->selectTo  ($obj, $start + length($hit) - 1);
            $found = $obj;
            last;
        }
    }
    
    unless ($found) {
        $gc->message("Can't find '$query_str'");
        return;
    }
    
    $gc->scroll_to_obj($found);
    
    my @overlapping = $canvas->find('overlapping', $canvas->bbox($found));
    foreach my $obj (@overlapping) {
        my @tags = $canvas->gettags($obj);
        if (grep $_ eq 'contig_seq_rectangle', @tags) {
            unless (grep $_ eq 'selected', @tags) {
                $gc->toggle_selection($gc, $obj);
            }
        }
    }
}

sub is_annotator{
    
    my $self = shift @_ ;
    
    my $annotator = $self->annotator_uname;
    
    my $set_name = $self->set_name;
    my $access_type = user_has_access($annotator, $set_name);

    # if access is restricted and this annotator has no access then report as if no such set
    if($access_type eq ''){
	die "No such set '$set_name'\n";
    }elsif($access_type eq 'RW'){
	return 1;
    }else{
	return 0;
    }
}


sub list_selected_unique_ids{
    
    my ($self) = shift @_;
    my $canvas = $self->canvas;
    my @selected_objects = $canvas->find('withtag', 'selected');
    my( @db_id_list );
    foreach my $obj (@selected_objects) { 
        my ($ana_seq_id) = grep s/^unique_id=//, $canvas->gettags($obj); 
        die "Found selected object without unique_id" unless $ana_seq_id;
        push(@db_id_list, $ana_seq_id);
    }
    
    warn "list @db_id_list";
    return @db_id_list;
    
}

sub make_button{
    my( $parent, $label, $command, $underline_index ) = @_;
    
    my @args = (
        -text => $label,
        -command => $command,
        );
    push(@args, -underline => $underline_index)
        if defined $underline_index;
    my $button = $parent->Button(@args);
    $button->pack(
        -side => 'left',
        );
    return $button;
}

sub make_matcher {
    my( $pattern ) = @_;
    
    # Escape non word characters
    $pattern =~ s{(\W)}{\\$1}g;
    
    my $matcher = eval "sub {
        my( \$text ) = \@_;
        
        \$text =~ /($pattern)/i;
        return \$1;
        }";
    if ($@) {
        die "Error in pattern '$pattern' \n$@";
    } else {
        return $matcher;
    }
}

sub pipeline_db{
    my ($self, $pipeline_db)  = @_ ;
    
    if ($pipeline_db){
        $self->{'_pipeline_db'} = $pipeline_db;
    }
    return $self->{'_pipeline_db'};    
}



{
    my( $top, $hist , $hist_gen_canv, $hist_chooser , $comment_string, $asid);
    my ($hist_popup);
    sub popup_ana_seq_history{
        
        my ($gc) = shift  @_ ;
        my $main_canvas = $gc->canvas;
  
        $asid = $gc->get_unique_id 
            or return;
        
        unless ($hist_popup)
        {   # basically, if there is no popup, create one
            $hist_popup = HistoryPopup->new(1,3,5);
            $hist_popup->make_popup($main_canvas , $asid); 
        }
        else{
            $hist_popup->comment_string('');
        }
        
        # create choosermap object and pass it to the hist_chooser 
        my @text = get_history_for_ana_seq_id($asid);
        $hist_chooser = $hist_popup->hist_chooser();
                          
        $hist_chooser->chooser_map(@text);

        $hist_chooser->chooser_tags(get_hist_chooser_tags());
        my @display_list = (6, 5 , 4 , 3 , 2);                   # this is the list of elements in the chooser_map array that are to be displayed
        $hist_chooser->chooser_display_list(\@display_list);  
    
        $hist_gen_canv = $hist_popup->history_canvas; 
        $hist_gen_canv->render;
        $hist_gen_canv->fix_window_min_max_sizes;
        $hist_popup->display;
    }
}
 
sub set_name{
    my ($self , $set_name) = @_ ;
    if ($set_name ){
        $self->{'_set_name'} = $set_name ;
    }
    return $self->{'_set_name'} ;
    
}

sub set_reviewed {
    my( $user, $comment, @ana_id_list ) = @_;
  
    foreach my $id (@ana_id_list) {
        update_old_notes($id);
        add_new_entry($id, $user, $comment);
    }
}

sub watch_cursor {
    my( $w ) = @_;
    
    $w->configure( -cursor => 'watch' );
    $w->update;
}


sub update_old_notes{
    my  $ctg_id = shift @_;
#    warn "updating contig : $ctg_id";
    my ($sth);
    
    $sth ||= prepare_statement(q{
                UPDATE sequence_note 
                SET is_current = 'N'
                WHERE contig_id = ?
    });
    $sth->execute($ctg_id);    
}


   



1;

__END__

=head1 NAME - GenomeCanvas::AnaNotes

=head1 AUTHOR

Colin Kingswood,,,, B<email> ck2@sanger.ac.uk

