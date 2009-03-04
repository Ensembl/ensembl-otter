
### EditWindow::Exonerate

package EditWindow::Exonerate;

use strict;
use warnings;
use Carp;

use Hum::Pfetch;
use Hum::FastaFileIO;
use Hum::ClipboardUtils qw{ accessions_from_text };
use Bio::Otter::Lace::Exonerate;
use Bio::Otter::Lace::Client;
use Hum::Sort qw{ ace_sort };
use Tk::LabFrame;
use Tk::Balloon;

use base 'EditWindow';

my $PROT_SCORE = 100;
my $DNA_SCORE  = 100;
my $DNAHSP     = 120;
my $BEST_N	   = 1;

my $INITIAL_DIR = (getpwuid($<))[7];

sub initialise {
	my ( $self ) = @_;
	
    my @frame_pack = (-side => 'top', -fill => 'x');
    my @frame_expand = (-side => 'top', -fill => 'both', -expand => 1);

	my $top  = $self->top;

	### Query frame
	my $query_frame = $top->LabFrame(
        -label      => 'Query sequences',
        -labelside  => 'acrosstop',
        -border     => 3,
	)->pack(@frame_expand);
	
	## Accession entry box
	my $match_frame = $query_frame->Frame( -border => 3 )->pack(@frame_pack);
	$match_frame->Label(
        -text   => 'Accessions:',
        -anchor => 's',
        -padx   => 6,
	)->pack( -side => 'left' );
	$self->match( $match_frame->Entry( -width => 40, )->pack( -side => 'left' ) );
	$match_frame->Frame( -width => 6, )->pack( -side => 'left' );
	
	my $update = sub {
		$self->accessions_from_clipboard;
	};
	$match_frame->Button(
        -text      => 'Fetch from clipboard',
        -underline => 0,
        -command   => $update,
	)->pack( -side => 'left' );
	$top->bind( '<Control-u>', $update );
	$top->bind( '<Control-U>', $update );
	

	## Fasta file entry box
	my $fname;
	my $file_frame = $query_frame->Frame( -border => 3 )->pack(@frame_pack);
	$file_frame->Label(
        -text   => 'Fasta file:',
        -anchor => 's',
        -padx   => 6,
	)->pack( -side => 'left' );

	$self->fasta_file( $file_frame->Entry( -width => 45, -textvariable => \$fname )->pack( -side => 'left' ) );

	# Pad between entries
	$file_frame->Frame( -width => 6, )->pack( -side => 'left' );

	$file_frame->Button(
		-text    => 'Browse...',
		-command => sub {
			$fname = $top->getOpenFile(
			    -title          => 'Choose fasta file',
			    -initialdir     => $INITIAL_DIR,
                -filetypes      => [
                    # ['Fasta Files'  => [qw{ .seq .pep .dna .fasta .fa }]],
                    # ['All Files'    => '*'],

                    # Do not want to show hidden files.
                    ['Fasta Files (*.seq,*.pep,*.dna,*.fasta,*.fa)' => sub {
                        my ($widget, $file, $dir) = @_;
                        # Match non-hidden files which end with one of our extensions
                        return $file =~ /^[^\.].*\.(seq|pep|dna|fasta|fa)$/;
                    } ],
                    ['All Files (*)' => sub {
                        my ($widget, $file, $dir) = @_;
                        # Match non-hidden files
                        return $file !~ /^\./;
                    } ],
                ],

                -sortcmd        => sub { ace_sort(@_) },
			    );
			if ($fname) {
			    if (my ($dir) = $fname =~ m{^(.+?)[^/]+$}) {
                    # warn "Setting inital dir to '$dir'";
			        $INITIAL_DIR = $dir;
			    }
			}
		}
	)->pack( -side => 'left' );
	
	## Sequence text box
	my $txt_frame = $query_frame->Frame( -border => 3 )->pack(@frame_expand);
    $txt_frame->Label(
                     -text   => 'Fasta sequence:',
                     -anchor => 'w',
                     -padx   => 6,
    )->pack(@frame_pack);
	$self->fasta_txt(
		   $txt_frame->Scrolled( "Text",
            -background => 'white',
		   	-height => 12,
		   	-width  => 62,
		   	-scrollbars => 'se',
		   	-font	=> $self->XaceSeqChooser->font_fixed,
		   	 )->pack(@frame_expand)
    );
	
	### Parameters
	my $param_frame = $top->LabFrame(
        -label      => 'Parameters',
        -labelside  => 'acrosstop',
        -border     => 3,
	)->pack(@frame_pack);
	
    $self->bestn(
        $param_frame->Entry(
            -width   => 4,
            -justify => 'right',
            )->pack( -side => 'right' )
        );
	$self->set_entry( 'bestn', $BEST_N );
	$param_frame->Label(
        -text   => 'Number of transcript alignments to report (0 for all):',
        -anchor => 's',
        -padx   => 6,
	)->pack( -side => 'right' );
	
	### Commands
	my $button_frame = $top->Frame->pack(@frame_pack);
	my $launch = sub {
		$self->launch_exonerate or return;
		$top->withdraw;
	};
	$button_frame->Button(
						   -text      => 'Launch',
						   -underline => 0,
						   -command   => $launch,
	)->pack( -side => 'left' );
	$top->bind( '<Control-l>', $launch );
	$top->bind( '<Control-L>', $launch );


	# Manage window closes and destroys
	my $close_window = sub { $top->withdraw };
	$button_frame->Button(
						   -text    => 'Close',
						   -command => $close_window,
	)->pack( -side => 'right' );
	$top->bind( '<Control-w>', $close_window );
	$top->bind( '<Control-W>', $close_window );
	$top->protocol( 'WM_DELETE_WINDOW', $close_window );
	$top->bind( '<Destroy>', sub {	$self = undef ;  } );
	$self->set_minsize;
}

