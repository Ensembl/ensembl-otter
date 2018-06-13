=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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

package Test::Bio::Vega::CoordSystemFactory;

use Test::Class::Most
    parent     => 'OtterTest::Class',
    attributes => [ qw( test_db dba ) ];

use Bio::EnsEMBL::ApiVersion;   # exports software_version
use Bio::Vega::DBSQL::DBAdaptor;
use OtterTest::DB;

sub startup {
    my $test = shift;

    my $db = OtterTest::DB->new;
    $test->test_db($db);

    my $dba = Bio::Vega::DBSQL::DBAdaptor->new(
        -driver  => 'SQLite',
        -dbname  => $db->file,
        -species => $db->species,
        );
    $test->dba($dba);

    my $sv = software_version();
    $dba->dbc->do("INSERT INTO meta (species_id, meta_key, meta_value) VALUES (NULL, 'schema_version', $sv)");

    $test->SUPER::startup;
    return;
}

sub build_attributes { return };

sub coord_systems : Tests {
    my $test = shift;

    my $factory = $test->our_object;
    can_ok $factory, 'coord_system';

    foreach my $name ($factory->known) {
        subtest $name => sub {
            my $cs = $factory->coord_system($name);
            isa_ok $cs, 'Bio::EnsEMBL::CoordSystem';
            _note_cs($cs);
        };
    }

    return;
}

sub override_spec : Tests {
    my $test = shift;

    my $override_spec = { 'chromosome' => { '-dbid' => 2, '-version' => 'Test', '-rank' => 2, '-default' => 1, } };

    my $std_factory = $test->our_object;
    my $ovr_factory = $test->class->new( override_spec => $override_spec );

    foreach my $name ($std_factory->known) {
        subtest $name => sub {
            my $std = $std_factory->coord_system($name);
            my $ovr = $ovr_factory->coord_system($name);
            isa_ok $ovr, 'Bio::EnsEMBL::CoordSystem';
            _note_cs($ovr);
            if ($name eq 'chromosome') {
                $std = Bio::EnsEMBL::CoordSystem->new('-name' => $name, %{$override_spec->{'chromosome'}});
            }
            foreach my $field ( qw( dbID version rank is_default is_sequence_level ) ) {
                is $ovr->$field, $std->$field, $field;
            }
        };
    }

    return;
}

# The following three are numbered to ensure sequential execution
#
sub dba_0_not_stored_yet : Tests {
    my $test = shift;

    my $dba_factory = $test->class->new( dba => $test->dba );
    foreach my $name ($dba_factory->known) {
        my $cs = $dba_factory->coord_system($name);
        ok not(defined($cs)), "$name: not defined";
    }
    return;
}

sub dba_1_create_in_db : Tests {
    my $test = shift;

    my $dba = $test->dba;
    my $dba_factory = $test->class->new( dba => $dba, create_in_db => 1 );

    can_ok $dba_factory, 'instantiate_all';
    $dba_factory->instantiate_all;

    foreach my $name ($dba_factory->known) {
        subtest $name => sub {
            my $cs = $dba_factory->coord_system($name);
            isa_ok $cs, 'Bio::EnsEMBL::CoordSystem';
            ok $cs->is_stored($dba), 'stored';
            _note_cs($cs);
        };
    }
    return;
}

sub dba_2_already_in_db : Tests {
    my $test = shift;

    my $dba = $test->dba;
    my $dba_factory = $test->class->new( dba => $dba );
    foreach my $name ($dba_factory->known) {
        subtest $name => sub {
            my $cs = $dba_factory->coord_system($name);
            isa_ok $cs, 'Bio::EnsEMBL::CoordSystem';
            ok $cs->is_stored($dba), 'stored';
            _note_cs($cs);
        };
    }
    return;
}

sub assembly_mappings : Tests(2) {
    my $test = shift;
    my $factory = $test->our_object;

    can_ok $factory, 'assembly_mappings';
    my @mappings = $factory->assembly_mappings;
    ok scalar(@mappings), '... and returns some mappings';
    note 'n(assembly_mappings) = ', scalar(@mappings);

    return;
}

sub _note_cs {
    my ($cs) = @_;
    note(sprintf '%-10s, v: %-5s, r: %2s, d: %s, s: %s, id: %4s',
         $cs->name,
         $cs->version           // '',
         $cs->rank,
         $cs->is_default        ?  'y' : 'n',
         $cs->is_sequence_level ?  'y' : 'n',
         $cs->dbID              // '',
        );
}

1;
