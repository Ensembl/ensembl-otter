package Bio::Otter::Lace::OnTheFly::Aligner::Genomic;

## Moose provides these, but webpublish doesn't know that!
##
use strict;
use warnings;
##

use namespace::autoclean;
use Moose;

extends 'Bio::Otter::Lace::OnTheFly::Aligner';

augment '_build_default_options'    => sub {
    return {
        '-M'               => 500,
        '--maxintron'      => 200000,
        '--score'          => 100,
        '--softmasktarget' => 'yes',
        '--softmaskquery'  => 'yes',
        '--showalignment'  => 'false',
    };
};

augment '_build_default_qt_options' => sub {
    return {
        dna => {
            '--model'           => 'e2g',
            '--geneseed'        => 300,
            '--dnahspthreshold' => 120,
        },
        protein => {
            '--model' => 'p2g',
        },
    };
};

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
