package HeadedCanvas;

# a double-headed canvas with scrolls
#
# 24.Feb'2005, lg4

use strict;
use Tk;

use base ('Tk::Frame');

Construct Tk::Widget 'HeadedCanvas';

sub Populate {
	my ($self,$args) = @_;

	$self->SUPER::Populate($args);
	
		# creation and packing of auxiliary frames:
	my $botframe = $self->Frame()->pack(-side=>'bottom',-fill=>'x');
	my $lframe = $self->Frame()->pack(-side=>'left',-fill=>'y');
	my $cframe = $self->Frame()->pack(-side=>'left',-fill=>'both',-expand=>1);

		# creation and packing of subwidgets:
	my $sh = $botframe->Scrollbar(-orient=>'horizontal');
	my $sqsize = $sh->reqheight();
	my $minisq = $botframe->Frame(-width=>$sqsize,-height=>$sqsize)
			->pack(-in=>$botframe,-side=>'right');
	$sh->pack(-side=>'left',-fill=>'x',-expand=>1);

	my $sv = $self->Scrollbar(-orient=>'vertical')
		 ->pack(-side=>'right',-fill=>'y');

	my $topleft_canvas = $lframe->Canvas(-width =>0,-height=>0)->pack(-side=>'top');
	my $left_canvas  = $lframe->Canvas(-width =>0)->pack(-side=>'left',-fill=>'y',-expand=>1);
	my $top_canvas  = $cframe->Canvas(-height=>0)->pack(-side=>'top',-fill=>'x');
	my $main_canvas = $cframe->Canvas(
	)->pack(-side=>'bottom',-fill=>'both',-expand=>1);

		# scrolls' binding:
	$sh->configure( -command => sub {
										if(($_[0] eq 'moveto')&&($_[1]<0)) { # don't let it become negative
											$_[1] = 0;
										}
										foreach my $c ($main_canvas,$top_canvas) {
											$c->xview(@_);
										}
								});
	$top_canvas->configure(-xscrollcommand => sub { $sh->set(@_); });
	$main_canvas->configure(-xscrollcommand => sub { $sh->set(@_); });
	 
	$sv->configure( -command => sub {
										if(($_[0] eq 'moveto')&&($_[1]<0)) { # don't let it become negative
											$_[1] = 0;
										}
										foreach my $c ($main_canvas,$left_canvas) {
											$c->yview(@_);
										}
								});
	$left_canvas->configure(-yscrollcommand => sub { $sv->set(@_); });
	# $left_canvas->configure(-yscrollcommand => [ set => $sv ]);
	$main_canvas->configure(-yscrollcommand => sub { $sv->set(@_); });

		# advertisement:
	$self->Advertise('main_canvas'     => $main_canvas);
	$self->Advertise('left_canvas'     => $left_canvas);
	$self->Advertise('top_canvas'      => $top_canvas);
	$self->Advertise('topleft_canvas'  => $topleft_canvas);
	$self->Advertise('xscrollbar'      => $sh);
	$self->Advertise('yscrollbar'      => $sv);

		# delegate configuration to the main canvas:
	$self->ConfigSpecs(
		-background => [['DESCENDANTS','SELF'],'background','Background','white'],
		-foreground => [['DESCENDANTS','SELF'],'foreground','Foreground','black'],
		-scrollregion => ['METHOD','scrollregion','Scrollregion',[0,0,0,0]],
		'DEFAULT' => [$main_canvas],
	);
		# delegate methods to the main canvas:
	$self->Delegates(
		'DEFAULT' => $main_canvas,
	);
}

# overrriding the existing canvas methods:

sub delete { # override the standard method
	my $self = shift @_;

	$self->Subwidget('main_canvas')->delete(@_);
	$self->Subwidget('left_canvas')->delete(@_);
	$self->Subwidget('top_canvas')->delete(@_);
	$self->Subwidget('topleft_canvas')->delete(@_);
}

