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
public class OtterTagHandler extends TagHandler{
  public String getFullName(){
    return "otter";
  }//end getTag

  public String getLeafName(){
    return "otter";
  }//end getTag
}//end TagHandler
