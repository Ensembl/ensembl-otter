
### Bio::Otter::SQL::Clause

package Bio::Otter::SQL::Clause;

use strict;
use Bio::Otter::SQL::Clause::ColumnDefinition;
use Bio::Otter::SQL::Clause::KeyDefinition;

sub new {
    return bless {}, shift;
}


1;

__END__

=head1 NAME - Bio::Otter::SQL::Clause

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

