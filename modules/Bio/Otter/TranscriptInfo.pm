
package Bio::Otter::TranscriptInfo;

# clone info file

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::Root;

@ISA = qw(Bio::EnsEMBL::Root);

sub new {
    my ($class, @args) = @_;

    my $self = bless {}, $class;

    my (
        $dbid,     $stable_id, $name,       $tclass,
        $start_nf, $end_nf,    $mrna_start, $mrna_end,
        $author,   $timestamp, $remark,     $evidence
      )
      = $self->_rearrange(
        [
            qw(DBID STABLE_ID NAME CLASS CDS_START_NOT_FOUND CDS_END_NOT_FOUND
              MRNA_START_NOT_FOUND MRNA_END_NOT_FOUND AUTHOR TIMESTAMP REMARK EVIDENCE)
        ],
        @args
      );

    $self->dbID($dbid);
    $self->transcript_stable_id($stable_id);
    $self->name($name);
    $self->class($tclass);
    $self->cds_start_not_found($start_nf);
    $self->cds_end_not_found($end_nf);
    $self->mRNA_start_not_found($mrna_start);
    $self->mRNA_end_not_found($mrna_end);
    $self->author($author);
    $self->timestamp($timestamp);

    $self->{_remark} = [];
    $self->flush_Evidence;

    if (defined($evidence)) {
        if (ref($evidence) eq "ARRAY") {
            $self->add_Evidence(@$evidence);
        }
        else {
            $self->throw(
"Argument to evidence must be an array ref. Currently [$evidence]"
            );
        }
    }

    if (defined($remark)) {
        if (ref($remark) eq "ARRAY") {
            $self->remark(@$remark);
        }
        else {
            $self->throw(
                "Argument to remark must be an array ref. Currently [$remark]");
        }
    }

    return $self;
}

=head2 dbID

 Title   : dbID
 Usage   : $obj->dbID($newval)
 Function: 
 Example : 
 Returns : value of dbID
 Args    : newvalue (optional)


=cut

sub dbID {
    my ($obj, $value) = @_;
    if (defined $value) {
        $obj->{'dbID'} = $value;
    }
    return $obj->{'dbID'};

}

=head2 transcript_stable_id

 Title   : transcript_stable_id
 Usage   : $obj->transcript_stable_id($newval)
 Function: 
 Example : 
 Returns : value of transcript_stable_id
 Args    : newvalue (optional)


=cut

sub transcript_stable_id {
    my ($obj, $value) = @_;
    if (defined $value) {
        $obj->{'stable_id'} = $value;
    }
    return $obj->{'stable_id'};

}

=head2 author

 Title   : author
 Usage   : $obj->author($newval)
 Function: 
 Example : 
 Returns : value of author
 Args    : newvalue (optional)


=cut

sub author {

    my ($self, $value) = @_;

    if (defined($value)) {
        if ($value->isa("Bio::Otter::Author")) {
            $self->{'author'} = $value;
        }
        else {
            $self->throw("Argument [$value] is not a Bio::Otter::Author");
        }
    }
    return $self->{'author'};
}

=head2 timestamp

 Title   : timestamp
 Usage   : $obj->timestamp($newval)
 Function: 
 Example : 
 Returns : value of timestamp
 Args    : newvalue (optional)


=cut

sub timestamp {
    my ($obj, $value) = @_;
    if (defined $value) {
        $obj->{'timestamp'} = $value;
    }
    return $obj->{'timestamp'};

}

=head2 name

 Title   : name
 Usage   : $obj->name($newval)
 Function: name of the transcript as the annotator sees it
 Example : 
 Returns : value of name
 Args    : newvalue (optional)


=cut

sub name {
    my ($obj, $value) = @_;
    if (defined $value) {
        $obj->{'name'} = $value;
    }
    return $obj->{'name'};
}

=head2 class

 Title   : class
 Usage   : $obj->class($newval)
 Function: 
 Example : 
 Returns : value of class
 Args    : newvalue (optional)


=cut

sub class {
    my ($obj, $value) = @_;
    if (defined $value) {
        if ($value->isa("Bio::Otter::TranscriptClass")) {
            $obj->{'class'} = $value;
        }
        else {
            $obj->throw(
"Argument to class should be a Transcriptclass object.  Currently [$value]"
            );
        }
    }
    return $obj->{'class'};

}

=head2 cds_start_not_found

 Title   : cds_start_not_found
 Usage   : $obj->cds_start_not_found($newval)
 Function: 
 Example : 
 Returns : value of cds_start_not_found, or zero if not set
 Args    : newvalue (optional)


=cut

