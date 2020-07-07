=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

# Parameters for a test region on human_test

package OtterTest::TestRegion;

use strict;
use warnings;

use Test::Builder;
use Test::Differences qw( eq_or_diff unified_diff );

use Carp;
use Cwd qw(abs_path);
use File::Basename;
use File::Slurp;
use List::Util qw(min max);
use Readonly;

use Bio::Otter::Server::Support::Local;
use Bio::Vega::Gene;
use Bio::Vega::Transform::XMLToRegion;
use Bio::Vega::Utils::Attribute qw( make_EnsEMBL_Attribute );


# FIXME: duplication with Test::OtterLaceOnTheFly
#
Readonly my $REGION_PATH => abs_path(dirname(__FILE__) . "/../../etc/test_regions");

# NB: order is significant, as older test scripts use ->new(0)
#     as shorthand for first region.
#
Readonly my @TEST_REGIONS => qw(
    human_test:chr6-38:2557766-2647766
    human_test:chr2-38:929903-1379472
    human_test:chr12-38:30351955-34820185
    mouse:chr1-38:3009920-3786391
);

sub new {
    my ($class, $name_or_index) = @_;

    my $self = bless {}, $class;

    my $name = $name_or_index;
    if ($name_or_index =~ /^\d+$/) {
        $name = $TEST_REGIONS[$name_or_index];
    }
    $self->{'base_name'} = $name;

    return $self;
}

sub local_server {
    my ($self) = @_;
    my $local_server = Bio::Otter::Server::Support::Local->new;
    $local_server->authorized_user('anacode');
    $local_server->set_params(%{$self->region_params});
    return $local_server;
}

sub xml_matches {
    my ($self, $xml, $desc) = @_;
    chomp $xml;
    unified_diff(); # set global default
    return eq_or_diff($xml, $self->xml_region, $desc, { context => 10 });
}

sub region_is {
    my ($self, $got, $expected) = @_;
    my $tb = Test::Builder->new;
    $tb->diag("region_is(): NOT YET IMPLEMENTED");
    return;
}

# May have been easier to just user our parser to parse XML, *sigh*
#
sub extra_gene {
    my ($self, $slice) = @_;

    my $expected = $TEST_REGIONS[0];
    croak "extra_gene() only works for '$expected'" unless $self->base_name eq $expected;

    my $bvt_otter = Bio::Vega::Transform::XMLToRegion->new; # just for utility methods

    my $analysis = $bvt_otter->_get_Analysis('Otter');
    my $author   = $bvt_otter->_make_Author('anacode', 'anacode');

    my $gene = Bio::Vega::Gene->new(
        -slice =>       $slice,
        -description => 'TEST COPY of chromosome 6 open reading frame 195 (via B:V:Region)',
        -analysis    => $analysis,
        );
    $gene->source('havana');
    $gene->biotype('protein_coding');
    $gene->status('KNOWN');
    $gene->gene_author($author);

    my @gene_attributes;
    push @gene_attributes, make_EnsEMBL_Attribute('name',    'ANACODE-TEST-GENE-2');
    push @gene_attributes, make_EnsEMBL_Attribute('synonym', 'TEST-GENE-2-SYN-1');
    push @gene_attributes, make_EnsEMBL_Attribute('synonym', 'TEST-GENE-2-SYN-2');
    $gene->add_Attributes(@gene_attributes);

    my $transcript = Bio::Vega::Transcript->new(
        -slice    => $slice,
        -analysis => $analysis,
        );
    $transcript->biotype('protein_coding');
    $transcript->status('KNOWN');
    $transcript->source('havana');
    $transcript->transcript_author($author);

    my @transcript_attributes;
    push @transcript_attributes, make_EnsEMBL_Attribute('name',   'ANACODE-TEST-TRANSCRIPT-2');
    push @transcript_attributes, make_EnsEMBL_Attribute('remark', 'TEST COPY 2 of novel protein (FLJ31934)');
    $transcript->add_Attributes(@transcript_attributes);

    my @exon_specs = (
        { start => 2_622_652, end => 2_622_690, strand => -1 },
        { start => 2_621_692, end => 2_621_879, strand => -1 },
        { start => 2_610_000, end => 2_612_206, strand => -1 },
        );

    my $test_region_params = $self->region_params;
    my $tran_start_pos = 2_611_909 - $test_region_params->{start} + 1;
    my $tran_end_pos   = 2_611_526 - $test_region_params->{start} + 1;

    my @exons;
    my ($start_Exon,$start_Exon_Pos,$end_Exon,$end_Exon_Pos); # FIXME: dup with B:V:Transform::Otter
    foreach my $e_spec (@exon_specs) {
        my $exon = Bio::Vega::Exon->new(
            -start     => ($e_spec->{'start'} - $test_region_params->{start} + 1),
            -end       => ($e_spec->{'end'}   - $test_region_params->{start} + 1),
            -strand    => $e_spec->{'strand'},
            -slice     => $slice,
            -phase     => -1,
            -end_phase => -1,
            );
        $transcript->add_Exon($exon);
        push @exons, $exon;
        unless (defined $start_Exon_Pos) {
            $start_Exon_Pos = $bvt_otter->translation_pos($tran_start_pos, $exon);
            $start_Exon = $exon if defined $start_Exon_Pos;
        }
        unless (defined $end_Exon_Pos) {
            $end_Exon_Pos = $bvt_otter->translation_pos($tran_end_pos,$exon);
            $end_Exon = $exon if defined $end_Exon_Pos;
        }
    }

    my $translation = Bio::Vega::Translation->new();
    $translation->start_Exon($start_Exon);
    $translation->start($start_Exon_Pos);
    $translation->end_Exon($end_Exon);
    $translation->end($end_Exon_Pos);
    $transcript->translation($translation);

    my @evidence_list;
    push @evidence_list, Bio::Vega::Evidence->new( -name => 'Em:AK056496', -type => 'Genomic' );
    push @evidence_list, Bio::Vega::Evidence->new( -name => 'Sw:Q96MT4',   -type => 'Protein' );
    $transcript->evidence_list(\@evidence_list);

    $gene->add_Transcript($transcript);
    return $gene;
}

