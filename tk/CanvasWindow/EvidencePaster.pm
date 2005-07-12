
### CanvasWindow::EvidencePaster

package CanvasWindow::EvidencePaster;

use strict;
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

    $canvas->Tk::bind('<Button-1>',       sub{ $self->left_button_handler });
    $canvas->Tk::bind('<Shift-Button-1>', sub{ $self->shift_left_button_handler });

    $canvas->Tk::bind('<Destroy>', sub{ $self = undef });

    $self->evidence_hash($evidence_hash);
    $self->draw_evidence;
}


sub left_button_handler {
    my( $self ) = @_;
    
    return if $self->delete_message;
    $self->deselect_all;
    $self->shift_left_button_handler;
}

sub shift_left_button_handler {
    my( $self ) = @_;
    
    my $canvas = $self->canvas;

    my ($obj)  = $canvas->find('withtag', 'current')  or return;
    my ($name) = $canvas->gettags($obj) or die "No name on object";

    if ($self->is_selected($obj)) {
        $self->remove_selected($obj);
    } else {
        $self->highlight($obj);
    }
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
        my ($type_and_name) = $canvas->gettags($obj);
        my ($type, $name) = $type_and_name =~ /^(\S+): (\S+)/;
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
    
    my( @evidence );
    foreach my $type (qw{Protein EST cDNA}) {
        my $name_list = $evidence_hash->{$type} or next;
        foreach my $name (@$name_list) {
            push(@evidence, "$type: $name");
        }
    }
    my $font = $self->font;
    my $size = $self->font_size;
    my $row_height = $size + int($size / 6);
    my $x = $size;
    for (my $i = 0; $i < @evidence; $i++) {
        my $text = $evidence[$i];
        my $y = $i * $row_height;
        $canvas->createText($x, $y,
            -anchor => 'nw',
            -text   => $text,
            -font   => [$font, $size, 'normal'],
            -tags   => [$text],
            );
    }
    
    
    $self->fix_window_min_max_sizes;
}

sub paste_type_and_name {
    my( $self ) = @_;
    
    if (my ($type, $name) = $self->type_and_name_from_clipboard) {
        my $evi = $self->evidence_hash;
        my $list = $evi->{$type} ||= [];

        # Hmm, perhaps evidence hash should be two level hash?
        my %uniq = map {$_, 1} @$list;
        $uniq{$name} = 1;
        @$list = sort keys %uniq;

        $self->draw_evidence;
        $self->highlight_evidence_by_name("$type: $name");
    }
}

sub highlight_evidence_by_name {
    my( $self, $name ) = @_;
    
    my $canvas = $self->canvas;
    my ($obj) = $canvas->find('withtag', $name);
    $self->highlight($obj);
}

{
    my %column_type = (
        EST             => 'EST',
        vertebrate_mRNA => 'cDNA',
        BLASTX          => 'Protein',
        );

    #my %lc_second_sw_tr = (
    #    'SW'    => 'Sw',
    #    'TR'    => 'Tr',
    #    );

    sub type_and_name_from_clipboard {
        my( $self ) = @_;

        my $canvas = $self->canvas;

        my( $text );
        eval {
            $text = $canvas->SelectionGet;
        };
        return if $@;
        #warn "Trying to parse: [$text]\n";

        # Sequence:Em:BU533776.1    82637 83110 (474)  EST_Human 99.4 (3 - 478) Em:BU533776.1
        # Sequence:Em:AB042555.1    85437 88797 (3361)  vertebrate_mRNA 99.3 (709 - 4071) Em:AB042555.1
        # Protein:Tr:Q7SYC3    75996 76703 (708)  BLASTX 77.0 (409 - 641) Tr:Q7SYC3

        #if ($text =~ /^(?:Sequence|Protein):(\w\w:[\w\.]+)[\d\(\)\s]+(EST|vertebrate_mRNA|BLASTX)/) {
        if ($text =~ /^(?:Sequence|Protein):(?:\w\w):([\w\.]+)[\d\(\)\s]+(EST|vertebrate_mRNA|BLASTX)/) {
            my $name = $1;
            my $column = $2;
            my $type = $column_type{$column} or die "Can't match '$column'";
            #warn "Got $type:$name\n";
            return ($type, $name);
        }
        elsif ($text =~ /^(?:SW|TR):([\w\.]+)$/i) {
            my $name = $1;
            #$name =~ s/^(..)/ $lc_second_sw_tr{$1} /e;
            return ('Protein', $name);
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

