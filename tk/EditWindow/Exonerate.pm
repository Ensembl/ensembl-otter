
### EditWindow::Exonerate

package EditWindow::Exonerate;

use strict;
use warnings;
use Carp;

use Hum::Pfetch;
use Hum::FastaFileIO;
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
	my $top  = $self->top;

	### Query frame
	my $query_frame = $top->LabFrame(
									  -borderwidth => 3,
									  -label       => 'Query sequences',
									  -labelside   => 'acrosstop',
	)->pack( -side => 'top', );
	
	## Accession entry box
	my $match_frame =
	  $query_frame->Frame( -border => 3, )->pack( -side => 'top', );
	$match_frame->Label(
						 -text   => 'Accessions:',
						 -anchor => 's',
						 -padx   => 6,
	)->pack( -side => 'left' );
	$self->match(
				$match_frame->Entry( -width => 24, )->pack( -side => 'left' ) );
	## Fasta file entry box
	my $fname;
	my $Horiz      = 1;
	my $file_frame =
	  $query_frame->Frame( -border => 3, )->pack( -side => 'top', );
	$file_frame->Label(
						-text   => 'Fasta file:',
						-anchor => 's',
						-padx   => 6,
	)->pack( -side => 'left' );

	# Pad between entries
	$file_frame->Frame( -width => 10, )->pack( -side => 'top' );
	$self->fasta_file(
		 $file_frame->Entry( -textvariable => \$fname )->pack( -side => 'left' ) );
	$file_frame->Button(
		-text    => 'Browse...',
		-command => sub {
			$fname = $top->getOpenFile(
			    -title          => 'Choose fasta file',
			    -initialdir     => $INITIAL_DIR,
                -filetypes      => [
                    ['Fasta Files'  => [qw{ .seq .pep .fasta .fa }]],
                    ['All Files'    => '*'],

                    ### Do not want to show hidden files.
                    # ['Fasta Files' => sub {
                    #     my ($widget, $file, $dir) = @_;
                    #     # Skip hidden files
                    #     return if $file =~ /^\./;
                    #     return $file =~ /\.(seq|pep|fasta|fa)$/;
                    # } ],
                    # ['All Files' => sub {
                    #     my ($widget, $file, $dir) = @_;
                    #     # Skip hidden files
                    #     return $file !~ /^\./;
                    # } ],
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
	my $txt_frame =
	  $query_frame->Frame( -border => 3, )->pack( -side => 'top', );
	$txt_frame->Label(
					   -text   => 'Fasta sequences',
					   -anchor => 's',
					   -padx   => 6,
	)->pack( -side => 'top' );
	$self->fasta_txt(
		   $txt_frame->Scrolled( "Text",
		   	-background => 'white',
		   	-height => 12,
		   	-font	=> $self->XaceSeqChooser->font_fixed,
		   	 )->pack( -side => 'top', ) );
	
	### Parameters
	my $param_frame = $top->LabFrame(
									  -borderwidth => 3,
									  -label       => 'Parameters',
									  -labelside   => 'acrosstop',
	)->pack( -side => 'top', );
	
	$param_frame->Label(
							 -text   => 'Number of matches to report (0 for all):',
							 -anchor => 's',
							 -padx   => 6,
	)->pack( -side => 'left' );
	$self->bestn(
				  $param_frame->Entry(
										   -width   => 9,
										   -justify => 'right',
					)->pack( -side => 'left' )
	);
	$self->set_entry( 'bestn', $BEST_N );
	
	### Commands
	my $button_frame = $top->Frame->pack(    -side => 'top',
										  -fill => 'x', );
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

	# Update coords
	my $update = sub {
		$self->update_from_clipboard;
	};
	$button_frame->Button(
						   -text      => 'Update',
						   -underline => 0,
						   -command   => $update,
	)->pack( -side => 'left' );
	$top->bind( '<Control-u>', $update );
	$top->bind( '<Control-U>', $update );

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
}

sub update_from_XaceSeqChooser {
	my ( $self ) = @_;
	$self->update_from_clipboard;
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
	$txt =~ s/\s//g;
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
}

my $seq_tag = 1;

sub get_query_seq {
	my ($self) = @_;
	my @seq;
	
	if ( $self->get_entry('match') ) {
		my @accessions = split /\,|\;/, $self->get_entry('match');
		if (@accessions) {
			push @seq, Hum::Pfetch::get_Sequences(@accessions);
		}
	}
	if ( my $string = $self->fasta_txt->get( '1.0', 'end' ) ) {
		if( $string =~ /\S/ && !($string =~ />/)) {
			print "creating new seq tag num: $seq_tag\n";
			$string = ">Unknown_$seq_tag\n".$string; $seq_tag++;
		}
		push @seq, Hum::FastaFileIO->new_String_IO($string)->read_all_sequences;
	}
	if ( $self->get_entry('fasta_file') ) {
		push @seq, Hum::FastaFileIO->new( $self->get_entry('fasta_file') )
		  	->read_all_sequences;
	}
	
	return \@seq;
}

sub name_start_end_from_fMap_blue_box {
	my ($self) = @_;
	my $tk = $self->top;
	my $text = $self->get_clipboard_text or return;

	#warn "clipboard: $text";
	# Match fMap "blue box"
	if ( $text =~
/^(?:<?(?:Protein|Sequence)[:>]?)?\"?([^\"\s]+)\"?\s+-?(\d+)\s+-?(\d+)\s+\(\d+\)/
	  )
	{
		my $name  = $1;
		my $start = $2;
		my $end   = $3;
		( $start, $end ) = ( $end, $start ) if $start > $end;

		#warn "Got ($name, $start, $end)";
		return ( $name, $start, $end );
	}
	else {
		return;
	}
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

