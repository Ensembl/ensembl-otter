=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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


### Tk::NoPasteEntry

package Tk::NoPasteEntry;

use strict;
use base qw{ Tk::Derived Tk::Entry };

our $VERSION = 1.0;

Construct Tk::Widget 'NoPasteEntry';

sub ClassInit {
    my ($class, $mw) = @_;
 
    $class->SUPER::ClassInit($mw);
    
    # Remove all the paste bindings
    foreach my $sequence (qw{ <<Paste>> <<PasteSelection>>
                              <Button-2> <ButtonRelease-2> <B2-Motion> }) {
        $mw->bind($class, $sequence, '');
    }
    
    $mw->bind($class, '<Up>',   'increment_int');
    $mw->bind($class, '<Down>', 'decrement_int');
}

my $simple_float = qr{-?\d+(\.\d*)?};

sub increment_int {
    my ($w) = @_;
    
    my $txt = $w->get;
    if ($txt =~ /^$simple_float$/) {
        $txt++;
        $w->set($txt);
    }
}

sub decrement_int {
    my ($w) = @_;
    
    my $txt = $w->get;
    if ($txt =~ /^$simple_float$/) {
        $txt--;
        $w->set($txt);
    }
}

sub set {
    my ($w, $txt) = @_;
    
    $w->delete(0, 'end');
    $w->insert(0, $txt);
}

1;

__END__

=head1 NAME - Tk::NoPasteEntry

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

