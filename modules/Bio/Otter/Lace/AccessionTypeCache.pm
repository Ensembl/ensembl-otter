
### Bio::Otter::Lace::AccessionTypeCache

package Bio::Otter::Lace::AccessionTypeCache;

use strict;
use warnings;
use Hum::ClipboardUtils qw{ $magic_evi_name_matcher };

my (%client, %full_accession, %type, %DB);

sub DESTROY {
    my ($self) = @_;

    warn "Destroying a ", ref($self), "\n";

    delete $client{$self};
    delete $full_accession{$self};
    delete $type{$self};
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
    
    my @to_fetch = grep { ! $full_accession{$self}{$_} } @$name_list;
    return unless @to_fetch;
    my $response = $self->Client->get_accession_types(@to_fetch);
    foreach my $line (split /\n/, $response) {
        my ($acc, $type, $full_acc) = split /\t/, $line;
        $full_accession{$self}{$acc} = $full_acc;
        $type{$self}{$full_acc} = $type;
    }

    return;
}

sub type_and_name_from_accession {
    my ($self, $acc) = @_;
    
    if (my $full_acc = $full_accession{$self}{$acc}) {
        my $type = $type{$self}{$full_acc};
        return ($type, $full_acc);
    }
    else {
        return;
    }
}

sub full_accession {
    my ($self, $acc) = @_;
    
    return $full_accession{$self}{$acc};
}

sub type {
    my ($self, $full_acc) = @_;
    
    return $type{$self}{$full_acc};
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
    my $full_fetch = $dbh->prepare(q{ SELECT evi_type, accession_sv, source_db FROM accession_info WHERE accession_sv = ? });
    my $part_fetch = $dbh->prepare(q{ SELECT evi_type, accession_sv, source_db FROM accession_info WHERE accession_sv LIKE ? });

    my $type_name = {};
    my $not_found = [];

    # First look at our SQLite db, to find out what kind of accession it is
    foreach my $acc (@$acc_list) {
        $full_fetch->execute($acc);
        my ($type, $full_name, $source_db) = $full_fetch->fetchrow;
        unless ($type) {
            # Try a different query, assuming the SV was missed off
            $part_fetch->execute("$acc.%");
            ($type, $full_name, $source_db) = $part_fetch->fetchrow;
        }
        unless ($type and $full_name) {
            push(@$not_found, $acc);
            next;
        }
        if ($source_db) {
            my $prefix = ucfirst lc substr($source_db, 0, 2);
            $full_name = "$prefix:$full_name";
        }
        my $name_list = $type_name->{$type} ||= [];
        push(@$name_list, $full_name);
    }
    
    # Fall back to a server query for stuff not found in the SQLite db.
    if (@$not_found) {
        $self->populate($not_found);
        foreach my $acc (@$not_found) {
            my ($type, $full_name) = $self->type_and_name_from_accession($acc);
            unless ($type and $full_name) {
                next;
            }
            my $name_list = $type_name->{$type} ||= [];
            push(@$name_list, $full_name);        
        }
    }
    
    return $type_name;
}


1;

__END__

=head1 NAME - Bio::Otter::Lace::AccessionTypeCache

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

