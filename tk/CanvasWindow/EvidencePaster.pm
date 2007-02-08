
### CanvasWindow::EvidencePaster

package CanvasWindow::EvidencePaster;

use strict;
use Scalar::Util 'weaken';
use Hum::Ace::AceText;
use base 'CanvasWindow';

sub initialise {
    my( $self, $evidence_hash ) = @_;

    my $canvas = $self->canvas;
    my $top = $canvas->toplevel;
    $top->configure(-title => "Supporting evidence");

    my $button_frame = $top->Frame->pack(
        -side => 'top',
        -fill => 'x',
        );

    my $draw = sub{ $self->draw_evidence };
    $top->bind('<Control-u>', $draw);
    $top->bind('<Control-u>', $draw);
    #$button_frame->Button(
    #    -text => 'Update',
    #    -command => $draw,
    #    )->pack(-side => 'left');

    my $paste = sub{ $self->paste_type_and_name };
    $top->bind('<Control-v>', $paste);
    $top->bind('<Control-V>', $paste);
    $top->bind('<Button-2>',  $paste);
    $button_frame->Button(
        -text => 'Paste',
        -command => $paste,
        )->pack(-side => 'left');

    my $delete = sub{ $self->remove_selected_from_evidence_list };
    $top->bind('<BackSpace>', $delete);
    $top->bind('<Delete>',    $delete);
    $top->bind('<Control-x>', $delete);
    $top->bind('<Control-X>', $delete);
    $button_frame->Button(
        -text => 'Delete',
        -command => $delete,
        )->pack(-side => 'left');
    
    my $close_window = sub{ $top->withdraw; };
    $top->bind('<Control-w>',           $close_window);
    $top->bind('<Control-W>',           $close_window);
    $top->protocol('WM_DELETE_WINDOW',  $close_window);
    $button_frame->Button(
        -text => 'Close',
        -command => $close_window,
        )->pack(-side => 'right');

    my $select_all = sub{ $self->select_all };
    $top->bind('<Control-a>', $select_all);
    $top->bind('<Control-A>', $select_all);
    $canvas->SelectionHandle( sub{ $self->selected_text_to_clipboard(@_) });

    $canvas->Tk::bind('<Button-1>',         sub{ $self->left_button_handler });
    $canvas->Tk::bind('<Control-Button-1>', sub{ $self->control_left_button_handler });
    $canvas->Tk::bind('<Shift-Button-1>',   sub{ $self->shift_left_button_handler });

    $canvas->Tk::bind('<Destroy>', sub{ $self = undef });
    

    $self->evidence_hash($evidence_hash);
    $self->draw_evidence;
}

sub ExonCanvas {
    my( $self, $ExonCanvas ) = @_;
    
    if ($ExonCanvas) {
        $self->{'_ExonCanvas'} = $ExonCanvas;
        weaken($self->{'_ExonCanvas'});
    }
    return $self->{'_ExonCanvas'};
}

sub left_button_handler {
    my( $self ) = @_;
    
    return if $self->delete_message;
    $self->deselect_all;
    $self->control_left_button_handler;
}

sub control_left_button_handler {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;

    my ($obj)  = $canvas->find('withtag', 'current&&!IGNORE')
      or return;

    if ($self->is_selected($obj)) {
        $self->remove_selected($obj);
    } else {
        $self->highlight($obj);
    }
}

sub shift_left_button_handler {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;

    return unless $canvas->find('withtag', 'current&&!IGNORE');

    $self->extend_highlight('!IGNORE');
}

sub select_all {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    
    $self->highlight(
        $canvas->find('withtag', '!IGNORE')
        );
}

sub evidence_hash {
    my( $self, $evidence_hash ) = @_;
    
    if ($evidence_hash) {
        $self->{'_evidence_hash'} = $evidence_hash;
    }
    return $self->{'_evidence_hash'};
}

sub remove_selected_from_evidence_list {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;
    my $evi    = $self->evidence_hash;
    foreach my $obj ($self->list_selected) {
        my ($type) = $canvas->gettags($obj);
        my ($name) = $canvas->itemcget($obj, 'text');
        my $name_list = $evi->{$type} or die "No list with key '$type' in evidence hash";
        for (my $i = 0; $i < @$name_list; $i++) {
            if ($name_list->[$i] eq $name) {
                splice(@$name_list, $i, 1);
                #warn "Found '$name'!";
            }
        }
    }
    $self->draw_evidence;
}

sub draw_evidence {
    my( $self ) = @_;

    $self->deselect_all;

    my $evidence_hash = $self->evidence_hash;
    my $canvas = $self->canvas;
    $canvas->delete('all');
    
    my $font = $self->font;
    my $size = $self->font_size;
    my $row_height = $size + int($size / 6);
    my $type_pad = $row_height / 2;
    my $x = $size;
    
    my $y = 0;
    foreach my $type (qw{ Protein cDNA EST }) {
        my $name_list = $evidence_hash->{$type} or next;
        next unless @$name_list;

        $canvas->createText(0, $y,
            -anchor => 'ne',
            -text   => $type,
            -font   => [$font, $size, 'bold'],
            -tags   => ['IGNORE'],
            );

        my $x = $size;
        foreach my $text (@$name_list) {
            $canvas->createText($x, $y,
                -anchor => 'nw',
                -text   => $text,
                -font   => [$font, $size, 'normal'],
                -tags   => [$type],
                );
            $y += $row_height;
        }

        $y += $type_pad
    }
    
    $self->canvas->toplevel->configure(
        -title => 'Evi: ' . $self->ExonCanvas->SubSeq->name,
        );
    $self->fix_window_min_max_sizes;
}