sub update_from_XaceSeqChooser {
	my ( $self ) = @_;
	$self->accessions_from_clipboard;
	my $top = $self->top;
	$top->deiconify;
	$top->raise;
}

sub query_Sequence {
	my ( $self, $query_Sequence ) = @_;
	if ($query_Sequence) {
		$self->{'_query_Sequence'} = $query_Sequence;
	}
	return $self->{'_query_Sequence'};
}

sub accessions_from_clipboard {
    my ($self) = @_;
    
    my $text = $self->get_clipboard_text or return;
    if (my @acc = accessions_from_text($text)) {
        $self->set_entry('match', join ' ', @acc);
    }
}

sub update_from_clipboard {
	my ($self) = @_;
	if ( my ( $name, $start, $end ) = $self->name_start_end_from_fMap_blue_box )
	{
		$self->set_entry( 'match', $name );
	}
}

sub set_entry {
	my ( $self, $method, $txt ) = @_;
	my $entry = $self->$method();
	
	my $reset = 0;
	if ($entry->cget('-state') eq 'readonly') {
		$entry->configure( -state => 'normal' );
		$reset = 1;
	}
	
	$entry->delete( 0, 'end' );
	$entry->insert( 0, $txt );
	
	$entry->configure( -state => 'readonly' ) if $reset;
}

sub get_entry {
	my ( $self, $method ) = @_;

	my $txt = $self->$method()->get or return;
	return $txt;
}

sub method_tag {
	my ( $self, $match ) = @_;
	if ($match) {
		$self->{'_method_tag'} = $match;
	}
	return $self->{'_method_tag'};
}

sub fasta_txt {
	my ( $self, $txt ) = @_;
	if ($txt) {
		$self->{'_fasta_txt'} = $txt;
	}
	return $self->{'_fasta_txt'};
}

sub fasta_file {
	my ( $self, $file ) = @_;
	if ($file) {
		$self->{'_fasta_file'} = $file;
	}
	return $self->{'_fasta_file'};
}

sub bestn {
	my ( $self, $bestn ) = @_;
	if ($bestn) {
		$self->{'_bestn'} = $bestn;
	}
	return $self->{'_bestn'};
}