{
    my $extra_gene = <<'__EO_GENE_XML__';
     <locus>
       <description>TEST COPY of chromosome 6 open reading frame 195</description>
       <name>ANACODE-TEST-GENE</name>
       <type>Known_CDS</type>
       <known>1</known>
       <truncated>0</truncated>
       <synonym>TEST-GENE-SYN-1</synonym>
       <synonym>TEST-GENE-SYN-2</synonym>
       <author>anacode</author>
       <author_email>anacode</author_email>
       <transcript>
         <author>anacode</author>
         <author_email>anacode</author_email>
         <remark>TEST COPY of novel protein (FLJ31934)</remark>
         <transcript_class>Known_CDS</transcript_class>
         <name>ANACODE-TEST-TRANSCRIPT-001</name>
         <translation_start>2591909</translation_start>
         <translation_end>2591526</translation_end>
         <evidence_set>
           <evidence>
             <name>Em:AK056496</name>
             <type>Genomic</type>
           </evidence>
           <evidence>
             <name>Sw:Q96MT4</name>
             <type>Protein</type>
           </evidence>
         </evidence_set>
         <exon_set>
           <exon>
             <start>2602652</start>
             <end>2602690</end>
             <strand>-1</strand>
             <phase>-1</phase>
             <end_phase>-1</end_phase>
           </exon>
           <exon>
             <start>2601692</start>
             <end>2601879</end>
             <strand>-1</strand>
             <phase>-1</phase>
             <end_phase>-1</end_phase>
           </exon>
           <exon>
             <start>2590000</start>
             <end>2592206</end>
             <strand>-1</strand>
             <phase>-1</phase>
             <end_phase>-1</end_phase>
           </exon>
         </exon_set>
       </transcript>
     </locus>
__EO_GENE_XML__

    sub add_extra_gene_xml {
        my ($self, $xml) = @_;
        $xml =~ s|(     </locus>\n)(   </sequence_set>)|$1$extra_gene$2|m;
        return $xml;
    }
}

{
    my %gene_info = (
        # First region, chr6-38 partial clones 37, 38
        OTTHUMG00000175882 => { source  => 'havana', biotype => 'tec',                  status  => 'UNKNOWN', },
        OTTHUMG00000014122 => { source  => 'havana', biotype => 'protein_coding',       status  => 'KNOWN',   },
        OTTHUMG00000014123 => { source  => 'havana', biotype => 'processed_transcript', status  => 'UNKNOWN', },

        # Second region, chr2-38 clones 16 - 26
        OTTHUMG00000151389 => { source  => 'havana', biotype => 'processed_transcript', status  => 'NOVEL',   },
        OTTHUMG00000151370 => { source  => 'havana', biotype => 'protein_coding',       status  => 'KNOWN',   },
        OTTHUMG00000151390 => { source  => 'havana', biotype => 'processed_transcript', status  => 'NOVEL',   },
        OTTHUMG00000151387 => { source  => 'havana', biotype => 'processed_transcript', status  => 'NOVEL',   },
        OTTHUMG00000151388 => { source  => 'havana', biotype => 'processed_transcript', status  => 'NOVEL',   },
        OTTHUMG00000090271 => { source  => 'havana', biotype => 'protein_coding',       status  => 'KNOWN',   },
        );

    sub gene_info_lookup {
        my ($self, $stable_id) = @_;
        return $gene_info{$stable_id};
    }
}

