package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import apollo.datamodel.*;

/**
 * SequenceSets contain everything with a marker for an author
 * - we map them to apollo GenericAnnotationSets
**/
public class SequenceSetTagHandler extends TagHandler{
  public void handleStartElement(
    OtterContentHandler theContentHandler,
    String namespaceURI,
    String localName,
    String qualifiedName,
    Attributes attributes
  ){
    //
    //should just push the mode - so subsequence tags know we're
	//dealing with a sequence fragment.
    super.handleStartElement(
      theContentHandler,
      namespaceURI,
      localName,
      qualifiedName,
      attributes
    );
    
    GenericAnnotationSet annotationSet = new GenericAnnotationSet();
    //sets the current object slot in the handler to hold the annotation set.
    theContentHandler.setCurrentObject(annotationSet);
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
	
    theContentHandler.addReturnedObject(theContentHandler.getCurrentObject());
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset";
  }//end getTag

  public String getLeafName(){
    return "sequenceset";
  }//end getTag
  
}//end TagHandler
