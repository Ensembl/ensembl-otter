=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


package Bio::Otter::UI::TextWindow::Peptide;

use 5.012;

use strict;
use warnings;

use Try::Tiny;

use Bio::Otter::Lace::Client;

use parent 'Bio::Otter::UI::TextWindow';

my $highlight_hydrophobic = 0;

sub new {
    my ($pkg, $parent) = @_;
    my $self = $pkg->SUPER::new($parent);
    my $window = $self->window;

    # Red for stop codons
    $window->tagConfigure('redstop',
                           -background => '#ef0000',
                           -foreground => 'white',
        );

    # Blue for "X", the unknown amino acid
    $window->tagConfigure('blueunk',
                           -background => '#0000ef',
                           -foreground => 'white',
        );

    # Light grey background for hydrophobic amino acids
    $window->tagConfigure('greyphobic',
                           -background => '#cccccc',
                           -foreground => 'black',
        );

    # Gold for methionine codons
    $window->tagConfigure('goldmeth',
                           -background => '#ffd700',
                           -foreground => 'black',
        );
    $window->tagBind('goldmeth', '<Button-1>',
                      sub{ $self->trim_cds_coord_to_current_methionine; }
        );
    $window->tagBind('goldmeth', '<Enter>',
                      sub{ $window->configure(-cursor => 'arrow'); }
        );
    $window->tagBind('goldmeth', '<Leave>',
                      sub{ $window->configure(-cursor => 'xterm'); }
        );
#    check_kozak needs overhaul.
#    $window->tagBind('goldmeth' , '<Button-3>' ,
#                      sub{ $self->check_kozak}
#        );

    # Green for selenocysteines
    $window->tagConfigure('greenseleno',
                           -background => '#32cd32',
                           -foreground => 'white',
        );

    $window->bind('<Destroy>', sub{ $self = undef });

    return $self;
}

sub buttons {
    my ($self, $frame, $top) = @_;

    my $trim_command = sub{
        $self->parent->trim_cds_coord_to_first_stop;
        $self->parent->update_translation;
    };
    $frame->Button(
        -text       => 'Trim',
        -underline  => 0,
        -command    => $trim_command ,
        )->pack(-side => 'left');
    $top->bind('<Control-t>',   $trim_command);
    $top->bind('<Control-T>',   $trim_command);
    $top->bind('<Return>',      $trim_command);
    $top->bind('<KP_Enter>',    $trim_command);

    $self->{'_highlight_hydrophobic'} = $highlight_hydrophobic;
    my $toggle_hydrophobic = sub {
        # Save preferred state for next translation window
        $highlight_hydrophobic = $self->{'_highlight_hydrophobic'};
        $self->parent->update_translation;
    };
    my $hydrophobic = $frame->Checkbutton(
        -command    => $toggle_hydrophobic,
        -variable   => \$self->{'_highlight_hydrophobic'},
        -text       => 'Highlight hydrophobic',
        -padx       => 6,
        )->pack(-side => 'left', -padx => 6);

    # Close only unmaps it from the display
    my $close_command = sub{ $top->withdraw };
    return $close_command;
}

sub update_translation {
    my ($self, $subseq) = @_;

    my $window = $self->window;

    # Empty the text widget
    $window->delete('1.0', 'end');

    my $error;
    try {
        $subseq->validate;
    }
    finally {
        $error = shift;
    };
    if ($error) {
        $self->parent->exception_message($error, 'Invalid transcript');
        $window->insert('end', "TRANSLATION ERROR");
    } else {
        # Put the new translation into the Text widget

        my $pep = $subseq->translator->translate($subseq->translatable_Sequence);
        $window->insert('end', sprintf(">%s\n", $pep->name));

        my $line_length = 60;
        my $str = $pep->sequence_string;
        my $map = $subseq->codon_start_map;
        my %style = qw{
            *   redstop
            X   blueunk
            M   goldmeth
            U   greenseleno
            };
        if ($self->{'_highlight_hydrophobic'}) {
            %style = (%style, qw{
                A   greyphobic
                C   greyphobic
                G   greyphobic
                I   greyphobic
                L   greyphobic
                F   greyphobic
                P   greyphobic
                W   greyphobic
                V   greyphobic
                });
        }
        my $pep_genomic = $self->{'_peptext_index_to_genomic_position'} = {};

        # If we are showing an "X" amino acid at the start due to a partial
        # codon we need to take 1 off the index into the codon_start_map
        my $offset = $str =~ /^X/ ? 1 : 0;

        for (my $i = 0; $i < length($str); $i++) {
            my $char = substr($str, $i, 1);
            my $tag = $style{$char};
            $window->insert('end', $char, $tag);

            if ($char eq 'M') {
                my $index = $window->index('insert - 1 chars');
                #warn sprintf "$index  $map->[$i]\n";
                $pep_genomic->{$index} = $map->[$i - $offset];
            }

            unless (($i + 1) % $line_length) {
                $window->insert('end', "\n");
            }
        }
    }

    $self->size_widget;

    # Set the window title
    $window->toplevel->configure(-title => sprintf("%sTranslation %s",
                                                   $Bio::Otter::Lace::Client::PFX,
                                                   $subseq->name) );

    return 1;
}