{
    my %transcript_info = (
        # First region, chr6-38 partial clones 37, 38
        OTTHUMT00000431233 => { biotype => 'tec',            status  => 'UNKNOWN', },
        OTTHUMT00000039633 => { biotype => 'protein_coding', status  => 'KNOWN',   },
        OTTHUMT00000039634 => { biotype => 'lincrna',        status  => 'UNKNOWN', },

        # Second region, chr2-38 clones 16 - 26
        OTTHUMT00000322452 => { biotype => 'antisense',               status  => 'UNKNOWN', },
        OTTHUMT00000322407 => { biotype => 'nonsense_mediated_decay', status  => 'UNKNOWN', },
        OTTHUMT00000322786 => { biotype => 'nonsense_mediated_decay', status  => 'UNKNOWN', },
        OTTHUMT00000322454 => { biotype => 'protein_coding',          status  => 'KNOWN',   },
        OTTHUMT00000322455 => { biotype => 'protein_coding',          status  => 'NOVEL',   },
        OTTHUMT00000322456 => { biotype => 'processed_transcript',    status  => 'UNKNOWN', },
        OTTHUMT00000322460 => { biotype => 'processed_transcript',    status  => 'UNKNOWN', },
        OTTHUMT00000322787 => { biotype => 'processed_transcript',    status  => 'UNKNOWN', },
        OTTHUMT00000322457 => { biotype => 'processed_transcript',    status  => 'UNKNOWN', },
        OTTHUMT00000322461 => { biotype => 'processed_transcript',    status  => 'UNKNOWN', },
        OTTHUMT00000322458 => { biotype => 'processed_transcript',    status  => 'UNKNOWN', },
        OTTHUMT00000322459 => { biotype => 'processed_transcript',    status  => 'UNKNOWN', },
        OTTHUMT00000322462 => { biotype => 'processed_transcript',    status  => 'UNKNOWN', },
        OTTHUMT00000322453 => { biotype => 'antisense',               status  => 'UNKNOWN', },
        OTTHUMT00000322450 => { biotype => 'antisense',               status  => 'UNKNOWN', },
        OTTHUMT00000322451 => { biotype => 'antisense',               status  => 'UNKNOWN', },
        OTTHUMT00000353107 => { biotype => 'processed_transcript',    status  => 'UNKNOWN', },
        );

    sub transcript_info_lookup {
        my ($self, $stable_id) = @_;
        return $transcript_info{$stable_id};
    }
}

sub base_name {
    my ($self) = @_;
    my $base_name = $self->{'base_name'};
    return $base_name;
}

sub xml_region {
    my ($self) = @_;
    my $xml_region = $self->{'xml_region'};
    return $xml_region if $xml_region;

    my $name =  $self->base_name;
    $xml_region = read_file("${REGION_PATH}/${name}.xml");
    chomp $xml_region;

    return $self->{'xml_region'} = $xml_region;
}

sub xml_parsed {
    my ($self) = @_;
    my $xml_parsed = $self->{'xml_parsed'};
    return $xml_parsed if $xml_parsed;

    require XML::Simple;
    XML::Simple->import(':strict');
    my $xs = XML::Simple->new(
        ForceArray => [ qw( locus transcript exon evidence feature ) ],
        KeyAttr    => [],
        );
    my $parsed = $xs->XMLin($self->xml_region);

    return $self->{'xml_parsed'} = $parsed;
}

sub xml_bounds {
    my ($self) = @_;
    my $parsed = $self->xml_parsed();
    my $sequence_set = $parsed->{sequence_set};

    my $start = min(map { $_->{assembly_start} } @{$sequence_set->{sequence_fragment}});
    my $end   = max(map { $_->{assembly_end} }   @{$sequence_set->{sequence_fragment}});

    return ($start, $end, $end - $start + 1);
}

sub region_params {
    my ($self) = @_;
    my $region_params = $self->{'region_params'};
    return $region_params if $region_params;

    my @bounds = $self->xml_bounds;
    my $parsed = $self->xml_parsed;
    my $set    = $parsed->{sequence_set};

    my $params = {
        dataset => $parsed->{species},
        name    => $set->{sequence_fragment}->[0]->{chromosome},
        chr     => $set->{assembly_type},
        cs      => 'chromosome',
        csver   => 'Otter',
        start   => $bounds[0],
        end     => $bounds[1],
    };

    return $self->{'region_params'} = $params;
}

sub fake_dna {
    my ($self) = @_;
    my (undef, undef, $length) = $self->xml_bounds();
    my $chunk = "GATTACAAGT";
    return ($chunk x int($length / 10)) . substr($chunk, 0, $length % 10);
}

sub assembly_dna {
    my ($self) = @_;
    my $assembly_dna = $self->{'assembly_dna'};
    return $assembly_dna if $assembly_dna;

    my $name =  $self->base_name;
    $assembly_dna = read_file("${REGION_PATH}/${name}.assembly_dna.txt");
    chomp $assembly_dna;

    return $self->{'assembly_dna'} = $assembly_dna;
}

1;
