
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
use Tk::Checkbutton;
use Data::Dumper;

use base 'EditWindow';

my $PROT_SCORE = 100;
my $DNA_SCORE  = 100;
my $DNAHSP     = 120;
my $BEST_N	   = 1;
my $MAX_INTRON_LENGTH = 200000;

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
	$self->match( $match_frame->Entry->pack( -side => 'left', -expand => 1, -fill => 'x' ) );
	$match_frame->Frame( -width => 6, )->pack( -side => 'left' );

	my $update = sub {
		$self->accessions_from_clipboard;
	};
	$match_frame->Button(
        -text      => 'Fetch from clipboard',
        -underline => 0,
        -command   => $update,
	)->pack( -side => 'left' );
	$match_frame->Button(
        -text      => 'Clear',
        -underline => 0,
        -command   => sub {$self->set_entry('match', '');},
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

	$self->fasta_file( $file_frame->Entry( -textvariable => \$fname )->pack( -side => 'left', -expand => 1, -fill => 'x' ) );

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
			# Show the end of the Entry, so that when the file path is long the
			# user can see the name of the file which was chosen.
			$self->fasta_file->xviewMoveto(1);
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
            # -background => 'white',
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

    my $option_frame = $param_frame->Frame->pack(-side => 'right', -fill => 'x');

    my $bestn_frame = $option_frame->Frame->pack(@frame_pack);

    $self->bestn(
        $bestn_frame->Entry(
            -width   => 9,
            -justify => 'right',
        )->pack( -side => 'right' )
    );
	
	$self->set_entry( 'bestn', $BEST_N );
	
	$bestn_frame->Label(
        -text   => 'Number of transcript alignments to report (0 for all):',
        -anchor => 'e',
        -padx   => 6,
	)->pack( -side => 'right', -fill => 'x' );
	
	my $intron_length_frame = $option_frame->Frame->pack(-side => 'bottom', -fill => 'x');
	
	$self->max_intron_length(
	    $intron_length_frame->Entry(
	       -width      => 9,
	       -justify    => 'right',
	    )->pack( -side => 'right' )
	);

    $self->set_entry( 'max_intron_length', $MAX_INTRON_LENGTH );
    
    $intron_length_frame->Label(
        -text   => 'Maximum intron length:',
        -anchor => 'e',
        -padx   => 6,
    )->pack( -side => 'right', -fill => 'x' );

	my $cb_frame = $param_frame->Frame->pack(-side => 'left', -fill => 'x');

	$cb_frame->Checkbutton(
    	-variable => \$self->{_clear_existing},
        -text => 'Clear existing alignments of same type',
        -anchor => 'w',
     )->pack( -side => 'top', -expand => 1, -fill => 'x' );

     $self->{_use_marked_region} = 1;

     $cb_frame->Checkbutton(
    	-variable => \$self->{_use_marked_region},
        -text => 'Only search within marked region',
        -anchor => 'w',
     )->pack( -side => 'top', -expand => 1, -fill => 'x' );

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

    # Add clipboard text to existing entry text so that annotator
    # can easily build up a list of accessions to search
    if (my $entry_txt = $self->get_entry('match')) {
        $text = join(' ', $entry_txt, $text);
    }

    # accessions_from_text extracts all the accessions from its
    # text argument and removes duplicates from the list
    if (my @acc = accessions_from_text($text)) {
        $self->set_entry('match', join ' ', @acc);
        # Show the end of the Entry so that the annotator sees
        # the latest accessions added.
        $self->match->xviewMoveto(1);
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

sub max_intron_length {
    my ( $self, $max_intron_length ) = @_;
    if ($max_intron_length) {
        $self->{'_max_intron_length'} = $max_intron_length;
    }
    return $self->{'_max_intron_length'};
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

	my $seqs;

	$seqs = $self->get_query_seq();

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

	my %seqs_by_type = ();

	for my $seq (@$seqs) {

		if ($seq->type &&
			($seq->type eq 'EST'   ||
			 $seq->type eq 'ncRNA' ||
			 $seq->type eq 'mRNA'  ||
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

	# get marked region (if requested)

	my ($genomic_start, $genomic_end) = (1, $self->XaceSeqChooser->Assembly->Sequence->sequence_length);

	if ($self->{_use_marked_region}) {
		my ($mark_start, $mark_end) = $self->XaceSeqChooser->zMapGetMark;
		if ($mark_start && $mark_end) {
			warn "Setting exonerate genomic start & end to marked region: $mark_start - $mark_end";
			($genomic_start, $genomic_end) = ($mark_start, $mark_end);
		}
	}

	$self->top->Busy;

	my $need_relaunch = 0;
	
	my $method_name;

	for my $type (keys %seqs_by_type) {

		print STDOUT "Running exonerate for sequence(s) of type: $type\n";

		my $score    = $type =~ /Protein/ ? $PROT_SCORE : $DNA_SCORE;
		my $ana_name = $type =~ /^Unknown/ ? $type : "OTF_$type";
		my $dnahsp   = $DNAHSP;
		my $best_n   = $self->get_entry('bestn');
		my $max_intron_length = $self->get_entry('max_intron_length');

		my $exonerate = Bio::Otter::Lace::Exonerate->new;
		$exonerate->AceDatabase($self->XaceSeqChooser->AceDatabase);
		$exonerate->genomic_seq($self->XaceSeqChooser->Assembly->Sequence);
		$exonerate->genomic_start($genomic_start);
		$exonerate->genomic_end($genomic_end);
		$exonerate->query_seq($seqs_by_type{$type});
		$exonerate->sequence_fetcher($self->{'_name_seq'});
		$exonerate->acedb_homol_tag($ana_name.'_homol');
		$exonerate->query_type($type =~ /Protein/ ? 'protein' : 'dna');
		$exonerate->score($score);
		$exonerate->dnahsp($dnahsp);
		$exonerate->bestn($best_n);
		$exonerate->max_intron_length($max_intron_length);
		$exonerate->method_tag($ana_name);
		$exonerate->logic_name($ana_name);

		my $seq_file = $exonerate->write_seq_file();

		if ($seq_file) {
			$exonerate->initialise($seq_file);
			my $ace_text = $exonerate->run;
			# delete query file
			unlink $seq_file;

			next unless $ace_text;

	        # add hit sequences into ace text
	        my $names = $exonerate->delete_all_hit_names;
	        foreach my $hit_name (@$names) {
	            my $seq = $self->{'_name_seq'}->{$hit_name};
	            if($exonerate->query_type eq 'protein') {
	            	$ace_text .= $self->ace_PEPTIDE($hit_name, $seq);
	            } else {
	            	$ace_text .= $self->ace_DNA($hit_name, $seq);
	        	}
	    	}

			if ($self->{_clear_existing}) {

				my $delete_cmd = "Sequence : \"".$exonerate->genomic_seq->name."\"\n".
							     "-D Homol ".$exonerate->acedb_homol_tag."\n";

				$ace_text = $delete_cmd.$ace_text;
			}

			#print "ACE text:\n\n$ace_text\n\n";

			$need_relaunch = 1;

			# Need to add new method to collection if we don't have it already
	    	my $coll = $exonerate->AceDatabase->MethodCollection;
	    	my $coll_zmap = $self->XaceSeqChooser->Assembly->MethodCollection;
	    	my $method = $exonerate->ace_Method;
	    	$method_name = $method->name;	
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
	    
	    if ($self->{_clear_existing}) {
	        warn "Deleting featureset $method_name...";
	        $self->XaceSeqChooser->zMapDeleteFeaturesets($method_name);
	    }
	    
	    if ($self->{_use_marked_region}) {
	        # XXX: temporarily don't ask zmap to load in the marked region as this crashes
	        # zmap when the view is reverse complemented
            #$self->XaceSeqChooser->zMapLoadFeaturesInMark($method_name);
            $self->XaceSeqChooser->zMapLoadFeatures($method_name);
	    }
	    else {
	        $self->XaceSeqChooser->zMapLoadFeatures($method_name);
	    }
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
	my @seqs;

	# get seqs from fasta file and text box

	if ( my $string = $self->fasta_txt->get( '1.0', 'end' ) ) {
		if ($string =~ /\S/ and $string !~ />/) {
			print "creating new seq tag num: $seq_tag\n";
			$string = ">OTF_seq_$seq_tag\n" . $string;
			$seq_tag++;
		}
		push @seqs, Hum::FastaFileIO->new_String_IO($string)->read_all_sequences;
	}
	if ( $self->get_entry('fasta_file') ) {
		push @seqs, Hum::FastaFileIO->new( $self->get_entry('fasta_file') )
		  	->read_all_sequences;
	}

	my @accessions = map { $_->name } @seqs;

	# get seqs from accession numbers supplied by the user

	my @supplied_accs;

	if (my $txt = $self->get_entry('match')) {
		@supplied_accs = split(/[,;\|\s]+/, $txt);
		push @accessions, @supplied_accs;
	}

	# identify the types of all the accessions supplied

    my $client = $self->XaceSeqChooser->AceDatabase->Client;

    my $types = $client->get_accession_types(@accessions);

	# add type and full accession information to the existing sequences

	for my $seq (@seqs) {
		if ($types->{$seq->name}) {
			my ($type, $full_acc) = @{ $types->{$seq->name} };
			$seq->type($type);
			$seq->name($full_acc);
		}
	}

	# map between the corrected and supplied accessions

	my %correct_to_supplied = ();

	map { $correct_to_supplied{ $types->{$_}->[1] || $_ } = $_ } @supplied_accs;

	# build a list of all the correct accessions for pfetch

	my @correct_accs = map { $types->{$_}->[1] || $_ } @supplied_accs;

	my $remapped_msg = '';

	my %seq_fetched = map { $_ => 0 } @correct_accs;

	if (@correct_accs) {

		# and pfetch the remaining sequences using the corrected accessions

		for my $seq (Hum::Pfetch::get_Sequences(@correct_accs)) {

			# add the type information to the sequence

			$seq->type($types->{ $correct_to_supplied{$seq->name} }->[0]);
			push @seqs, $seq;

			# flag to the user that we changed the accession if necessary

			unless ($seq->name =~ $correct_to_supplied{$seq->name}) {
				$remapped_msg .= "  ".$correct_to_supplied{$seq->name}.
								 " to ".$seq->name."\n";
			}

			# and flag that we have found a sequence for this accession

			$seq_fetched{$seq->name} = 1;
		}
	}

	# build a list of accessions we didn't find anything for

	my $missing_msg = '';

	map { $missing_msg .= "\t$_\n" unless $seq_fetched{$_} } @correct_accs;

	$missing_msg = "I did not find any sequences for the following accessions:\n\n" . $missing_msg
		if $missing_msg;

	# tell the user about any missing sequences or remapped accessions

	if ($missing_msg || $remapped_msg) {

		$remapped_msg = "The following supplied accessions have been ".
						"mapped to more recent accessions\n\n".$remapped_msg
							if $remapped_msg;

		$missing_msg .= "\n" if ($missing_msg && $remapped_msg);

		$self->top->messageBox(
	        -title      => 'Problems with accessions supplied',
	        -icon       => 'warning',
	        -message    => $missing_msg.$remapped_msg,
	        -type       => 'OK',
		);
	}


	# lower case query polyA/T tails to avoid spurious exons

	foreach my $seq (@seqs) {
		my $s = $seq->uppercase;
		$s =~ s/(^T{6,}|A{6,}$)/lc($1)/ge;

		$seq->sequence_string($s);

		# save seq in hash
		$self->{'_name_seq'}->{$seq->name} = $seq;
	}

	return \@seqs;
}

sub ace_DNA {
    my ($self, $name, $seq) = @_;

    my $ace = qq{\nSequence "$name"\n\nDNA "$name"\n};

    my $dna_string = $seq->sequence_string;

    while ($dna_string =~ /(.{1,60})/g) {
        $ace .= $1 . "\n";
    }

    return $ace;
}

sub ace_PEPTIDE {
    my ($self, $name, $seq) = @_;

    my $ace = qq{\nProtein "$name"\n\nPEPTIDE "$name"\n};

    my $prot_string = $seq->sequence_string;
    while ($prot_string =~ /(.{1,60})/g) {
        $ace .= $1 . "\n";
    }
    return $ace;
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