sub check_kozak{
    my ($self) = @_;

    my $parent = $self->parent;
    my $pep_window = $self->window;
    my $kozak_window = $self->{'_kozak_window'} ;
    # create a new window if none available
    unless (defined $kozak_window){
        my $master = $parent->canvas->toplevel;
        $kozak_window = $master->Toplevel
          (-title => $Bio::Otter::Lace::Client::PFX.'Kozak Checker');
        $kozak_window->transient($master);

        my $font = $parent->font_fixed;

        $kozak_window->Label(
                -font           => $font,
                -text           => "5'\n3'" ,
                -padx                   => 6,
                -pady                   => 6,
                )->pack(-side   => 'left');

        my $kozak_txt = $kozak_window->ROText(
                -font           => $font,
                #-justify        => 'left',
                -padx                   => 6,
                -pady                   => 6,
                -relief                 => 'groove',
                -background             => 'white',
                -border                 => 2,
                -selectbackground       => 'gold',
                #-exportselection => 1,

                -width                  => 10 ,
                -height                 => 2 ,
                )->pack(-side   => 'left' ,
                        -expand => 1      ,
                        -fill   => 'both' ,
                        );


        $kozak_window->Label(
                -font           => $font,
                -text           => "3'\n5'" ,
                -padx                   => 6,
                -pady                   => 6,
                )->pack(-side   => 'left');

        my $close_kozak = sub { $kozak_window->withdraw } ;
        $kozak_window->bind('<Destroy>', sub{ $self = undef });
        my $kozak_butt = $kozak_window->Button( -text       => 'close' ,
                                            -command    => $close_kozak ,
                                            )->pack(-side => 'left')  ;
        $self->{'_kozak_txt'} = $kozak_txt ;
        $self->{'_kozak_window'} = $kozak_window;

    }

    my $kozak_txt = $self->{'_kozak_txt'} ;

    ### get index of selected methionine
    my $pep_index = $pep_window->index('current');
    my $seq_index = $self->{'_peptext_index_to_genomic_position'}{$pep_index} or return;

    my $subseq = $self->parent->SubSeq ;
    my $clone_seq = $subseq->clone_Sequence();
    my $sequence_string = $clone_seq->sequence_string;
    my $strand = $subseq->strand;

    my $k_start ;

    if ($strand == 1){
        $k_start = ($seq_index  - 7 ) ;
    }else{
        $k_start = ($seq_index  - 4 ) ;
    }

    my $kozak ;
    if ( $k_start >= 0 ){
        $kozak = substr($sequence_string ,  $k_start  , 10 ) ;
    }
    else{
        # if subseq  goes off start , this will pad it with '*'s to make it 10 chars long
        $kozak =  "*" x ( $k_start * -1) . substr($sequence_string ,  0  , 10 + $k_start ) ;
    }

    my $rev_kozak = $kozak ;
    $rev_kozak =~ tr{acgtrymkswhbvdnACGTRYMKSWHBVDN}
                    {tgcayrkmswdvbhnTGCAYRKMSWDVBHN};
    $kozak  =~ s/t/u/g  ;
    $rev_kozak =~ s/t/u/g  ;


    $kozak_window->resizable( 1 , 1)  ;
    $kozak_txt->delete( '1.0' , 'end')  ;
    $kozak_window->resizable(0 , 0)  ;

    # higlight parts of sequence that match
    # green for matches codons
    $kozak_txt->tagConfigure('match',
            -background => '#AAFF66',
            );

    # from an email from [cas]
    # shows how the template matches various recognised Kozak consensi.
    ############################  perfect, strong, adequate, chr22 version
    my @template_kozak = ('(a|g)',   # G
                          'c',       # C
                          'c',       # C
                          'a',       # A    A   G   G  Y     G
                          'c',       # C    n   n   n  n     n
                          'c',       # C    n   n   n  n     n
                          'a',       # A    A   A   A  A     A
                          'u',       # T    T   T   T  T     T
                          'g',       # G    G   G   G  G     G
                          'g');      # G    n   G   Y  G     A

    ## for some reason (tk bug?) tk would not display tags added to the
    ## second line when using the index system - hence two loops rather
    ## than one
    for( my $i = 0 ;  $i <= ( length($kozak) - 1) ; $i++ ){
        my $pos_char = substr( $kozak , $i , 1) ;
        my $template = $template_kozak[$i] ;
        if ($pos_char  =~ /$template/ && $strand == 1){
            $kozak_txt->insert('end' , "$pos_char" , 'match');
        }else{
            $kozak_txt->insert('end' , "$pos_char" );
        }
    }

    for (my $i = 0 ;  $i <= ( length($rev_kozak) - 1) ; $i++ ){
        my $template = $template_kozak[9 - $i] ;
        my $neg_char = substr( $rev_kozak ,  $i   , 1) ;
        if ($neg_char  =~ /$template/  && $strand == -1){
            $kozak_txt->insert('end' , "$neg_char" , "match");
        }else{
            $kozak_txt->insert('end' , "$neg_char");
        }
    }

    $kozak_window->deiconify;
    $kozak_window->raise ;

    return;
}

sub trim_cds_coord_to_current_methionine {
    my ($self) = @_;

    my $index = $self->window->index('current');
    my $new = $self->{'_peptext_index_to_genomic_position'}{$index} or return;

    $self->parent->adjust_tk_t_start($new);

    return;
}

sub width {
    return 60;
}

1;

__END__

=head1 NAME - Bio::Otter::UI::TextWindow::Peptide

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
