
### Bio::Otter::SQL::Statement

package Bio::Otter::SQL::Statement;

use strict;
use Bio::Otter::SQL::Clause;
use Bio::Otter::SQL::Qualifier;

sub new {
    return bless {}, shift;
}


sub comment_string {
    my( $self, $comment_string ) = @_;
    
    if ($comment_string) {
        $self->{'_comment_string'} = $comment_string;
    }
    return $self->{'_comment_string'} || '';
}

sub append_comment {
    my( $self, $comment ) = @_;
    
    $self->{'_comment_string'} .= $comment;
}

1;

__END__

=head1 NAME - Bio::Otter::SQL::Statement

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