sub paste_type_and_name {
    my( $self ) = @_;
    
    if (my $clip_evi = $self->type_and_name_from_clipboard) {
        foreach my $type (keys %$clip_evi) {
            my $clip_list = $clip_evi->{$type};
            my $evi = $self->evidence_hash;
            my $list = $evi->{$type} ||= [];

            # Hmm, perhaps evidence hash should be two level hash?
            my %uniq = map {$_, 1} (@$list, @$clip_list);
            @$list = sort keys %uniq;
        }
        $self->draw_evidence;
        foreach my $type (keys %$clip_evi) {
            my $clip_list = $clip_evi->{$type};
            foreach my $name (@$clip_list) {
                $self->highlight_evidence_by_type_name($type, $name);
            }
        }
    }
}

sub highlight_evidence_by_type_name {
    my( $self, $type, $name ) = @_;
    
    my $canvas = $self->canvas;
    foreach my $obj ($canvas->find('withtag', $type)) {
        my $text = $canvas->itemcget($obj, 'text');
        if ($text eq $name) {
            $self->highlight($obj);
            last;
        }
    }
}

sub highlight {
    my $self = shift;
    
    $self->SUPER::highlight(@_);
    $self->canvas->SelectionOwn(
        -command    => sub{ $self->deselect_all },
        );
    weaken $self;
}


sub type_and_name_from_clipboard {
    my ($self) = @_;

    my $canvas = $self->canvas;

    my ($clip);
    eval { $clip = $canvas->SelectionGet; };
    return if $@;

    my $clip_hash = {};
    foreach my $text (split /\n+/, $clip) {
        my ($type, $name) = $self->type_and_name_from_text($text);
        if ($type) {
            my $list = $clip_hash->{$type} ||= [];
            push(@$list, $name);
        }
    }
    return $clip_hash;
}

{
    my %column_type = (
        EST             => 'EST',
        vertebrate_mRNA => 'cDNA',
        BLASTX          => 'Protein',
        SwissProt       => 'Protein',
        TrEMBL          => 'Protein',
    );

    sub type_and_name_from_text {
        my ($self, $text) = @_;


        #warn "Trying to parse: [$text]\n";

        # Sequence:Em:BU533776.1    82637 83110 (474)  EST_Human 99.4 (3 - 478) Em:BU533776.1
        # Sequence:Em:AB042555.1    85437 88797 (3361)  vertebrate_mRNA 99.3 (709 - 4071) Em:AB042555.1
        # Protein:Tr:Q7SYC3    75996 76703 (708)  BLASTX 77.0 (409 - 641) Tr:Q7SYC3
        # Protein:"Sw:Q16635-4.1"    14669 14761 (93)  BLASTX 100.0 (124 - 154) Sw:Q16635-4.1

        if ($text =~
    /^(?:Sequence|Protein):"?(\w\w:[\-\.\w]+)"?[\d\(\)\s]+(EST|vertebrate_mRNA|BLASTX)/
          )
        {
            my $name   = $1;
            my $column = $2;
            my $type   = $column_type{$column} or die "Can't match '$column'";

            #warn "Got blue box $type:$name\n";
            return ($type, $name);
        }
        elsif (
            $text =~ /
              ([A-Za-z]{2}:)?       # Optional prefix
              (
                                    # Something that looks like an accession:
                  [A-Z]+\d{5,}      # one or more letters followed by 5 or more digits
                  |                 # or, for TrEMBL,
                  [A-Z]\d[A-Z\d]{4} # a capital letter, a digit, then 4 letters and digits.
              )
              (\-\d+)?              # Optional VARSPLICE suffix
              (\.\d+)?              # Optional .SV
                /x
          )
        {
            my $prefix = $1 || '*';
            my $acc    = $2;
            $acc .= $3 if $3;
            my $sv     = $4 || '*';

            #warn "Got name '$prefix$acc$sv'";
            my $ace = $self->ExonCanvas->XaceSeqChooser->ace_handle;
            my ($type, $name);
            foreach my $class (qw{ Sequence Protein }) {
                $ace->raw_query(qq{find $class "$prefix$acc$sv"});
                my $txt =
                  Hum::Ace::AceText->new(
                    $ace->raw_query(qq{show -a DNA_homol}));
                print STDERR $$txt;
                my @seq = map $_->[1], $txt->get_values($class) or next;
                if (@seq > 1) {
                    $self->message(join '', "Got multiple matches:\n",
                        map "  $_\n", @seq);
                    last;
                }
                $name = $seq[0];
                my $homol_method = ($txt->get_values('DNA_homol'))[0]->[1];
                $homol_method =~ s/^(EST)_.+/$1/;
                $type = $column_type{$homol_method};
            }
            if ($type and $name) {
                return ($type, $name);
            }
            else {
                return;
            }
        }
        else {
            #warn "Didn't match: '$text'\n";
            return;
        }
    }
}

sub DESTROY {
    warn "Destrying ", ref(shift), "\n";
}

1;

__END__

=head1 NAME - CanvasWindow::EvidencePaster

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