sub match {
	my ( $self, $match ) = @_;
	if ($match) {
		$self->{'_match'} = $match;
	}
	return $self->{'_match'};
}

sub genomic {
	my ( $self, $genomic ) = @_;
	if ($genomic) {
		$self->{'_genomic'} = $genomic;
	}
	return $self->{'_genomic'};
}

sub genomic_start {
	my ( $self, $genomic_start ) = @_;
	if ( defined $genomic_start ) {
		$self->{'_genomic_start'} = $genomic_start;
	}
	return $self->{'_genomic_start'};
}

sub genomic_end {
	my ( $self, $genomic_end ) = @_;
	if ( defined $genomic_end ) {
		$self->{'_genomic_end'} = $genomic_end;
	}
	return $self->{'_genomic_end'};
}

sub flank {
	my ( $self, $flank ) = @_;
	if ($flank) {
		$self->{'_flank'} = $flank;
	}
	return $self->{'_flank'};
}

sub revcomp_ref {
	my ( $self, $revcomp_ref ) = @_;
	if ($revcomp_ref) {
		$self->{'_revcomp_ref'} = $revcomp_ref;
	}
	return $self->{'_revcomp_ref'};
}

sub XaceSeqChooser {
	my ($self,$xc) = @_;
	if ($xc) {
		$self->{'_xc'} = $xc;
	}
	return $self->{'_xc'};
}