sub scrollregion {
	my $self = shift @_;
	if(scalar(@_)) { # configure request
		$self->fit_everything();
	} else { # cget request
		return $self->Subwidget('main_canvas')->cget(-scrollregion);
	}
}

# calls to 'xview()' and 'yview()' should get propagated to the main_canvas

sub xviewMoveto {
	my ($self,$frac) = @_;

	$self->Subwidget('main_canvas')->xviewMoveto($frac);
	$self->Subwidget('top_canvas')->xviewMoveto($frac);
}

sub yviewMoveto {
	my ($self,$frac) = @_;

	$self->Subwidget('main_canvas')->xviewMoveto($frac);
	$self->Subwidget('left_canvas')->xviewMoveto($frac);
}

sub defmin { # not a method
	my ($def,$a,$b) = @_;

	return defined($a)
			? (defined($b)
				? (($a<$b)?$a:$b)
				: $a)
			: (defined($b)
				? $b
				: $def);
}

sub defmax { # not a method
	my ($def,$a,$b) = @_;

	return defined($a)
			? (defined($b)
				? (($a>$b)?$a:$b)
				: $a)
			: (defined($b)
				? $b
				: $def);
}

sub fit_everything {
	my $self = shift @_;

	my ($m_x1,$m_y1,$m_x2,$m_y2) = $self->Subwidget('main_canvas')->bbox('all');
	my ($t_x1,$t_y1,$t_x2,$t_y2) = $self->Subwidget('top_canvas')->bbox('all');
	my ($l_x1,$l_y1,$l_x2,$l_y2) = $self->Subwidget('left_canvas')->bbox('all');
	my ($tl_x1,$tl_y1,$tl_x2,$tl_y2) = $self->Subwidget('topleft_canvas')->bbox('all');

	my $w_x1 = defmin(0,$tl_x1,$l_x1);
	my $w_x2 = defmax(0,$tl_x2,$l_x2);

	my $n_y1 = defmin(0,$tl_y1,$t_y1);
	my $n_y2 = defmax(0,$tl_y2,$t_y2);

	my $e_x1 = defmin(0,$t_x1,$m_x1);
	my $e_x2 = defmax(0,$t_x2,$m_x2);

	my $s_y1 = defmin(0,$l_y1,$m_y1);
	my $s_y2 = defmax(0,$l_y2,$m_y2);

	$self->Subwidget('topleft_canvas')->configure(
		-scrollregion =>[$w_x1,$n_y1,$w_x2,$n_y2],
		-width  => ($w_x2-$w_x1),
		-height => ($n_y2-$n_y1),
	);

	$self->Subwidget('left_canvas')->configure(
		-scrollregion =>[$w_x1,$s_y1,$w_x2,$s_y2],
		-width  => ($w_x2-$w_x1),
	);

	$self->Subwidget('top_canvas')->configure(
		-scrollregion =>[$e_x1,$n_y1,$e_x2,$n_y2],
		-height => ($n_y2-$n_y1),
	);

	$self->Subwidget('main_canvas')->configure(
		-scrollregion =>[$e_x1,$s_y1,$e_x2,$s_y2],
	);

	$self->Subwidget('topleft_canvas')->xviewMoveto(0);
	$self->Subwidget('topleft_canvas')->yviewMoveto(0);
	$self->Subwidget('top_canvas')->xviewMoveto(0);
	$self->Subwidget('top_canvas')->yviewMoveto(0);
	$self->Subwidget('left_canvas')->xviewMoveto(0);
	$self->Subwidget('left_canvas')->yviewMoveto(0);
	$self->Subwidget('main_canvas')->xviewMoveto(0);
	$self->Subwidget('main_canvas')->yviewMoveto(0);
}

sub DESTROY {
	my( $self ) = @_;

	my $class = ref($self);
	warn "Destroying a '$class'";
}

1;

