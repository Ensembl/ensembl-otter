package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import apollo.datamodel.*;

/**
 * SequenceFragments will be mapped to Apollo GenericAnnotations: this handler
 * will create a new GenericAnnotation when the start tag is found, set its
 * attributes as each subcomponent is found (assemblystart etc) and 
 * add it to the set of sequence fragments (of the geneset) when
 * the end tag is hit.
**/
public class SequenceFragmentTagHandler extends TagHandler{
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
    
    AssemblyFeature sequenceFragment = new AssemblyFeature();
    //
    //pushes annotation on the stack so subsequence tags can 
    //modify it.
    theContentHandler.pushStackObject(sequenceFragment);
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
    AssemblyFeature sequenceFragment = (AssemblyFeature)theContentHandler.popStackObject();
    ((GenericAnnotationSet)theContentHandler.getCurrentObject()).addFeature(sequenceFragment);
  }//end handleTag


  public String getFullName(){
    return "otter:sequenceset:sequencefragment";
  }
  
  public String getLeafName() {
    return "sequencefragment";    
  }
  
//end getTag
}//end TagHandler