sub launch_exonerate {
	my ($self) = @_;
	
	my $seqs = $self->get_query_seq();
	print STDOUT "Found " . scalar(@$seqs) . " sequences\n";
	
	unless (@$seqs) {
	    $self->top->messageBox(
	        -title      => 'No sequence',
	        -icon       => 'warning',
	        -message    => 'Did not get any sequence data',
	        -type       => 'OK',
	        );
	    return;
	}

	# identify the types of the sequences
	
	$self->{_client} = Bio::Otter::Lace::Client->new unless $self->{_client};
	my $types = $self->{_client}->get_accession_types(map { $_->name } @$seqs);
	map { $_->type($types->{$_->name}) } @$seqs;

	my %params = ();
	
	# These methods are now in the methods.ace file, so the auto-generated
	# method in Bio::Otter::Lace::Exonerate is not used.
	
	$params{Protein}->{method_tag} = 'OTF_Protein';
	$params{Protein}->{query_type} = 'protein';
	$params{Protein}->{method_color} = 'GREEN';
	
	$params{Unknown_Protein}->{method_tag} = 'Unknown_Protein';
	$params{Unknown_Protein}->{query_type} = 'protein';
	$params{Unknown_Protein}->{method_color} = 'BROWN';
	
	$params{mRNA}->{method_tag} = 'OTF_mRNA';
	$params{mRNA}->{query_type} = 'dna';
	$params{mRNA}->{method_color} = 'BLUE';
	
	$params{EST}->{method_tag} = 'OTF_EST';
	$params{EST}->{query_type} = 'dna';
	$params{EST}->{method_color} = 'RED';
	
	$params{Unknown_DNA}->{method_tag} = 'Unknown_DNA';
	$params{Unknown_DNA}->{query_type} = 'dna';
	$params{Unknown_DNA}->{method_color} = 'YELLOW';
	
	my %seqs_by_type = ();
	
	for my $seq (@$seqs) {
		
		if ($seq->type &&
			($seq->type eq 'EST' || 
			 $seq->type eq 'mRNA' || 
			 $seq->type eq 'Protein')) {
			push @{ $seqs_by_type{$seq->type} }, $seq;
		}
		elsif ($seq->sequence_string =~ /^[AGCTNagctn\s]*$/) {
			push @{ $seqs_by_type{Unknown_DNA} }, $seq;
		}
		else {
			push @{ $seqs_by_type{Unknown_Protein} }, $seq;
		}
	}
	
	$self->top->Busy;
	
	my $need_relaunch = 0;
	
	for my $type (keys %seqs_by_type) {
		
		print STDOUT "Running exonerate for sequence(s) of type: $type\n";
			
		my $score   = $type =~ /Protein/ ? $PROT_SCORE : $DNA_SCORE;
		my $dnahsp  = $DNAHSP;
		my $m_tag   = $params{$type}->{method_tag};
		my $m_color = $params{$type}->{method_color};
		my $query_type = $params{$type}->{query_type};
		my $l_name  = $params{$type}->{method_tag};
		my $best_n = $self->get_entry('bestn');
		
		unless ( $score and $m_tag and $m_color and $l_name and $seqs_by_type{$type}) {
			warn "Missing parameters\n";
			next;
		}
	
		my $exonerate = Bio::Otter::Lace::Exonerate->new;
		$exonerate->AceDatabase($self->XaceSeqChooser->AceDatabase);
		$exonerate->genomic_seq($self->XaceSeqChooser->Assembly->Sequence);
		$exonerate->query_seq($seqs_by_type{$type});
		$exonerate->query_type($query_type);
		$exonerate->score($score);
		$exonerate->dnahsp($dnahsp);
		$exonerate->bestn($best_n);
		$exonerate->method_tag($m_tag);
		$exonerate->method_color($m_color);
		$exonerate->logic_name($l_name);
		my $seq_file = $exonerate->write_seq_file();
		if($seq_file){
			$exonerate->initialise($seq_file);
			my $ace_text = $exonerate->run;
			# delete query file
			unlink $seq_file;
			
			next unless $ace_text;
			
			$need_relaunch = 1;
			
			#print "ACE_TEXT:\n\n$ace_text\n\n";
			
			# Need to add new method to collection if we don't have it already
	    	my $coll = $exonerate->AceDatabase->MethodCollection;
	    	my $coll_zmap = $self->XaceSeqChooser->Assembly->MethodCollection;
	    	my $method = $exonerate->ace_Method;
	    	unless ($coll->get_Method_by_name($method->name) ||
	    			$coll_zmap->get_Method_by_name($method->name)) {
	        	$coll->add_Method($method);
	        	$coll_zmap->add_Method($method);
	        	$self->XaceSeqChooser->save_ace($coll->ace_string());
	    	}
	
			$self->XaceSeqChooser->save_ace($ace_text);
			$self->XaceSeqChooser->zMapWriteDotZmap;
		}
	}
	
	if ($need_relaunch) {
		$self->XaceSeqChooser->resync_with_db();
		$self->XaceSeqChooser->zMapLaunchZmap;
	}
	
	$self->top->Unbusy;
	
	if ($need_relaunch) {	    
    	return 1;
	} else {
	    $self->top->messageBox(
	        -title      => 'No matches',
	        -icon       => 'warning',
	        -message    => 'Exonerate did not find any matches on genomic sequence',
	        -type       => 'OK',
	        );
	    return 0;
	}
}

my $seq_tag = 1;

sub get_query_seq {
	my ($self) = @_;
	my @seq;
	
	if (my $txt = $self->get_entry('match')) {
		my @accessions = split /[,;\|\s]+/, $txt;
		if (@accessions) {
		    warn "Going to fetch accessions: ", join(', ', map "'$_'", @accessions);
			push @seq, Hum::Pfetch::get_Sequences(@accessions);
		}
	}
	if ( my $string = $self->fasta_txt->get( '1.0', 'end' ) ) {
		if ($string =~ /\S/ and $string !~ />/) {
			print "creating new seq tag num: $seq_tag\n";
			$string = ">OTF_seq_$seq_tag\n" . $string;
			$seq_tag++;
		}
		push @seq, Hum::FastaFileIO->new_String_IO($string)->read_all_sequences;
	}
	if ( $self->get_entry('fasta_file') ) {
		push @seq, Hum::FastaFileIO->new( $self->get_entry('fasta_file') )
		  	->read_all_sequences;
	}
	
	return \@seq;
}

sub DESTROY {
    my ($self) = shift;

	warn "Freeing exonerateWindow '$self'\n";
}

1;

__END__

=head1 NAME - EditWindow::Exonerate

=head1 AUTHOR

Anacode B<email> anacode@sanger.ac.uk