sub cds_start_not_found {
    my ($obj, $value) = @_;

    if (defined $value) {

        if ($value eq "true") {
            $value = 1;
        }
        elsif ($value eq "false") {
            $value = 0;
        }

        if ($value != 0 && $value != 1) {
            $obj->throw("Value must be either 0 or 1");
        }

        $obj->{'cds_start_not_found'} = $value;
    }
    return $obj->{'cds_start_not_found'} || 0;
}

=head2 cds_end_not_found

 Title   : cds_end_not_found
 Usage   : $obj->cds_start_not_found($newval)
 Function: 
 Example : 
 Returns : value of cds_end_not_found, or zero if not set
 Args    : newvalue (optional)


=cut

sub cds_end_not_found {
    my ($obj, $value) = @_;

    if (defined $value) {

        if ($value eq "true") {
            $value = 1;
        }
        elsif ($value eq "false") {
            $value = 0;
        }

        if ($value ne '0' && $value ne '1') {
            $obj->throw("Value must be either 0 or 1");
        }
        $obj->{'cds_end_not_found'} = $value;
    }
    return $obj->{'cds_end_not_found'} || 0;
}

=head2 mRNA_start_not_found

 Title   : mRNA_start_not_found
 Usage   : $obj->mRNA_start_not_found($newval)
 Function: 
 Example : 
 Returns : value of mRNA_start_not_found, or zero if not set
 Args    : newvalue (optional)


=cut

sub mRNA_start_not_found {
    my ($obj, $value) = @_;
    if (defined $value) {

        if ($value eq "true") {
            $value = 1;
        }
        elsif ($value eq "false") {
            $value = 0;
        }

        if ($value != 0 && $value != 1) {
            $obj->throw("Value must be either 0 or 1");
        }
        $obj->{'mRNA_start_not_found'} = $value;
    }
    return $obj->{'mRNA_start_not_found'} || 0;
}

=head2 mRNA_end_not_found

 Title   : mRNA_end_not_found
 Usage   : $obj->mRNA_start_not_found($newval)
 Function: 
 Example : 
 Returns : value of mRNA_end_not_found, or zero if not set
 Args    : newvalue (optional)


=cut

sub mRNA_end_not_found {
    my ($obj, $value) = @_;
    if (defined $value) {

        if ($value eq "true") {
            $value = 1;
        }
        elsif ($value eq "false") {
            $value = 0;
        }

        if ($value != 0 && $value != 1) {
            $obj->throw("Value must be either 0 or 1");
        }
        $obj->{'mRNA_end_not_found'} = $value;
    }
    return $obj->{'mRNA_end_not_found'} || 0;
}

sub remark {
    my $obj = shift @_;

    while (my $rem = shift @_) {
        if ($rem->isa("Bio::Otter::TranscriptRemark")) {
            push(@{ $obj->{'_remark'} }, $rem);
        }
        else {
            $obj->throw("Object [$rem] is not a TranscriptRemark object");
        }
    }

    return @{ $obj->{'_remark'} };

}

sub add_Evidence {
    my $self = shift;

    my $list = $self->{'_evidence'};
    while (my $ev = shift) {
        if ($ev->isa("Bio::Otter::Evidence")) {
            push(@$list, $ev);
            $self->{'_is_sorted'} = 0;
        }
        else {
            $self->throw("Object [$ev] is not an Evidence object");
        }
    }
}

sub get_all_Evidence {
    my $self = shift;

    unless ($self->{'_is_sorted'}) {
        # Ensures that we only sort the evidence array once
        $self->{'_evidence'} =
          [ sort { $a->type cmp $b->type || $a->name cmp $b->name }
              @{ $self->{'_evidence'} } ];
        $self->{'_is_sorted'} = 1;
    }
    return $self->{'_evidence'};
}

sub flush_Evidence {
    my $self = shift;

    $self->{'_evidence'} = [];
    return 1;
}

sub toString {
    my ($self) = shift;

    my $str = "";

    my $dbid;
    my $timestamp;

    if (!defined($self->dbID)) {
        $dbid = "";
    }
    else {
        $dbid = $self->dbID;
    }

    if (!defined($self->timestamp)) {
        $timestamp = "";
    }
    else {
        $timestamp = $self->timestamp("");
    }

    $str .= "DbID       : " . $dbid . "\n";
    $str .= "Stable id  : " . $self->transcript_stable_id . "\n";
    $str .= "Timestamp  : " . $timestamp . "\n";
    $str .= "Name       : " . $self->name . "\n";
    $str .= "Cds_snf    : " . $self->cds_start_not_found . "\n";
    $str .= "Cds_enf    : " . $self->cds_end_not_found . "\n";
    $str .= "Mrna_snf   : " . $self->mRNA_start_not_found . "\n";
    $str .= "Mrna_enf   : " . $self->mRNA_end_not_found . "\n";

    $str .= "Class info :-\n";
    $str .= $self->class->toString() . "\n";

    $str .= "Author info :-\n";

    $str .= $self->author->toString() . "\n";

    $str .= "Gene info remarks :-\n";

    foreach my $rem ($self->remark) {
        $str .= $rem->toString() . "\n";
    }

    $str .= "Transcript evidence :-\n";

    $str .= "EV:\n";
    foreach my $ev (@{ $self->get_all_Evidence }) {
        $str .= $ev->toString() . "\n";
    }
    return $str;

}

