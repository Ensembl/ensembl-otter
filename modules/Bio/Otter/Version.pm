package Bio::Otter::Version;

use strict;
use warnings;

use Exporter ;

our $SCHEMA_VERSION = 0.01;
our $XML_VERSION    = 0.01;
our @ISA       = qw(Exporter);
our @EXPORT    = qw($SCHEMA_VERSION
                    $XML_VERSION);
our @EXPORT_OK = qw();
our @EXPORT_TAGS = (all => [qw($SCHEMA_VERSION
                               $XML_VERSION)]
                    );


1;
