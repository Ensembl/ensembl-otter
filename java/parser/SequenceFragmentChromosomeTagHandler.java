package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import apollo.datamodel.*;

/**
 * I add on the name of the current sequence fragment.
**/
public class SequenceFragmentChromosomeTagHandler extends TagHandler{

  public void handleCharacters(
    OtterContentHandler theContentHandler,
    char[] text,
    int start,
    int length
  ){
    AssemblyFeature annotation = (AssemblyFeature)theContentHandler.getStackObject();
    String characters = (new StringBuffer()).append(text,start,length).toString();	
    //
    //pushes annotation on the stack so subsequence tags can 
    //modify it.
    annotation.setChromosome(characters);
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:sequencefragment:chromosome";
  }//end getTag
  
  public String getLeafName(){
    return "chromosome";
  }//end getTag
  
}//end TagHandler
