package apollo.dataadapter.otter.parser;

import apollo.datamodel.*;
import java.io.*;
import java.util.*;

/**
 * I visit elements of the Apollo datamodel, converting each them into XML with my
 * visit() methods. I am typically invoked with a call like: 
 * <code>
 * GenericAnnotationSet set = ...
 * OtterXMLRenderingVisitor visitor = new OtterXMLRenderingVisitor();
 * set.visit(visitor); //will create XML for all features in the set
 * String xml = visitor.getReturnBuffer().toString();
 * </code>
**/
public class OtterXMLRenderingVisitor
implements apollo.util.Visitor
{
  private int indent = 0;
  private StringBuffer returnBuffer = new StringBuffer();
  private String indentString = "";

  private static String [] genePropNames = { 
                                            TagHandler.AUTHOR, 
                                            TagHandler.AUTHOR_EMAIL
                                           }; 

  private static String [] transcriptPropNames = { 
                                                  TagHandler.CDS_START_NOT_FOUND,
                                                  TagHandler.CDS_END_NOT_FOUND, 
                                                  TagHandler.MRNA_START_NOT_FOUND,
                                                  TagHandler.MRNA_END_NOT_FOUND
                                                 }; 
  
  private int getIndent(){
    return indent;
  }//end getIndent
  
  private void incrementIndent(){
    indentString += TagHandler.INDENT;
    indent++;
  }//end incrementIndent
  
  private void decrementIndent(){
    indent--;
    if(indent >=1){
      indentString = indentString.substring(0, indentString.length()-2);
    }//end if
  }//end decrementIndent
  
  private String getIndentString(){
    return indentString;
  }//end getIndentString

  public StringBuffer getReturnBuffer(){
    return returnBuffer;
  }//end getReturnBuffer

  private void setReturnBuffer(StringBuffer newValue){
    returnBuffer = newValue;
  }//end setReturnBuffer
  
  private StringBuffer append(String append){
    return getReturnBuffer().append(append);
  }//end appendToReturnBuffer
  
  public void visit(SeqFeature feature){
    throw new apollo.dataadapter.NotImplementedException("This is not implemented");
  }

  private StringBuffer open(String tag){
    return
        append(TagHandler.LEFT)
        .append(tag)
        .append(TagHandler.RIGHT);
  }
  
  private StringBuffer close(String tag){
    return
        append(TagHandler.LEFT)
        .append(TagHandler.SLASH)
        .append(tag)
        .append(TagHandler.RIGHT);
  }
  
  private StringBuffer retrn(){
    return append(TagHandler.RETURN);
  }
  
  private void wrap(String tag, String value){
    append(getIndentString());
    open(tag).append(value);
    close(tag);
    retrn();
  }
  
//  private void wrapPropertiesForFeature(SeqFeature feature, String [] propNames){
//    Iterator keys;
//    String key;
//    String value;
//    
//    keys = feature.getProperties().keySet().iterator();
//    while(keys.hasNext()){
//      key = (String)keys.next();
//      value = feature.getProperty(key);
//      wrap(key, value);
//    }//end while
//  }//end wrapPropertiesForFeature

  private void wrapPropertiesForFeature(SeqFeature feature, String [] propNames){
    Iterator keys;
    String key;
    String value;
    
    for (int i=0;i<propNames.length;i++) {
      key = propNames[i];
      if (feature.getProperties().containsKey(key)) {
        value = feature.getProperty(key);
        wrap(key, value);
      } else {
        wrap(key, "");
      }
    }
  }//end wrapPropertiesForFeature
  
  public void visit(AssemblyFeature feature){
    
    append(getIndentString());
    open(TagHandler.SEQUENCE_FRAGMENT);
    retrn();

    incrementIndent();
    
    // wrapPropertiesForFeature(feature);
    
    //<assemblystart>1922</assemblystart>
    wrap(TagHandler.ID,feature.getId());
    wrap(TagHandler.CHROMOSOME,feature.getChromosome());
    wrap(TagHandler.ASSEMBLY_START,String.valueOf(feature.getLow()));
    //<assemblyend>1922</assemblyend>
    wrap(TagHandler.ASSEMBLY_END,String.valueOf(feature.getHigh()));
    wrap(TagHandler.ASSEMBLY_ORI,String.valueOf(feature.getStrand()));
    wrap(TagHandler.ASSEMBLY_OFFSET,String.valueOf(feature.getAssemblyOffset()));
    
    decrementIndent();
    
    append(getIndentString());
    close(TagHandler.SEQUENCE_FRAGMENT);
    retrn();
    
  }  

  public void visit(FeatureSet feature){
    open(TagHandler.OTTER);
    retrn();
    
    incrementIndent();
    
    append(getIndentString());
    open(TagHandler.SEQUENCE_SET);
    retrn();

    Iterator featureIterator = feature.getFeatures().iterator();
    incrementIndent();
    
    // wrapPropertiesForFeature(feature);
    
    while(featureIterator.hasNext()){
      //
      //this processes all contents of the set - assemblyfeatures,
      //genes and their child transcripts and exons.
      ((SeqFeature)featureIterator.next()).accept(this);
      append(TagHandler.RETURN);
    }//end while
    decrementIndent();
    
    append(getIndentString());
    close(TagHandler.SEQUENCE_SET);
    retrn();
    
    decrementIndent();
    
    close(TagHandler.OTTER);
  }//end visit 
  
  public void visit(Gene feature){
    append(getIndentString());
    open(TagHandler.GENE);
    retrn();

    incrementIndent();
    
    wrap(TagHandler.STABLE_ID, feature.getId());

    // Temporary location for name
    Iterator dbxrefs = feature.getdbXrefs().iterator();
    while(dbxrefs.hasNext()){
      DbXref dbx = (DbXref)dbxrefs.next();
      if (dbx.getIdType().equals("OtterName")) {
        wrap(TagHandler.NAME, dbx.getIdValue());
      }
    }

    Iterator synonyms = feature.getSynonyms().iterator();
    while(synonyms.hasNext()){
      wrap(TagHandler.SYNONYM, ((String)synonyms.next()));
    }
    
    Iterator comments = feature.getComments().iterator();
    while(comments.hasNext()){
      wrap(TagHandler.REMARK, ((Comment)comments.next()).getText());
    }//end while

    if (feature.getProperties().containsKey(TagHandler.AUTHOR)) {
      wrap(TagHandler.AUTHOR,feature.getProperty(TagHandler.AUTHOR));
    } else {
      wrap(TagHandler.AUTHOR,System.getProperty("user.name"));
    }

    if (feature.getProperties().containsKey(TagHandler.AUTHOR_EMAIL)) {
      wrap(TagHandler.AUTHOR_EMAIL,feature.getProperty(TagHandler.AUTHOR_EMAIL));
    } else {
      wrap(TagHandler.AUTHOR_EMAIL,System.getProperty("user.name") + "@sanger.ac.uk");
    }
    
    Iterator featureIterator = feature.getFeatures().iterator();

    while(featureIterator.hasNext()){
      //
      //this processes all contents of the set - assemblyfeatures,
      //genes and their child transcripts and exons.
      ((SeqFeature)featureIterator.next()).accept(this);
      append(TagHandler.RETURN);
    }//end while

    decrementIndent();
    
    append(getIndentString());
    close(TagHandler.GENE);
    retrn();
  }
  
  public void visit(Transcript feature){
    Iterator featureIterator = feature.getFeatures().iterator();
    Iterator evidenceIterator = feature.getEvidence().iterator();
    Evidence evidence;
    
    append(getIndentString());
    open(TagHandler.TRANSCRIPT);
    retrn();
    
    incrementIndent();
    
    wrap(TagHandler.STABLE_ID, feature.getId());

    Iterator synonyms = feature.getSynonyms().iterator();
    if (synonyms.hasNext()) {
      while(synonyms.hasNext()){
        wrap(TagHandler.NAME, ((String)synonyms.next()));
      }
    } else {
      wrap(TagHandler.NAME, "");
    }

    Iterator comments = feature.getComments().iterator();
    while(comments.hasNext()){
      wrap(TagHandler.REMARK, ((Comment)comments.next()).getText());
    }//end while
    

    wrap(TagHandler.TRANSCRIPT_CLASS, feature.getBioType());

    wrapPropertiesForFeature(feature,transcriptPropNames);
    
    //
    //print out evidence
    while(evidenceIterator.hasNext()){
      evidence = (Evidence)evidenceIterator.next();
      evidence.accept(this);
    }
    
    if (feature.getTranslationStart() != 0 &&
        feature.getTranslationEnd() != 0) {
      wrap(TagHandler.TRANSLATION_START,String.valueOf(feature.getTranslationStart()));
      wrap(TagHandler.TRANSLATION_END,String.valueOf(feature.getTranslationEnd()));
    }
    //
    //print out all exons.
    while(featureIterator.hasNext()){
      //
      //this processes all contents of the set - assemblyfeatures,
      //genes and their child transcripts and exons.
      ((SeqFeature)featureIterator.next()).accept(this);
      append(TagHandler.RETURN);
    }//end while
    
    decrementIndent();
    
    append(getIndentString());
    close(TagHandler.TRANSCRIPT);
    retrn();
  }
  
  public void visit(Exon feature){
    append(getIndentString());
    open(TagHandler.EXON);
    retrn();

    incrementIndent();
    
    wrap(TagHandler.STABLE_ID, feature.getId());
    wrap(TagHandler.START, String.valueOf(feature.getLow()));
    wrap(TagHandler.END, String.valueOf(feature.getHigh()));
    wrap(TagHandler.STRAND, String.valueOf(feature.getStrand()));
    wrap(TagHandler.FRAME, String.valueOf((3-feature.getPhase())%3));
    
    decrementIndent();
    
    append(getIndentString());
    close(TagHandler.EXON);
    retrn();
  }
  
  public void visit(Evidence evidence){
    append(getIndentString());
    open(TagHandler.EVIDENCE);
    retrn();
    
    incrementIndent();
    
    wrap(TagHandler.NAME, evidence.getSetId());
    
    decrementIndent();
    
    append(getIndentString());
    close(TagHandler.EVIDENCE);
    retrn();
  }
  
}//end OtterXMLRenderingVistor


