
### Bio::Otter::SQL::StatementSet

package Bio::Otter::SQL::StatementSet;

use strict;
use Bio::Otter::SQL::Statement;

sub new {
    return bless [], shift;
}

sub add_Statement {
    my $self = shift;
    
    push(@$self, shift);
}

sub Statement_list {
    my $self = shift;
    
    return @$self;
}

sub string {
    my $self = shift;
    
    my $str = '';
    foreach my $statement ($self->Statement_list) {
        $str .= $statement->string;
    }
    return $str;
}

sub make_transactional {
    my $self = shift;
    
    foreach my $st ($self->Statement_list) {
        next unless $st->isa('Bio::Otter::SQL::Statement::CreateTable');
        $st->make_transactional;
    }
}

1;

__END__

=head1 NAME - Bio::Otter::SQL::StatementSet

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

