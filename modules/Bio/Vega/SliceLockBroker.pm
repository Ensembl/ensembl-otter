package Bio::Vega::SliceLockBroker;

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

-- adaptor like a feature?  a simple_feature or a new thing?

create table slice_lock (
 -- feature-like aspect
 slice_lock_id    int unsigned not null auto_increment,
 seq_region_id    int unsigned not null,
 seq_region_start int unsigned not null,
 seq_region_end   int unsigned not null,
 author_id        int not null,      -- whose it is

 ts_begin         datetime not null, -- when row is INSERTed
 ts_activity      datetime not null, -- when the owner last touched it

 -- Transitions allowed: INSERT -> pre -> free(too_late),
 --   pre -> held -> free(finished | expired | interrupted)
 active           enum('pre', 'held', 'free') not null,
 freed            enum('too_late', 'finished', 'expired', 'interrupted'),
 freed_author_id  int,               -- who ( did / will ) free it

 -- FYI fields
 intent		  varchar(32) not null, -- human readable, some conventions or defaults?
 hostname         varchar(100) not null, -- machine readable
 ts_free          datetime,          -- when freed was set

 primary key            (slice_lock_id),
 key seq_region_idx     (seq_region_id, seq_region_start),
 key active_author_idx  (active, author_id)
) ENGINE=InnoDB;

=cut

1;
