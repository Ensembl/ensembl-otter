### CanvasWindow::PfamWindow
package CanvasWindow::PfamWindow;
use strict;
use Carp;
use Bio::Otter::Lace::Pfam;
use Tk::ProgressBar;
use base 'CanvasWindow';
my $POLL_ATTEMPTS = 30;

sub new {
	my ( $pkg, @args ) = @_;
	my $self         = $pkg->SUPER::new(@args);
	my $canvas       = $self->canvas;
	my $quit_command = sub {
		$self->canvas->toplevel->withdraw;
	};
	$canvas->Tk::bind( '<Control-q>', $quit_command );
	$canvas->Tk::bind( '<Control-Q>', $quit_command );
	$canvas->toplevel->protocol( 'WM_DELETE_WINDOW', $quit_command );
	my $top = $canvas->toplevel;
	$canvas->configure(    -background         => 'grey',
						-highlightthickness => 0 );
	$top->ProgressBar(
					   -width       => 20,
					   -from        => 0,
					   -to          => 100,
					   -blocks      => 100,
					   -gap         => 0,
					   -troughcolor => 'white',
					   -colors      => [ 0, 'IndianRed3' ],
					   -variable    => \$self->{_progress}
	)->pack( -fill => 'x' );
	$top->Label(
				 -width        => 45,
				 -height       => 1,
				 -textvariable => \$self->{_status}
	)->pack( -side => 'top', -fill => 'x' );
	my $button_frame = $top->Frame->pack( -side => 'top', -fill => 'x' );
	my $open = $button_frame->Button(
		-text    => 'open Pfam page',
		-command => sub {
			$self->open_url();
		},
	)->pack( -side => 'left' );
	$self->open_button($open);
	my $quit = $button_frame->Button(
									  -text    => 'Close',
									  -command => $quit_command,
	)->pack( -side => 'right' );
	return $self;
}

sub progress {
	my ( $self, $p ) = @_;
	if ($p) {
		$self->{_progress} = $p;
	}
	return $self->{_progress};
}

sub pfam {
	my ( $self, $pfam ) = @_;
	$self->{_pfam} = $pfam if $pfam;
	return $self->{_pfam};
}

sub query {
	my ( $self, $s ) = @_;
	if ($s) {
		$self->{_seq} = $s;
	}
	return $self->{_seq};
}

sub name {
	my ( $self, $n ) = @_;
	if ($n) {
		$self->{_name} = $n;
	}
	return $self->{_name};
}

sub status {
	my ( $self, $s ) = @_;
	if ($s) {
		$self->{_status} = $s;
	}
	return $self->{_status};
}

sub open_button {
	my ( $self, $ob ) = @_;
	if ($ob) {
		$self->{_obutton} = $ob;
	}
	return $self->{_obutton};
}

sub initialize {
	my ($self) = @_;
	my $pfam = Bio::Otter::Lace::Pfam->new();
	$self->pfam($pfam);
	$self->open_button->configure( -state => 'disabled' );
	my $xml = $pfam->submit_search( $self->query );
	my ( $result_url, $estimated_time ) = $pfam->check_submission($xml);
	$self->status("searching pfam (wait the estimated running time)");
	my $wait = $estimated_time * 1000 / 70;

	for ( my $block = 1 ; $block <= 70 ; $block++ ) {
		$self->progress($block);
		$self->canvas->toplevel->update;
		$self->canvas->toplevel->after($wait);
	}
	my $tries = 1;
	$wait = 0;
	my $res;
	until ( $tries >= $POLL_ATTEMPTS ) {
		$self->status("searching pfam (querying server)");
		$self->progress( 70 + $tries );
		$res = $pfam->poll_results($result_url);
		if ($res) {
			$self->fill_progressBar();
			last;
		}
		$self->canvas->toplevel->update;
		$wait += $tries;
		$tries++;
		sleep $wait;
	}
	if ($res) {
		$self->status("data ready");
		$self->canvas->toplevel->update;
		$self->open_url();
		$self->canvas->toplevel->withdraw;
	}
	else {
		$self->status("open pfam manually");
		$self->canvas->toplevel->update;
	}
	$self->open_button->configure( -state => 'normal' );
}

sub fill_progressBar {
	my ($self) = @_;
	for ( my $percent = $self->progress ; $percent <= 100 ; $percent++ ) {
		$self->progress($percent);
		$self->canvas->toplevel->update;
		$self->canvas->toplevel->after(20);
	}
}

sub open_url {
	my ($self) = @_;
	my $url = $self->pfam->result_url;
	$url =~ s/output=xml&//;
	if ( $^O eq 'darwin' ) {
		system("open '$url'");
	}
	else {
		print STDOUT "Pfam search result for " . $self->name . "\n$url\n";
		system(qq{firefox -remote "openFile($url,new-tab)"});
	}
}

sub DESTROY {
	my ($self) = @_;
	$self = undef;    # $self gets nicely DESTROY'd with this
}
1;
__END__

=head1 NAME - CanvasWindow::PfamWindow

=head1 AUTHOR

anacode B<email> anacode@sanger.ac.uk

