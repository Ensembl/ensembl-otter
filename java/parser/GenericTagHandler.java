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
public class GenericTagHandler extends TagHandler{
  String name;
  
  public GenericTagHandler(String newValue){
    name = newValue;
  }//end GenericTagHandler


  public String getFullName(){
    return name;
  }//end getFullName

  public String getLeafName(){
    return name;
  }//end getLeafName
}//end TagHandler
