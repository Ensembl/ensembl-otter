
### Bio::Otter::Lace::AccessionTypeCache

package Bio::Otter::Lace::AccessionTypeCache;

use strict;
use warnings;
use Hum::ClipboardUtils qw{ $magic_evi_name_matcher };

my (%client, %full_accession, %type);

sub DESTROY {
    my ($self) = @_;

    warn "Destroying a ", ref($self), "\n";

    delete $client{$self};
    delete $full_accession{$self};
    delete $type{$self};
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

sub populate {
    my ($self, $name_list) = @_;
    
    my @to_fetch = grep ! $full_accession{$self}{$_}, @$name_list;
    return unless @to_fetch;
    my $response = $self->Client->get_accession_types(@to_fetch);
    foreach my $line (split /\n/, $response) {
        my ($acc, $type, $full_acc) = split /\t/, $line;
        $full_accession{$self}{$acc} = $full_acc;
        $type{$self}{$full_acc} = $type;
    }
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
        $clip_names{"$prefix$acc$sv"} = 1;
    }
    my $acc_list = [keys %clip_names];
    # warn "Got names:\n", map {"  $_\n"} @$acc_list;
    $self->populate($acc_list);

    my $type_name = {};
    foreach my $acc (@$acc_list) {
        my ($type, $full_name) = $self->type_and_name_from_accession($acc);
        my $name_list = $type_name->{$type} ||= [];
        push(@$name_list, $full_name);
    }
    
    return $type_name;
}

{
    ### Should add this to otter_config
    ### or parse it from the Zmap styles
    my %column_type = (
        EST              => 'EST',
        vertebrate_mRNA  => 'cDNA',
        vertebrate_ncRNA => 'ncRNA',
        BLASTX           => 'Protein',
        SwissProt        => 'Protein',
        TrEMBL           => 'Protein',
        OTF_ncRNA        => 'ncRNA',
        OTF_EST          => 'EST',
        OTF_mRNA         => 'cDNA',
        OTF_Protein      => 'Protein',
        Ens_cDNA         => 'cDNA',
    );
    
    # Make hash case insensitive
    foreach my $style (keys %column_type) {
        $column_type{lc $style} = $column_type{$style};
    }
    
    sub cache_type_from_Zmap_XML {
        my ($self, $parsed_xml) = @_;
        
        foreach my $full_acc (keys %$parsed_xml) {
            my $style = $parsed_xml->{$full_acc}{'style'}
                or next;
            my $acc_type = $column_type{$style};
            unless ($acc_type) {
                if ($style =~ /^EST_/i) {
                    $acc_type = 'EST';
                }
                else {
                    next;
                }
            }
            # warn "Caching $full_acc = $acc_type\n";
            $full_accession{$self}{$full_acc} = $full_acc;
            $type{$self}{$full_acc} = $acc_type;
        }
    }
}


1;

__END__

=head1 NAME - Bio::Otter::Lace::AccessionTypeCache

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

