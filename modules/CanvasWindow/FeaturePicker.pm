
### CanvasWindow::FeaturePicker

package CanvasWindow::FeaturePicker;

use strict;
use warnings;
use base 'CanvasWindow';
use Carp;
use Hum::Ace::XaceRemote;

sub new {
    my ($pkg, @args) = @_;
    
    my $self = $pkg->SUPER::new(@args);

    my $canvas = $self->canvas;

    $canvas->Tk::bind('<Button-1>', sub{
            $self->select_feature;
        });
    $canvas->Tk::bind('<Escape>', sub{ $self->deselect_all });

    my $top = $canvas->toplevel;
    my $button_frame = $top->Frame->pack(-side => 'top', -fill => 'x');

    my $open_command = sub{ $self->show_selected_in_zmap; };
    $canvas->Tk::bind('<Double-Button-1>',  $open_command);
    $canvas->Tk::bind('<Return>',           $open_command);
    $canvas->Tk::bind('<KP_Enter>',         $open_command);
    $canvas->Tk::bind('<Control-d>',        $open_command);
    $canvas->Tk::bind('<Control-D>',        $open_command);

    $canvas->Tk::bind('<Up>',   sub{ $self->next_match(-1) });
    $canvas->Tk::bind('<Down>', sub{ $self->next_match( 1) });

    my $attach = $button_frame->Button(
        -text       => 'Attach zMap',
        -command    => sub {
            $self->attach_zmap
        },
        )->pack(-side => 'left');
    my $open = $button_frame->Button(
        -text       => 'Display',
        -command    => $open_command,
        )->pack(-side => 'left');

    my $close_window = sub{
        $self->canvas->toplevel->destroy;
        $self = undef;  # $self gets nicely DESTROY'd with this
        };
    $canvas->Tk::bind('<Control-q>',    $close_window);
    $canvas->Tk::bind('<Control-Q>',    $close_window);
    $canvas->toplevel
        ->protocol('WM_DELETE_WINDOW',  $close_window);
    my $quit = $button_frame->Button(
        -text       => 'Quit',
        -command    => $close_window,
        )->pack(-side => 'right');
        
    return $self;
}

sub next_match {
    my ($self, $incr) = @_;
    
    my ($obj) = $self->list_selected or return;
    $obj += $incr;
    my $canvas = $self->canvas;
    if ($canvas->gettags($obj)) {
        $self->deselect_all;
        $self->highlight($obj);
        $self->scroll_to_obj($obj);
    }

    return;
}

sub select_feature {
    my ($self) = @_;
    
    return if $self->delete_message;
    my $canvas = $self->canvas;
    $self->deselect_all;
    if (my ($current) = $canvas->find('withtag', 'current')) {
        $self->highlight($current);
    }

    return;
}

sub show_selected_in_zmap {
    my ($self) = @_;
    
    my ($obj) = $self->list_selected or return;
    my $canvas = $self->canvas;
    my $ftr_i = undef;
    foreach my $tag ($canvas->gettags($obj)) {
        if ($tag =~ /^feature_index=(\d+)/) {
            $ftr_i = $1;
            last;
        }
    }
    return unless defined($ftr_i);
    my $ftr = $self->feature_list->[$ftr_i];
    
    my $zmap_rem = $self->zmap_remote;
    unless ($zmap_rem) {
        $self->message('No zMap attached');
        return;
    }
    
    my $command = join(' ; ',
        'feature_find method = readpairs',
        'type = homol',
        "feature = $ftr->{query_name}",
        "q_start = $ftr->{query_start}",
        "q_end = $ftr->{query_end}",
        "t_start = $ftr->{subject_start}",
        "t_end = $ftr->{subject_end}",
        "strand = $ftr->{strand}",
       );
    warn $command;
    eval {
        $zmap_rem->send_command($command);
    };
    $self->exception_message($@) if $@;

    return;
}

sub parse_feature_filehandle {
    my ($self, $fh) = @_;
    
    my $feat_list = $self->feature_list;
    
    my $row = 0;
    while (<$fh>) {
        next if /^$/;
        my( $line_type,
            $sw_score,
            $query_name,
            $subject_name,
            $query_start,
            $query_end,
            $subject_start,
            $subject_end,
            $strand,
            $match_length,
            $identity,
            $query_length ) = split;
        unless ($line_type eq 'ALIGNMENT') {
            next;
        }
        #if ($strand eq 'F') {
        #    $strand = 1;
        #} elsif ($strand eq 'C') {
        #    $strand = -1;
        #} else {
        #    confess "Unknown strand '$strand' in line: $_";
        #}
        my $match = {
            'row_num'       => ++$row,
            'sw_score'      => $sw_score,
            'query_name'    => $query_name,
            'subject_name'  => $subject_name,
            'query_start'   => $query_start,
            'query_end'     => $query_end,
            'subject_start' => $subject_start,
            'subject_end'   => $subject_end,
            'strand'        => $strand,
            'match_length'  => $match_length,
            'identity'      => $identity . '%',
            'query_length'  => $query_length,
            };
        push(@$feat_list, $match);
    }

    return;
}

sub feature_list {
    my ($self) = @_;
    
    my $feat_list = $self->{'_feature_list'} ||= [];
    return $feat_list;
}

