package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import java.io.*;
import java.util.*;
import apollo.datamodel.*;


/**
 * <p>I am the ContentHandler used when <code>SyntenyAdaptor</code> parses
 * the result of a call for annotations on the synteny regions in question.</p>
 *
 * @author Vivek Iyer
**/
public class 
	OtterContentHandler 
extends 
	DefaultHandler 
{

  private Stack modeStack = new Stack();
  private Stack objectStack = new Stack();
  private List returnedObjects = new ArrayList();
  private Map tagMap = new HashMap();
  private String nestedName;
  
  private Object currentObject;
  
  public OtterContentHandler() {
    TagHandler tagHandler = new OtterTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new SequenceSetTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);
    
    tagHandler = new SequenceSetAuthorTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new SequenceFragmentTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);
    
    tagHandler = new SequenceFragmentIdTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new SequenceFragmentChromosomeTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);
    
    tagHandler = new SequenceFragmentAssemblyStartTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);
    
    tagHandler = new SequenceFragmentAssemblyEndTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);
    
    tagHandler = new SequenceFragmentAssemblyOffsetTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);
    
    tagHandler = new SequenceFragmentAssemblyOrientationTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);
    
    tagHandler = new GeneTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new GeneAuthorTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new GeneSynonymTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new GeneAuthorEmailTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new GeneStableIdTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new GeneRemarkTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new GeneNameTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new TranscriptTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new TranscriptNameTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new TranscriptCdsEndNotFoundTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new TranscriptCdsStartNotFoundTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new TranscriptMRNAStartNotFoundTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new TranscriptMRNAEndNotFoundTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new TranscriptTranslationStartTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new TranscriptTranslationEndTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new TranscriptRemarkTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new TranscriptStableIdTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new TranscriptClassTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new EvidenceTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new EvidenceNameTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new EvidenceTypeTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new ExonStableIdTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new ExonTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new ExonStartTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new ExonEndTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new ExonStrandTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

    tagHandler = new ExonFrameTagHandler();
    addTagMapping(tagHandler.getFullName(), tagHandler);

  }//end OtterContentHandler

  private String getNestedName(){
    return nestedName;
  }//end getNestedName

  private void setNestedName(String name){
    nestedName = name;
  }//end setNestedName

  public Map getTagMap(){
    return tagMap;
  }//end getTagMap
  
  private void addTagMapping(String tag, TagHandler tagHandler){
    getTagMap().put(tag, tagHandler);
  }//end addTagMapping
  
  private TagHandler getTagHandlerForTag(String tag){
    return (TagHandler)getTagMap().get(tag);
  }//end getTagHandlerForTag
  
  public Object getCurrentObject(){
    return currentObject;
  }//end getCurrentObject

  public void setCurrentObject(Object theObject) {
    currentObject = theObject;
  }//end setCurrentObject

  public void addReturnedObject(Object theObject) {
    getReturnedObjects().add(theObject);
  }//end addObject

  public List getReturnedObjects() {
    return returnedObjects;
  }//end getReturnedObject

  public Stack getObjectStack() {
    return objectStack;
  }//end getObjectStack

  public void pushStackObject(Object theObject) {
    getObjectStack().push(theObject);
  }//end setObject

  public Object getStackObject() {
    if(!getObjectStack().isEmpty()) {
      return (Object)getObjectStack().peek();
    } else {
      return null;
    }//end if
  }//end getObject

  public Object popStackObject() {
    if(!getObjectStack().isEmpty()) {
      return getObjectStack().pop();
    }//end if
    
    return null;
  }//end closeObject

  public Stack getModeStack() {
    return modeStack;
  }//end getModeStack

  public void setMode(TagHandler theMode) {
    getModeStack().push(theMode);
    String nestedName;
    if(getNestedName() != null){
      setNestedName(getNestedName()+":"+theMode.getLeafName());
    }else{
      setNestedName(theMode.getLeafName());
    }//end if
  }//end setMode

  public TagHandler getMode() {
    if(!getModeStack().isEmpty()) {
      return (TagHandler)getModeStack().peek();
    } else {
      return null;
    }//end if
  }//end getMode

  public void closeMode() {
    if(!getModeStack().isEmpty()) {
      getModeStack().pop();
    }//end if
    
    String nestedName = getNestedName();
    int separatorIndex;
    if(nestedName != null){
      separatorIndex = nestedName.lastIndexOf(":");
      if(separatorIndex > 0){
        String name = nestedName.substring(0, separatorIndex);
        setNestedName(name);
      }else{
        setNestedName(null);
      }
    }//end if
  }//end closeMode

  private void checkTagNames(String fullName, String leafName){
    int colonIndex = fullName.lastIndexOf(":");
    String calculatedLeafName;
    if(colonIndex > 0){
      calculatedLeafName = fullName.substring(colonIndex+1); 
    }else{
      calculatedLeafName = fullName;
    }
    
    if(!calculatedLeafName.equals(leafName)){
      throw new IllegalStateException("inconsistent tag: "+fullName+"-"+leafName);
    }//end if
  }
  public void startElement(
    String namespaceURI,
    String localName,
    String qualifiedName,
    Attributes attributes
  ) throws SAXException {
    String uniqueLocalName;
    GenericTagHandler genericTagHandler;
    
    if(getNestedName()!=null){
       uniqueLocalName = getNestedName()+":"+localName;
    }else{
      uniqueLocalName = localName;
    }//end if
    
    TagHandler matchedTag = getTagHandlerForTag(uniqueLocalName);

    if(matchedTag != null){
        
        checkTagNames(matchedTag.getFullName(), matchedTag.getLeafName());
        
        matchedTag.handleStartElement(
          this,
          namespaceURI,
          localName,
          qualifiedName,
          attributes
        );
	  }/* else{
      //
      //Create a generic tag labelled by the fully qualified 
      //name at this point - e.g. sequenceset:sequencefragment:remark
      genericTagHandler = new GenericTagHandler(uniqueLocalName);
      genericTagHandler.handleStartElement(
        this,
        namespaceURI,
        localName,
        qualifiedName,
        attributes
      );
    }//end if */
  }//end startElement
  
  public void endElement(
    String namespaceURI,
    String localName,
    String qualifiedName
  ) throws SAXException {
	
    String nestedName = getNestedName();
    String leafPartOfNestedName = null;
    String uniqueLocalName;
    GenericTagHandler genericTagHandler;
    int separatorIndex = nestedName.lastIndexOf(":");
    TagHandler matchedTag;
    
    if(nestedName !=null){
      if(separatorIndex > 0){
        leafPartOfNestedName = nestedName.substring(separatorIndex+1);
      }else{
        leafPartOfNestedName = nestedName;
      }//end if
      
      uniqueLocalName = getNestedName();
    }else{
      uniqueLocalName = localName;
    }//end if
    
    //a close operation only makes sense if the tag that's closing is in fact
    //closing the "current" mode. That is, if the closing tag is the last one that
    //was added to the stack of modes. This is the check for that. Failure of this
    //check means we're dealing with a closing tag we don't recognise, and we just ignore it!
    if(!leafPartOfNestedName.equals(localName)){
      return;
    }//end if
    
    matchedTag = getTagHandlerForTag(uniqueLocalName);

    if(matchedTag != null){
        matchedTag.handleEndElement(
          this,
          namespaceURI,
          localName,
          qualifiedName
        );
    }/*else{
      //
      //Remove the generic tag from the mode stack. This should also
      //remove the name off the end of the nested name.
      genericTagHandler = new GenericTagHandler(uniqueLocalName);
      genericTagHandler.handleEndElement(
        this,
        namespaceURI,
        localName,
        qualifiedName
      );
    }//end if//end if */
  }//end endElement


  public void characters(
    char[] text,
    int start,
    int length
  )throws SAXException {
    TagHandler matchedTag = getMode();
    if(matchedTag != null){
        matchedTag.handleCharacters(
          this,
          text,
          start,
          length
        );
    }//end if
  }//end characters

  public static void main(String[] args){
    try {
      XMLReader parser = XMLReaderFactory.createXMLReader();
      OtterContentHandler handler = new OtterContentHandler();
      InputSource theFileReader = new InputSource(new FileReader(args[0]));
      parser.setContentHandler(handler);
      parser.parse(theFileReader);
      GenericAnnotationSet theSet = (GenericAnnotationSet)handler.getReturnedObjects().iterator().next();
      //System.out.println("Displaytool output: ");
      //apollo.dataadapter.debug.DisplayTool.showFeatureSet((FeatureSetI)theSet);

      System.out.println("Otter string: ");
      OtterXMLRenderingVisitor visitor = new OtterXMLRenderingVisitor();
      theSet.accept(visitor);
      String string = visitor.getReturnBuffer().toString();

      System.out.println(string);
      System.out.println("Finished otter string: ");
    }catch (Exception e) {
      e.printStackTrace();
    }//end try
  }//end main
}//end DASHandler
