package Bio::Vega::RangeLockBroker;

use strict;
use warnings;

use Try::Tiny;

# Answer initially will be mostly "no"
sub supported {
    my ($called, $dataset) = @_;

    my $db_thing = $dataset->isa('DBI::db') ? $dataset
      : ($dataset->can('get_cached_DBAdaptor')
         ? $dataset->get_cached_DBAdaptor->dbc # B:O:Lace:D
         : $dataset->otter_dba->dbc # B:O:SpeciesDat:D
        );

    return try {
        local $SIG{__WARN__} = sub {
            my ($msg) = @_;
            warn $msg unless $msg =~ /execute failed:/;
            return;
        };
        my $sth = $db_thing->prepare(q{ SELECT * FROM slice_lock LIMIT 1 });
        my $rv = $sth->execute();
        return 0 unless defined $rv; # when RaiseError=0
        my @junk = $sth->fetchrow_array;
        1;
    } catch {
        if (m{(?:^|: )Table '[^']+' doesn't exist($| )}) {
            0;
        } else {
            throw("Unexpected error in supported check: $_");
        }
    };
}


=for sql

create table slice_lock (
 slice_lock_id  int unsigned not null auto_increment,
 lock_cookie    varchar(64),
 seq_region_id  int unsigned not null,
 author_id      int not null,
 hostname       varchar(100) not null,
 timestamp      datetime not null,

 primary key (slice_lock_id),
 unique key lock_cookie (lock_cookie)
) ENGINE=InnoDB;

=cut

1;
