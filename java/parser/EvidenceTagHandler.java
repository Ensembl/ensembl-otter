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
public class EvidenceTagHandler extends TagHandler{
  public void handleStartElement(
    OtterContentHandler theContentHandler,
    String namespaceURI,
    String localName,
    String qualifiedName,
    Attributes attributes
  ){
    super.handleStartElement(
      theContentHandler,
      namespaceURI,
      localName,
      qualifiedName,
      attributes
    );
    
    Evidence evidence = new Evidence("feature id not yet set");
    
    theContentHandler.pushStackObject(evidence);
  }//end handleTag
	
  public void handleEndElement(
    OtterContentHandler theContentHandler,
    String namespaceURI,
    String localName,
    String qualifiedName
  ){

    super.handleEndElement(
      theContentHandler,
      namespaceURI,
      localName,
      qualifiedName
    );

    Evidence evidence = (Evidence)theContentHandler.popStackObject();
    Transcript parentTranscript = (Transcript)theContentHandler.getStackObject();
    parentTranscript.addEvidence(evidence);
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:gene:transcript:evidence";
  }//end getFullName
  
  public String getLeafName() {
    return "evidence";    
  }//end getLeafName
  
}//end TagHandler
