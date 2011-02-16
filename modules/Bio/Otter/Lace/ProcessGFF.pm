
### Bio::Otter::Lace::ProcessGFF

package Bio::Otter::Lace::ProcessGFF;

use strict;
use warnings;
use Carp;
use Text::ParseWords qw{ quotewords };


{
    ### Should add this to otter_config
    ### or parse it from the Zmap styles
    my %evidence_type = (
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


    sub store_hit_data_from_gff {
        my ($dbh, $gff_file) = @_;
    
        my $store = $dbh->prepare(q{
            INSERT OR REPLACE INTO accession_info (accession_sv
                  , taxon_id
                  , evi_type
                  , description
                  , source_db)
            VALUES (?,?,?,?,?)
        });
    
        open my $gff_fh, '<', $gff_file or confess "Can't read 'GFF file $gff_file'; $!";
        while (defined(my $line = <$gff_fh>)) {
            next if $line =~ /^\s*#/;
            chomp($line);
            my ($seq_name, $method, $feat_type, $start, $end, $score, $strand, $frame, $group)
                = split(/\t/, $line, 9);
            my (%attrib);
            foreach my $tag_val (quotewords('\s*;\s*', 1, $group)) {
                my ($tag, @values) = quotewords('\s+', 0, $tag_val);
                $attrib{$tag} = "@values";
            }
            next unless $attrib{'Name'};
            $store->execute(
                $attrib{'Name'},
                $attrib{'Taxon_ID'},
                substr($method,0,3) eq 'EST' ? 'EST' : $evidence_type{$method},
                $attrib{'Description'},
                $attrib{'DB_Name'},
                );
        }
        close $gff_fh or confess "Error reading GFF file '$gff_file'; $!";
    }
}
1;

__END__

=head1 NAME - Bio::Otter::Lace::ProcessGFF

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

   