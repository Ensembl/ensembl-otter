package Bio::Otter::CloneFinder;

#
# A module used by server script 'find_clones' to find things on clones
# (old API version)
#

use strict;

my $DEBUG=0; # do not show all SQL statements

sub new {
    my ($class, $dba, $qnames) = @_;

    my $self = bless {
        '_dba' => $dba,
        '_qtc' => ($qnames ? {map {($_ => {})} @$qnames } : {}),
        '_cns' => {},
        '_c2a' => {},
    }, $class;

    return $self;
}

sub dba {
    my $self = shift @_;

    return $self->{_dba};
}

sub qnames_types_clones {
#
# This is a 3-level hash:
# {query_name}{type_of_query}{clones_found}
#
    my $self = shift @_;

    return $self->{_qtc};
}

sub clone_name_set {
#
# This is a set emulated by a hash
# (the values mean numbers of 'hits', but are never used apart from testing !=0 )
#
    my $self = shift @_;

    return $self->{_cns};
}

sub clonename2assemblies {
#
# 2-level hash: # {clonename}{assembly}
# The values are numbers of hits
#
    my $self = shift @_;

    return $self->{_c2a};
}

sub exons2clones {
    my ($self, $qname, $search_type, $exons) = @_;

    foreach my $exon (@$exons) {
        my $clone = $exon->contig()->clone();
        my $clone_name = $clone->embl_id().'.'.$clone->embl_version();

        $self->qnames_types_clones->{$qname}{$search_type}{$clone_name}++;
        $self->clone_name_set->{$clone_name}++;
    }
}

sub find_otter_clones_by_qnames {
    my $self = shift @_;

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

    my $qnames_types_clones = $self->qnames_types_clones();
    my $clone_name_set      = $self->clone_name_set();

    foreach my $qname (keys %$qnames_types_clones) {
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

    } # foreach $qname
}

sub find_assemblies_by_clone_names {
    my ($self, $unhide) = @_;

    if(my @clone_names = keys %{$self->clone_name_set()} ) {

        my $clones_string = join(', ', map { "'$_'" } @clone_names);
        my $sql = qq{
            SELECT ss.assembly_type, concat(cl.embl_acc,'.',cl.embl_version), ss.hide
              FROM clone cl, contig co, assembly asm, sequence_set ss
             WHERE concat(cl.embl_acc,'.',cl.embl_version) IN ($clones_string)
               AND co.clone_id=cl.clone_id
               AND asm.contig_id=co.contig_id
               AND ss.assembly_type=asm.type
        }.($unhide ? '' : "       AND ss.hide='N' ");
        warn $sql if $DEBUG;
        my $sth = $self->dba->prepare($sql);
        $sth->execute;
        
        my $clonename2assemblies = $self->clonename2assemblies();

        # server_log("finding assemblies for clone names");
        while (my ($atype, $clone_name, $hide) = $sth->fetchrow) {
            $clonename2assemblies->{$clone_name} ||= {};
            $clonename2assemblies->{$clone_name}{$atype}++;
        }
    }
}

sub find {
    my ($self, $unhide) = @_;

    $self->find_otter_clones_by_qnames();
    $self->find_assemblies_by_clone_names($unhide);
}

sub generate_output {
    my ($self, $filter_atype) = @_;

    my $qnames_types_clones  = $self->qnames_types_clones();
    my $clonename2assemblies = $self->clonename2assemblies();

    my $output_string = '';

    for my $qname (sort keys %$qnames_types_clones) {
        my $types_set = $qnames_types_clones->{$qname};
        if(keys %$types_set) {
            for my $type (keys %$types_set) {
                my $clones = $types_set->{$type};

                my %asm2clonenames = ();

                    # inversion and partial grouping:
                for my $clone_name (keys %$clones) {
                    for my $asm (keys %{$clonename2assemblies->{$clone_name}}) {
                        $asm2clonenames{$asm}{$clone_name}++;
                    }
                }

                if(keys %asm2clonenames) {
                    for my $asm (sort keys %asm2clonenames) {
                        if(!$filter_atype || ($filter_atype eq $asm)) {
                            $output_string .= join("\t", $qname, $type,
                                join(',', keys %{$asm2clonenames{$asm}}),
                                $asm)."\n";
                        }
                    }
                } else {
                    $output_string .= "$qname\n";
                    # server_log("$qname found on some clone, but its assembly is hidden or inexistent");
                }
            }
        } else {
            $output_string .= "$qname\n";
            # server_log("$qname not found on any clone");
        }
    }

    return $output_string;
}

1;

