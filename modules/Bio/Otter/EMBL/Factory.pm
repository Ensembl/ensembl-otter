### Bio::Otter::EMBL::Factory
#
# Copyright 2004 Genome Research Limited (GRL)
#
# Maintained by Mike Croning <mdr@sanger.ac.uk>
#
# You may distribute this file/module under the terms of the perl artistic
# licence
#
# POD documentation main docs before the code. Internal methods are usually
# preceded with a _
#

=head1 NAME
 
EST_DB::DB_Entry::EST
 
=head2 Constructor:

my $factory = Bio::Otter::EMBL::Factory->new;

=cut

package Bio::Otter::EMBL::Factory;


use strict;
use Carp;
use Hum::EMBL;


=head2 new
 
?? 

=cut
	
sub new {
    my( $pkg ) = @_;
     
    return bless {}, $pkg;
}

=head2 organism_lines
 
?? 

=cut

sub organism_lines {

}

=head2 standard_comments
 
?? 

=cut

sub standard_comments {

}

=head2 make_embl
 
?? 

=cut

sub make_embl {
    my ( $self ) = @_;
    
    my $embl = Hum::EMBL->new();
    


}

__END__
 
=head1 NAME - Bio::Otter::EMBL::Factory
 
=head1 AUTHOR
 
Mike Croning B<email> mdr@sanger.ac.uk
 
