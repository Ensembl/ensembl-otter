package MenuCanvasWindow::ZMapExonCanvas;

use strict;
use warnings;

use Carp;
use Tk::Dialog;
use Tk::ROText;
use Tk::LabFrame;
use Tk::ComboBox;
use Hum::Ace::SubSeq;
use Hum::Translator;
use MenuCanvasWindow;
use Hum::Ace::DotterLauncher;
use CanvasWindow::EvidencePaster;

use Hum::Ace;
use Bio::Otter::Converter;

use MenuCanvasWindow::ExonCanvas;

our @ISA = qw(MenuCanvasWindow::ExonCanvas);


sub xace_save {
    my( $self, $sub ) = @_;

    warn "$sub";
    
    confess "Missing SubSeq argument" unless $sub;

    my $old = $self->SubSeq;
    my $old_name = $old->name;
    my $new_name = $sub->name;
    
    my $clone_name = $sub->clone_Sequence->name;
    if ($clone_name eq $new_name) {
        $self->message("Can't have SubSequence with same name as clone!");
        return;
    }
    
    my $ace = '';
    
    # Do we need to rename?
    if ($old->is_archival and $new_name ne $old_name) {
        $ace .= $sub->ace_string($old_name);
    } else {
        $ace .= $sub->ace_string;
    }
    
    # Add ace_string method from locus with rename as above
    
    print STDERR "Sending:\n$ace";

    my $xml =  make_zmap_xremote_xml($sub);
    print STDERR $xml;

    $self->XaceSeqChooser->zMapMakeRequest(undef, undef, $xml);

# most of the below still needs doing I guess!


#     my $xc = $self->XaceSeqChooser;
#     my $xr = $xc->xace_remote;
#     if ($xr) {
#         $xr->load_ace($ace);
#         $xr->save;
#         $xr->send_command('gif ; seqrecalc');
#         $xc->replace_SubSeq($sub, $old_name);
#         $self->SubSeq($sub);
#         $self->update_transcript_remark_widget($sub);
#         $self->update_Locus_tk_fields($sub->Locus);
#         $self->name($new_name);
#         $self->evidence_hash($sub->clone_evidence_hash);
#         $sub->is_archival(1);
#         $xc->update_all_locus_edit_fields($sub->Locus->name);
#         return 1;
#     } else {
#         $self->message("No xace attached");
#         return 0;
#     }

}

# akin to Hum::Ace::SubSeq->ace_string
# here so as not to alter PerlModules just yet.
sub make_zmap_xremote_xml{
    my( $ace_sub_seq, $old_name, $create ) = @_;
    my @exons       = $ace_sub_seq->get_all_Exons;
    my $name        = $ace_sub_seq->name
        or confess "name not set";
    my $clone_seq   = $ace_sub_seq->clone_Sequence
        or confess "no clone_Sequence";
    my $method      = $ace_sub_seq->GeneMethod;
    
    $create ||= 1;
    my $cmd = ($create ? "create_feature" : "delete_feature");
    my $xml = qq`<zmap action="$cmd">\n`;

    my ($align, $block);
    if($align && $block){
        $xml .= qq`\t<featureset align="" block="">\n`;
    }else{
        $xml .= qq`\t<featureset >\n`;
    }

    $xml .= sprintf(qq`\t\t<feature name="%s" start="%d" end="%d" style="%s" strand="%s" >\n`,
                    $name, 
                    $ace_sub_seq->start, 
                    $ace_sub_seq->end,
                    $method->name,
                    $ace_sub_seq->strand == 1 ? '+' : $ace_sub_seq->strand == -1 ? '-' : '.');

    # fix up numbers here
    for (my $i = 0; $i < @exons; $i++){
        my $ex = $exons[$i];
        if(($i > 0)){
            my $pex = $exons[$i - 1];
            # get intron info
            $xml .= sprintf(qq`\t\t\t<subfeature ontology="intron" start="%d" end="%d" />\n`,
                            $pex->end,
                            $ex->start);
        }
        $xml .= sprintf(qq`\t\t\t<subfeature ontology="exon" start="%d" end="%d" />\n`,
                        $ex->start,
                        $ex->end);
    }

    ## these are correct for zmap
    my ($cds_start, $cds_end) = $ace_sub_seq->cds_coords;
    if($cds_start && $cds_end){
        $xml .= qq`\t\t\t<subfeature ontology="cds" start="$cds_start" end="$cds_end" />\n`;
    }

    $xml .= qq`\t\t</feature>\n`;

    $xml .= qq`\t</featureset>\n`;

    $xml .= qq`</zmap>\n<!-- end xml -->\n`;

    return $xml;
}


1;
