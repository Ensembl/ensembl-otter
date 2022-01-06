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


### Tk::SmartOptionmenu

package Tk::SmartOptionmenu;

use strict;
use Carp;

use base qw(Tk::Derived Tk::Menubutton);

Construct Tk::Widget 'SmartOptionmenu';

sub Populate {
    my ($w, $args) = @_;

    $w->SUPER::Populate($args);
    $args->{-indicatoron} = 1;
    my $menu = $w->menu(-tearoff => 0);

    # Should we allow -menubackground etc. as in -label* of Frame ?

    $w->ConfigSpecs(
        -command  => [ 'CALLBACK', undef, undef, undef ],
        -options  => [ 'METHOD',   undef, undef, undef ],
        -variable => [ 'PASSIVE',  undef, undef, undef ],
        -font => [ [ 'SELF', $menu ], undef, undef, undef ],
        -foreground => [ [ 'SELF', 'CHILDREN' ], undef, undef, undef ],

        -takefocus => [qw/SELF takefocus          Takefocus          1/],
        -highlightthickness =>
          [qw/SELF highlightThickness HighlightThickness 1/],
        -relief => [qw/SELF relief             Relief        raised/],
    );

    # configure -variable and -command now so that when -options
    # is set by main-line configure they are there to be set/called.

    if (my $tvar = delete $args->{-textvariable}) {
        $w->configure(-textvariable => $tvar);
    }
    if (my $vvar = delete $args->{-variable}) {
        $w->configure(-variable => $vvar);
    }
    if (my $command = delete $args->{-command}) {
        $w->configure(-command => $command);
    }
}

sub setOption {
    my ($w, $label, $val) = @_;

    $w->_setValues($label, $val);
    
    # Invoke the callback with the value argument
    $w->Callback(-command => $val);
}

sub _setValues {
    my ($w, $label, $val) = @_;

    if (@_ == 2) {
        $val = $label;
    }
    if (my $tvar = $w->cget(-textvariable)) {
        $$tvar = $label;
    }
    if (my $vvar = $w->cget(-variable)) {
        $$vvar = $val;
    }
}

sub addOptions {
    my $w = shift;

    my $menu  = $w->menu;
    my $width = $w->cget('-width') || 0;

    my $tvar  = $w->cget(-textvariable);
    my $oldt  = $tvar ? $$tvar : undef;
    unless ($tvar) {
        my $new = undef;
        $w->configure(-textvariable => \$new);
    }
    my $vvar  = $w->cget(-variable);
    my $oldv  = $vvar ? $$vvar : undef;
    unless ($vvar) {
        my $new = undef;
        $w->configure(-variable => \$new);
    }

    my ($firstt, $firstv);

    while (@_) {
        my $thing = shift;
        my ($label, $val);
        if (ref $thing) {
            ($label, $val) = @$thing;
        } else {
            $label = $val = $thing;
        }
        
        # Fill in missing $oldv or $oldt with the other value of this pair
        if (defined($oldt) and ! defined($oldv)) {
            $oldv = $val   if $oldt eq $label;
        }
        elsif (! defined($oldt) and defined($oldv)) {
            $oldt = $label if $oldv eq $val;
        }
        
        my $len = length($label);
        $width = $len if $len > $width;
        $menu->command(
            -label   => $label,
            -command => [ $w, 'setOption', $label, $val ]
        );
        unless (defined $firstt) {
            $firstt = $label;
            $firstv = $val;
        }
    }

    if (defined($oldt) and defined($oldv)) {
        $w->_setValues($oldt, $oldv);
    }
    elsif (defined($firstt)) {
        $w->_setValues($firstt, $firstv);
    }

    $w->configure('-width' => $width);
}

sub options {
    my ($w, $opts) = @_;

    if (@_ > 1) {
        $w->menu->delete(0, 'end');
        $w->addOptions(@$opts);
    }
    else {
        return $w->_cget('-options');
    }
}



1;

__END__

=head1 NAME - Tk::SmartOptionmenu

=head1 DESCRIPTION

Code copied from B<Tk::Optionmenu>, but with code
fixes so that you can set everthing in the
constructor.  Any callback registered with
C<-command> is not called during widget
construction.  ie: The callback is only run by
C<setOption()> not C<addOptions()>.

It also preserves the values in C<-textvariable>
or C<-variable>, and, if they are different, will
fill in one give the other. To do this it will use
the values in the first pair passed to C<-options>
which matches. (The textvariable/variable pairs
are not key/values in a hash - they are separate
pairs.)

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

