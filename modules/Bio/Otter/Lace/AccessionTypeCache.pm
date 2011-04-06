
### Bio::Otter::Lace::AccessionTypeCache

package Bio::Otter::Lace::AccessionTypeCache;

use strict;
use warnings;
use Hum::ClipboardUtils qw{ $magic_evi_name_matcher };

my (%client, %DB);

sub DESTROY {
    my ($self) = @_;

    warn "Destroying a ", ref($self), "\n";

    delete $client{$self};
    delete $DB{$self};

    return;
}

sub new {
    my ($pkg) = @_;
    
    my $str;
    return bless \$str, $pkg;
}

sub Client {
    my ($self, $client) = @_;
    
    if ($client) {
        $client{$self} = $client;
    }
    return $client{$self};
}

sub DB {
    my ($self, $DB) = @_;
    
    if ($DB) {
        $DB{$self} = $DB;
    }
    return $DB{$self};
}

sub populate {
    my ($self, $name_list) = @_;
    
    # Will fetch the latest version of any ACCESSION supplied without a SV.
    
    my $dbh = $DB{$self}->dbh;
    my $check_full  = $dbh->prepare(q{ SELECT count(*) FROM accession_info WHERE accession_sv = ? });
    my $check_alias = $dbh->prepare(q{ SELECT count(*) FROM full_accession WHERE name = ? });
    
    my (@to_fetch);
    foreach my $name (@$name_list) {
        # my ($prefix, $acc, $varsplice, $sv) = $name =~ /$magic_evi_name_matcher/;
        $check_full->execute($name);
        my ($have_full) = $check_full->fetchrow;
        if ($have_full) {
            next;
        }
        else {
            $check_alias->execute($name);
            my ($have_alias) = $check_alias->fetchrow;
            if ($have_alias) {
                next;
            }
            else {
                push(@to_fetch, $name);
            }
        }
    }
    return unless @to_fetch;

    # Query the webserver (mole database) for the information.
    my $response = $self->Client->get_accession_types(@to_fetch);

    my $save_acc_info = $dbh->prepare(q{
        INSERT INTO accession_info (
              accession_sv
              , taxon_id
              , evi_type
              , description
              , source_db
              , length)
        VALUES (?,?,?,?,?,?)
    });
    my $save_alias = $dbh->prepare(q{
        INSERT INTO full_accession(name, accession_sv) VALUES (?,?)
    });
    
    $dbh->begin_work;
    eval {
        foreach my $line (split /\n/, $response) {
            my ($name, $evi_type, $acc_sv, $source_db, $seq_length, $taxon_list, $description) = split /\t/, $line;
            my ($tax_id, @other_tax) = split /,/, $taxon_list; # /; # emacs highlighting workaround
            if (@other_tax) {
                # Some SwissProt entries contain the same protein and multiple species.
                warn "Discarding taxon info from '$taxon_list' for '$acc_sv'; keeping only '$tax_id'";
            }
            # Don't overwrite existing info
            $check_full->execute($acc_sv);
            my ($have_full) = $check_full->fetchrow;
            unless ($have_full) {
                # It is new, so save it
                $save_acc_info->execute($acc_sv, $tax_id, $evi_type, $description, $source_db, $seq_length);
            }
            if ($name ne $acc_sv) {
                $save_alias->execute($name, $acc_sv);
            }
        }
    };
    if (my $err = $@) {
        $dbh->rollback;
        die "Error saving accession info: $@";
    }
    else {
        $dbh->commit;
    }

    return;
}

sub type_and_name_from_accession {
    my ($self, $acc) = @_;
    
    my $dbh = $DB{$self}->dbh;
    my $sth = $dbh->prepare(q{
        SELECT evi_type
          , accession_sv
        FROM accession_info
        WHERE accession_sv = ?
        });
    $sth->execute($acc);
    my ($type, $acc_sv) = $sth->fetchrow;
    unless ($type and $acc_sv) {
        $sth = $dbh->prepare(q{
            SELECT ai.evi_type, ai.accession_sv
            FROM accession_info ai
              , full_accession f
            WHERE ai.accession_sv = f.accession_sv
            AND f.name = ?
            });
        $sth->execute($acc);
        ($type, $acc_sv) = $sth->fetchrow;
    }
    if ($type and $acc_sv) {
        return ($type, $acc_sv);
    }
    else {
        return;
    }
}

sub evidence_type_and_name_from_text {
    my ($self, $text) = @_;

    # warn "Trying to parse: [$text]\n";

    my %clip_names;
    while ($text =~ /$magic_evi_name_matcher/g) {
        my $prefix = $1 || '';
        my $acc    = $2;
        $acc      .= $3 if $3;
        my $sv     = $4 || '';
        # $clip_names{"$prefix$acc$sv"} = 1;
        $clip_names{"$acc$sv"} = 1;
    }
    my $acc_list = [keys %clip_names];
    # warn "Got names:\n", map {"  $_\n"} @$acc_list;

    my $dbh = $DB{$self}->dbh;
    my $full_fetch = $dbh->prepare(q{
        SELECT evi_type
          , accession_sv
          , source_db
        FROM accession_info
        WHERE accession_sv = ?
        });
    my $alias_fetch = $dbh->prepare(q{
        SELECT ai.evi_type
          , ai.accession_sv
          , ai.source_db
        FROM accession_info ai
          , full_accession f
        WHERE ai.accession_sv = f.accession_sv
          AND f.name = ?
        });
    my $part_fetch = $dbh->prepare(q{
        SELECT evi_type
          , accession_sv
          , source_db
        FROM accession_info
        WHERE accession_sv LIKE ?
        });

    # First look at our SQLite db, to find out what kind of accession it is
    my $type_name = {};
    foreach my $acc (@$acc_list) {
        $full_fetch->execute($acc);
        my ($type, $full_name, $source_db) = $full_fetch->fetchrow;
        unless ($type) {
            # If the SV was left off, try the full_accession table first to
            # ensure that the most recent version is returned, if cached.
            $alias_fetch->execute($acc);
            ($type, $full_name, $source_db) = $alias_fetch->fetchrow;
        }
        unless ($type) {
            # Last, try a LIKE query, assuming the SV was missed off
            $part_fetch->execute("$acc.%");
            ($type, $full_name, $source_db) = $part_fetch->fetchrow;
        }
        unless ($type and $full_name) {
            next;
        }
        if ($source_db) {
            my $prefix = ucfirst lc substr($source_db, 0, 2);
            $full_name = "$prefix:$full_name";
        }
        my $name_list = $type_name->{$type} ||= [];
        push(@$name_list, $full_name);
    }
    
    return $type_name;
}


1;

__END__

=head1 NAME - Bio::Otter::Lace::AccessionTypeCache

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

