
### Bio::Otter::SQL::Comment

package Bio::Otter::SQL::Comment;

use strict;
use Carp;

sub new {
    my( $pkg, $string ) = @_;
    
    confess "Missing string argument to new()"
        unless defined $string;
    return bless \$string, $pkg;
}

sub string {
    my $self = shift;
    
    return $$self;
}

1;

__END__

=head1 NAME - Bio::Otter::SQL::Comment

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

