package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import apollo.datamodel.*;

/**
 * I will create a new Gene when my tag is found. When I am closed, I will
 * add myself to the current GenericAnnotationSet.
**/
public class TranscriptTagHandler extends TagHandler{
  public void handleStartElement(
    OtterContentHandler theContentHandler,
    String namespaceURI,
    String localName,
    String qualifiedName,
    Attributes attributes
  ){
    //
    //should just push the mode - so subsequence tags know we're
    //dealing with a gene.
    super.handleStartElement(
      theContentHandler,
      namespaceURI,
      localName,
      qualifiedName,
      attributes
    );
    
    Transcript transcript = new Transcript();
    
    //
    //pushes annotation on the stack so subsequence tags can 
    //modify it.
    theContentHandler.pushStackObject(transcript);
  }//end handleTag
	
  public void handleEndElement(
    OtterContentHandler theContentHandler,
    String namespaceURI,
    String localName,
    String qualifiedName
  ){

    //
    //should pop the mode off the stack.
    super.handleEndElement(
      theContentHandler,
      namespaceURI,
      localName,
      qualifiedName
    );

    //grab the annotation off the stack, and set it into the 
    //parent sequenceset.
    Transcript transcript = (Transcript)theContentHandler.popStackObject();
    Gene parentGene = (Gene)theContentHandler.getStackObject();
    parentGene.addTranscript(transcript);
    transcript.setRefFeature(parentGene);
    transcript.setType("otter");
    transcript.getGene().setStrand(transcript.getStrand());

    //work out translation coords if there is a translation
    
    String translationStartStr;
    String translationEndStr;
    if ((translationStartStr = transcript.getProperty(TagHandler.TRANSLATION_START)) != null &&
        (translationEndStr = transcript.getProperty(TagHandler.TRANSLATION_END)) != null) {
      int genomicTranslationStartPos = Integer.parseInt(translationStartStr);
      int genomicTranslationEndPos = Integer.parseInt(translationEndStr);
      transcript.setTranslationStart(genomicTranslationStartPos);
      transcript.setTranslationEnd(genomicTranslationEndPos);
      transcript.removeProperty(TagHandler.TRANSLATION_START);
      transcript.removeProperty(TagHandler.TRANSLATION_END);
    } 

  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:gene:transcript";
  }//end getFullName
  
  public String getLeafName() {
    return "transcript";    
  }//end getLeafName
  
}//end TagHandler
