package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import apollo.datamodel.*;

/**
 * I add on the assembly start of the current sequence fragment.
**/
public class SequenceSetAuthorTagHandler extends TagHandler{

  public void handleCharacters(
    OtterContentHandler theContentHandler,
    char[] text,
    int start,
    int length
  ){
    GenericAnnotationSet set = (GenericAnnotationSet)theContentHandler.getCurrentObject();
    String characters = (new StringBuffer()).append(text,start,length).toString();	
    //
    //As a GenericAnnotationSet has no author, we will store it on the properties
    //of the set.
    set.addProperty(TagHandler.AUTHOR, characters);
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:author";
  }
  
  public String getLeafName() {
    return "author";
  }
}//end TagHandler