sub draw_feature_list {
    my ($self) = @_;
    
    my $feat_list = $self->feature_list;
    my @fields = qw{
        row_num
        subject_start
        subject_end
        query_name
        query_start
        query_end
        strand
        sw_score
        identity
        };
    my( %field_widths );
    foreach my $fld (@fields) {
        my $max_width = 0;
        foreach my $ftr (@$feat_list) {
            my $len = length($ftr->{$fld});
            $max_width = $len if $len > $max_width;
        }
        confess "No data in '$fld' field" unless $max_width;
        $field_widths{$fld} = $max_width
    }
    
    my( @format );
    foreach my $fld (@fields) {
        push(@format, "\%$field_widths{$fld}s");
    }
    my $printf_str = join('  ', @format);
    my $font_size = 10;
    my $font = 'courier';
    my $font_def = ['courier', $font_size];
    my $font_line_height = 1.2 * $font_size;
    
    my $canvas = $self->canvas;
    for (my $i = 0; $i < @$feat_list; $i++) {
        my $x = 0;
        my $y = $i * $font_line_height;
        my $ftr = $feat_list->[$i];
        my $txt_str = sprintf $printf_str, map { $ftr->{$_} } @fields;
        $canvas->createText($x, $y,
            -font   => $font_def,
            -text   => $txt_str,
            -tags   => ["feature_index=$i"],
            );
    }
    
    $self->fix_window_min_max_sizes;

    return;
}

sub zmap_remote {
    my ($self, $zmap_remote) = @_;
    
    if ($zmap_remote) {
        warn "Saving $zmap_remote";
        $self->{'_zmap_remote'} = $zmap_remote;
    }
    return $self->{'_zmap_remote'};
}

sub attach_zmap {
    my ($self) = @_;
    
    if (my $xwid = $self->get_zmap_window_id) {
        my $xrem = Hum::Ace::XaceRemote->new($xwid);
        $self->zmap_remote($xrem);
    }

    return;
}

sub get_zmap_window_id {
    my ($self) = @_;
    
    my $mid = $self->message("Please click on the zMap main window with the cross-hairs");
    $self->delete_message($mid);
    open my $xwid_pipe, '-|', 'xwininfo'
        or confess("Can't open pipe from xwininfo : $!");
    my( $xwid );
    while (<$xwid_pipe>) {
        # xwininfo: Window id: 0x7c00026 "ACEDB 4_9c, lace bA314N13"

        if (/Window id: (\w+)\s+(.+)/) {
            $xwid = $1;
            my $name = $2;
            $name =~ s/\s+$//;
            $name =~ s/^"|"$//g;
            $self->message("Attached to:\n$name");
        }
    }
    if (close $xwid_pipe) {
        return $xwid;
    } else {
        $self->message("Error running xwininfo: exit $?");
        return;
    }
}

#  ALIGNMENT  238  20SNP45079-1505c12.p1c NC_chr20.5  40  387  2613255  2613598  F  348 91.09 518
#
#  and here is Zemins description....
#
#  In order:
#
#  "238":                  smith-waterman score;
#  20SNP45079-1505c12.p1c: query name;
#  NC_chr20.5:             subject contig name;
#  40:                     start query match position;
#  387:                    end query match position;
#  2613255:                start subject match position;
#  2613598:                end subject match position;
#  "F":                    forward ("C" means reverse complement");
#  348:                    match length;
#  91.09                   match indentity(matched bases/match length);
#  518:                    query length;


1;

__END__

=head1 NAME - CanvasWindow::FeaturePicker

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=head1 SEE ALSO

        From:    edgrif@sanger.ac.uk
        Subject: "spec" for program to drive ZMap
        Date:    November 15, 2004 10:00:06 GMT
        To:      jgrg@sanger.ac.uk
        Cc:      rnc@sanger.ac.uk

James,

Richard wants to be able to see a list of his readpair data in some kind of list
which he can then click on and have the ZMap display move automatically to that
readpair feature and highlight it.

I don't want to have this piece of code embedded in ZMap because he wants the
order of his list of features maintained (and various other things peculiar to
his data) and with the current ZMap design this will not be so.


Therefore one way of tackling this is to write a separate program that:

- reads in his data from a file

- displays it more or less "asis" in a selectable list (but note that the list
might be very long and therefore not all displayable in one go in a list window)

- responds to him clicking on a readpair in the list by sending a message via
xremote to zmap which causes zmap to move to that feature and highlight it


I have made zmap work with the xremote protocol and will add the commands
required to do the moving/highlighting.


The program will have to take a list item that looks essentially like this:

"ALIGNMENT  238   20SNP45079-1505c12.p1c NC_chr20.5       40      387   2613255
2613598   F     348 91.09 518"

and send it to zmap in a form something like this:

"method = readpairs ; type = homol ; sequence = 20SNP45079-1505c12.p1c ; strand = F ;
q_start = 40 ; q_end = 387 ; t_start = 2613255 ; t_end = 2613598"


I think its ok for the program to get the user to click on the zmap window they
want to send the request to, you could call the utility program xwininfo to do
this bit and get the windowid for the xremote request from the output.

It think this sounds like a perl/Tk program which would use xremote in much the
same way as lace does currently and wondered if you might have someone who would
code this up and hence learn something of xremote and start to interact with
ZMap as well.

cheers Ed
-- 
 ------------------------------------------------------------------------
| Ed Griffiths, Acedb development, Informatics Group,                    |
|        Wellcome Trust Sanger Institute, Wellcome Trust Genome Campus,  |
|               Hinxton, Cambridge CB10 1SA, UK                          |
|                                                                        |
| email: edgrif@sanger.ac.uk  Tel: +44-1223-494780  Fax: +44-1223-494919 |
 ------------------------------------------------------------------------


