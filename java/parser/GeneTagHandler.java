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
public class GeneTagHandler extends TagHandler{
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
    
    Gene gene = new Gene();
    
    //
    //pushes annotation on the stack so subsequence tags can 
    //modify it.
    theContentHandler.pushStackObject(gene);
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
    Gene gene = (Gene)theContentHandler.popStackObject();
    ((GenericAnnotationSet)theContentHandler.getCurrentObject()).addFeature(gene);
    gene.setRefFeature((GenericAnnotationSet)theContentHandler.getCurrentObject());
    gene.setHolder(true);
    gene.setType("gene");
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:gene";
  }//end getFullName
  
  public String getLeafName() {
    return "gene";    
  }//end getLeafName
  
}//end TagHandler