sub validate {
    my ($self) = @_;

    if (!defined($self->transcript_stable_id)) {
        $self->throw("No stable id");
    }
    if (!defined($self->author)) {
        $self->throw("No author for transcript " . $self->transcript_stable_id);
    }
    if (!defined($self->name)) {
        $self->throw("No name for transcript " . $self->transcript_stable_id);
    }

    #    if (!defined($self->cds_start_not_found)) {
    #	$self->throw("No cds_start_not_found");
    #    }
    #    if (!defined($self->cds_end_not_found)) {
    #	$self->throw("No cds_end_not_found");
    #    }
    #    if (!defined($self->mRNA_start_not_found)) {
    #	$self->throw("No mRNA start not found");
    #    }
    #    if (!defined($self->mRNA_end_not_found)) {
    #	$self->throw("No mRNA end not found");
    #    }
}

sub equals {
    my ($self, $obj) = @_;

    if (!defined($obj)) {
        $self->throw("Need an object to compare with");
    }
    if (!$obj->isa("Bio::Otter::TranscriptInfo")) {
        $self->throw("[$obj] is not a Bio::Otter::TranscriptInfo");
    }

    $self->validate;
    $obj->validate;

    if ($self->transcript_stable_id ne $obj->transcript_stable_id) {
        print STDERR " FOUND DIFF : Stable id different "
          . $self->transcript_stable_id . " : "
          . $obj->transcript_stable_id . "\n";
        return 0;
    }
    if ($self->class->equals($obj->class) == 0) {
        print STDERR "FOUND DIFF : Different class "
          . $self->class->name . " : "
          . $obj->class->name . "\n";
        return 0;
    }
    if ($self->name ne $obj->name) {
        print STDERR "FOUND DIFF : Name different "
          . $self->name . " : "
          . $obj->name . "\n";
        return 0;
    }

    my $cdss = $self->cds_start_not_found;
    my $cdse = $self->cds_end_not_found;
    my $rnas = $self->mRNA_start_not_found;
    my $rnae = $self->mRNA_end_not_found;

    my $obj_cdss = $obj->cds_start_not_found;
    my $obj_cdse = $obj->cds_end_not_found;
    my $obj_rnas = $obj->mRNA_start_not_found;
    my $obj_rnae = $obj->mRNA_end_not_found;
    if ($cdss != $obj_cdss) {
        print STDERR
          "FOUND DIFF : Cds start not found different $cdss : $obj_cdss\n";
        return 0;
    }
    if ($cdse != $obj_cdse) {
        print STDERR
          "FOUND DIFF : Cds end not found different $cdse : $obj_cdse\n";
        return 0;
    }
    if ($rnas != $obj_rnas) {
        print STDERR
          "FOUND DIFF : Rna start not found different $rnas : $obj_rnas\n";
        return 0;
    }
    if ($rnae != $obj_rnae) {
        print STDERR
          "FOUND DIFF : Rna end not found different $rnae : $obj_rnae\n";
        return 0;
    }

    my @remark1 = $self->remark;
    my @remark2 = $obj->remark;

    if (scalar(@remark1) != scalar(@remark2)) {
        print STDERR "Different numbers of remarks "
          . scalar(@remark1) . " : "
          . scalar(@remark2) . "\n";
        return 0;
    }

    foreach my $rem (@remark1) {
        my $found = 0;

        foreach my $rem2 (@remark2) {
            if ($rem->equals($rem2)) {
                $found = 1;
            }
        }
        if ($found == 0) {
            print "FOUND DIFF in remark\n";
            return 0;
        }
    }

    my $ev_list1 = $self->get_all_Evidence;
    my $ev_list2 = $obj->get_all_Evidence;

    if (@$ev_list1 != @$ev_list2) {
        print STDERR "FOUND DIFF : Different evidence numbers "
          . scalar(@$ev_list1) . " : "
          . scalar(@$ev_list2) . "\n";
        return 0;
    }
    
    my %ev_names2 = map {$_->name, 1} @$ev_list2;
    foreach my $ev1 (@$ev_list1) {
        unless ($ev_names2{$ev1->name}) {
            print STDERR "FOUND DIFF : in evidence\n";
            return 0;
        }
    }

    return 1;
}

1;
