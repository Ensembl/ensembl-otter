package Bio::Otter::CloneFinder;

#
# A module used by server script 'find_clones' to find things on clones
# (old API version)
#

use strict;
use Bio::Otter::Lace::Locator;

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

sub qnames_locators {
#
# This is a HoL
# {query_name}[locators*]
#
    my $self = shift @_;

    return $self->{_ql};
}

sub register_clones {
    my ($self, $qname, $qtype, $clone_names) = @_;

    my $unhide = $self->{_unhide};

    my $clones_string = join(', ', map { "'$_'" } keys %$clone_names);
    my $sql = qq{
        SELECT asm.type, concat(cl.embl_acc,'.',cl.embl_version),
               asm.chr_start, asm.chr_end
          FROM clone cl, contig ctg, assembly asm
    }.($unhide ? '' : ' , sequence_set ss ')
    .qq{
         WHERE concat(cl.embl_acc,'.',cl.embl_version) IN ($clones_string)
           AND ctg.clone_id=cl.clone_id
           AND asm.contig_id=ctg.contig_id
    }.($unhide ? '' : " AND ss.assembly_type=asm.type AND ss.hide='N' ")
    .qq{
      ORDER BY asm.type, asm.chr_start
    };

    warn $sql if $DEBUG;
    my $sth = $self->dba->prepare($sql);
    $sth->execute;
    
    my $locs = $self->qnames_locators()->{$qname};
    my $curr_loc;
    my $curr_atype = '';
    my $curr_clone_names;
    while (my ($atype, $clone_name, $chr_start, $chr_end) = $sth->fetchrow) {
        if($atype ne $curr_atype) { # new atype section has started
            if($curr_atype) { # store the previous one
                $curr_loc = Bio::Otter::Lace::Locator->new($qname, $qtype);
                $curr_loc->assembly($curr_atype);
                $curr_loc->component_names($curr_clone_names);
                push @$locs, $curr_loc;
            }

                # prepare for the next one:
            $curr_clone_names = [$clone_name];
            $curr_atype = $atype;
        } else {
            push @$curr_clone_names, $clone_name;
        }
    }
    if($curr_atype) { # store the last one
        $curr_loc = Bio::Otter::Lace::Locator->new($qname, $qtype);
        $curr_loc->assembly($curr_atype);
        $curr_loc->component_names($curr_clone_names);
        push @$locs, $curr_loc;
    }
}

sub exons2clones {
    my ($self, $qname, $qtype, $exons) = @_;

    my %clone_names = ();
    foreach my $exon (@$exons) {
        my $clone = $exon->contig()->clone();
        $clone_names { $clone->embl_id().'.'.$clone->embl_version() } ++;
    }

    $self->register_clones($qname, $qtype, \%clone_names);
}

sub find {
    my ($self, $unhide) = @_;

    $self->{_unhide} = $unhide;

    my $dba      = $self->dba();
    my $meta_con = $dba->get_MetaContainer();

    my $prefix_primary = $meta_con->get_primary_prefix();
        # OR error_exit($sq, "Missing prefix.primary in meta table");

    my $prefix_species = $meta_con->get_species_prefix();
        # OR error_exit($sq, "Missing prefix.species in meta table");

    my $gene_adaptor           = $dba->get_GeneAdaptor();
    my $genename_adaptor       = $dba->get_GeneNameAdaptor();
    my $genesyn_adaptor        = $dba->get_GeneSynonymAdaptor();
    my $geneinfo_adaptor       = $dba->get_GeneInfoAdaptor();
    my $transcript_adaptor     = $dba->get_TranscriptAdaptor();
    my $exon_adaptor           = $dba->get_ExonAdaptor();

    foreach my $qname (keys %{ $self->qnames_locators() }) {
        if(uc($qname) =~ /^$prefix_primary$prefix_species([TPGE])\d+/i){ # try stable_ids
            my $typeletter = $1;
            my $type;
            my $exons;

            eval {
                if($typeletter eq 'G') {
                    $type = 'gene_stable_id';
                    $exons = $gene_adaptor->fetch_by_stable_id($qname)->get_all_Exons();
                } elsif($typeletter eq 'T') {
                    $type = 'transcript_stable_id';
                    $exons = $transcript_adaptor->fetch_by_stable_id($qname)->get_all_Exons();
                } elsif($typeletter eq 'P') {
                    $type = 'translation_stable_id';
                    $exons = $transcript_adaptor->fetch_by_translation_stable_id($qname)->get_all_Exons();
                } elsif($typeletter eq 'E') {
                    $type = 'exon_stable_id';
                    $exons = [ $exon_adaptor->fetch_by_stable_id($qname) ];
                }
            };
                # Just imagine: they raise an EXCEPTION to indicate nothing was found. Terrific!
            if($@) {
                # server_log("'$qname' looks like a stable id, but wasn't found.");
                # server_log($@)if $DEBUG;
            } else {
                $self->exons2clones($qname, $type, $exons);
            }
        }
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
                $self->register_clones($qname, 'clone_accession', {$clone_name});
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
                $self->register_clones($qname, 'contig_name', {$clone_name});
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
                $self->register_clones($qname, 'intl_clone_name', {$clone_name});
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

    } # foreach $qname
}

sub generate_output {
    my ($self, $filter_atype) = @_;

    my $output_string = '';

    for my $qname (sort keys %{$self->qnames_locators()}) {
        my $count = 0;
        for my $loc (sort {$a->assembly cmp $b->assembly}
                        @{ $self->qnames_locators()->{$qname} }) {
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

