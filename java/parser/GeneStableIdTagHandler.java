package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import apollo.datamodel.*;

/**
 * I add on the assembly start of the current sequence fragment.
**/
public class GeneStableIdTagHandler extends TagHandler{

  public void handleCharacters(
    OtterContentHandler theContentHandler,
    char[] text,
    int start,
    int length
  ){
    Gene gene = (Gene)theContentHandler.getStackObject();
    String characters = (new StringBuffer()).append(text,start,length).toString();	
    gene.setDescription(characters);
    gene.setId(characters);
    gene.setName(characters);
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:gene:stable_id";
  }
  
  public String getLeafName() {
    return "stable_id";
  }
}//end TagHandler
