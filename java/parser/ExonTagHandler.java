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
public class ExonTagHandler extends TagHandler{
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
    
    Exon exon = new Exon();
    
    theContentHandler.pushStackObject(exon);
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

    Exon exon = (Exon)theContentHandler.popStackObject();
    Transcript parentTranscript = (Transcript)theContentHandler.getStackObject();
    parentTranscript.addExon(exon);
    exon.setRefFeature(parentTranscript);
    exon.getTranscript().setStrand(exon.getStrand());
    exon.setType("otter");
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:gene:transcript:exon";
  }//end getFullName
  
  public String getLeafName() {
    return "exon";    
  }//end getLeafName
  
}//end TagHandler
