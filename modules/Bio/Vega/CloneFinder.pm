package Bio::Vega::CloneFinder;

use strict;
use Bio::Otter::Lace::Locator;

my $component = 'clone';

#
# A module used by server script 'find_clones' to find things on clones
# (new API version)
#

use strict;

my $DEBUG=0; # do not show all SQL statements

sub new {
    my ($class, $dba, $qnames) = @_;

    my $self = bless {
        '_dba' => $dba,
        '_ql'  => ($qnames ? {map {($_ => [])} @$qnames } : {}),
    }, $class;

    return $self;
}

sub dba {
    my $self = shift @_;

    return $self->{_dba};
}

sub dbc {
    my $self = shift @_;

    return $self->dba->dbc();
}

sub qnames_locators {
#
# This is a HoL
# {query_name}[locators*]
#
    my $self = shift @_;

    return $self->{_ql};
}

sub register_feature {
    my ($self, $qname, $search_type, $feature) = @_;

    my $loc = Bio::Otter::Lace::Locator->new($qname, $search_type);

    my $csname = $feature->slice()->coord_system_name();

    $loc->assembly( ($csname eq 'chromosome')
        ? $feature->seq_region_name()
        : $feature->project('chromosome')->[0]->to_Slice()->seq_region_name()
    );

    $loc->component_names( ($csname eq $component)
        ? [ $feature->seq_region_name() ]
        : [ map { $_->to_Slice()->seq_region_name() } @{ $feature->project($component) } ]
    );

    my $locs = $self->qnames_locators()->{$qname} ||= [];
    push @$locs, $loc;
}

sub find_by_stable_ids {
    my $self = shift @_;

    my $dba      = $self->dba();
    my $meta_con = $dba->get_MetaContainer();

    my $prefix_primary = $meta_con->get_primary_prefix()
        || die "Missing prefix.primary in meta table";

    my $prefix_species = $meta_con->get_species_prefix()
        || die "Missing prefix.species in meta table";

    my $gene_adaptor           = $dba->get_GeneAdaptor();
    # my $genename_adaptor       = $dba->get_GeneNameAdaptor();
    # my $genesyn_adaptor        = $dba->get_GeneSynonymAdaptor();
    # my $geneinfo_adaptor       = $dba->get_GeneInfoAdaptor();
    my $transcript_adaptor     = $dba->get_TranscriptAdaptor();
    my $exon_adaptor           = $dba->get_ExonAdaptor();

    foreach my $qname (keys %{$self->qnames_locators()}) {
        if(uc($qname) =~ /^$prefix_primary$prefix_species([TPGE])\d+/i){ # try stable_ids
            my $typeletter = $1;
            my $type;
            my $feature;

            eval {
                if($typeletter eq 'G') {
                    $type = 'gene_stable_id';
                    $feature = $gene_adaptor->fetch_by_stable_id($qname);
                } elsif($typeletter eq 'T') {
                    $type = 'transcript_stable_id';
                    $feature = $transcript_adaptor->fetch_by_stable_id($qname);
                } elsif($typeletter eq 'P') {
                    $type = 'translation_stable_id';
                    $feature = $transcript_adaptor->fetch_by_translation_stable_id($qname);
                } elsif($typeletter eq 'E') {
                    $type = 'exon_stable_id';
                    $feature = $exon_adaptor->fetch_by_stable_id($qname);
                }
            };
                # Just imagine: they raise an EXCEPTION to indicate nothing was found. Terrific!
            if($@) {
                # server_log("'$qname' looks like a stable id, but wasn't found.");
                # server_log($@)if $DEBUG;
            } else {
                $self->register_feature($qname, $type, $feature);
            }
        }

=comment

        if($qname =~ /^(\w+)(?:\.(\d+))?$/) { # try clone accessions with & without version number
            my $wanted_acc = $1;
            my $wanted_version = $2;

            my $sql = qq{
                SELECT concat(embl_acc, '.', embl_version)
                FROM clone
                WHERE embl_acc = '$wanted_acc'
            }. (defined($wanted_version) ? qq{ AND embl_version = '$wanted_version' } : '');
            warn $sql if $DEBUG;
            my $sth = $dba->prepare($sql);
            $sth->execute;
            
            # server_log("trying clone accession[.version] '$qname' ");
            while (my ($clone_name) = $sth->fetchrow) {
                $qnames_types_clones->{$qname}{clone_accession}{$clone_name}++;
                $clone_name_set->{$clone_name}++;
            }
        } elsif($qname =~ /^\w+\.\d+\.\d+\.\d+$/) { # try mapping contigs to clones
            my $sql = qq{
                SELECT concat(cl.embl_acc, '.', cl.embl_version)
                FROM clone cl, contig co
                WHERE co.name = '$qname'
                  AND cl.clone_id = co.clone_id
            };
            warn $sql if $DEBUG;
            my $sth = $dba->prepare($sql);
            $sth->execute;
            
            # server_log("trying contig name '$qname' ");
            while (my ($clone_name) = $sth->fetchrow) {
                $qnames_types_clones->{$qname}{contig_name}{$clone_name}++;
                $clone_name_set->{$clone_name}++;
            }
        }

        { # try intl. clone names:
            my $sql = qq{
                SELECT concat(embl_acc, '.', embl_version)
                FROM clone
                WHERE name = '$qname'
            };
            warn $sql if $DEBUG;
            my $sth = $dba->prepare($sql);
            $sth->execute;
            
            # server_log("trying intl. clone name '$qname' ");
            while (my ($clone_name) = $sth->fetchrow) {
                $qnames_types_clones->{$qname}{intl_clone_name}{$clone_name}++;
                $clone_name_set->{$clone_name}++;
            }
        }


        { # try gene name or synonym:
            my $exons;
            eval{
                # server_log("trying gene name or synonym '$qname' ");
                my $geneNameObjList = $genename_adaptor->fetch_by_name($qname);
                my $geneSynObjList  = $genesyn_adaptor->fetch_by_name($qname);
                foreach my $geneNameObj (@$geneNameObjList, @$geneSynObjList){
                    my $geneInfoObj = $geneinfo_adaptor->fetch_by_dbID($geneNameObj->gene_info_id());    
                    $exons = $gene_adaptor->fetch_by_stable_id($geneInfoObj->gene_stable_id())->get_all_Exons();
                    $self->exons2clones($qname, 'gene_name_or_synonym', $exons);
                }
            };
            if ($@){
                ## assume error was caused by not being able to create a $geneNameObjList -
                ## - as name didnt exist
                #
                # server_log("no gene was found with name or synonym '$qname'"); 
                # server_log($@)if $DEBUG;
            }
        }

=cut

    } # foreach $qname
}

sub find {
    my ($self, $unhide) = @_;

    $self->find_by_stable_ids();
}

sub generate_output {
    my ($self, $filter_atype) = @_;

    my $output_string = '';

    for my $qname (sort keys %{$self->qnames_locators()}) {
        my $locators = $self->qnames_locators()->{$qname};
        my $count = 0;
        for my $loc (@$locators) {
            my $asm = $loc->assembly();
            if(!$filter_atype || ($filter_atype eq $asm)) {
                $output_string .= join("\t",
                    $qname, $loc->qtype(),
                    join(',', @{$loc->component_names()}),
                    $loc->assembly())."\n";
                $count++;
            }
        }
        if(!$count) {
            $output_string .= "$qname\n"; # no matches for this qname
        }
    }

    return $output_string;
}

1;

