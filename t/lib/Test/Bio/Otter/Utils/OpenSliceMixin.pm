package Test::Bio::Otter::Utils::OpenSliceMixin;

use Test::Class::Most
    parent     => 'OtterTest::Class';

sub build_attributes { return; } # none

sub setup       { return; }  # don't let OtterTest::Class do its OO stuff
sub constructor { return; }  # --"--

1;
