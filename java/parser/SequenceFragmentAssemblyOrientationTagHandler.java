package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import apollo.datamodel.*;

/**
 * I add on the assembly start of the current sequence fragment.
**/
public class SequenceFragmentAssemblyOrientationTagHandler extends TagHandler{

  public void handleCharacters(
    OtterContentHandler theContentHandler,
    char[] text,
    int start,
    int length
  ){
	AssemblyFeature annotation = (AssemblyFeature)theContentHandler.getStackObject();
	String characters = (new StringBuffer()).append(text,start,length).toString();	
	annotation.setStrand(Integer.valueOf(characters).intValue());
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:sequencefragment:assemblyori";
  }//end getTag
  
  public String getLeafName(){
    return "assemblyori";
  }//end getTag
}//end TagHandler
