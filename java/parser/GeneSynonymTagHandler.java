package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import apollo.datamodel.*;

public class GeneSynonymTagHandler extends TagHandler{

  public void handleCharacters(
    OtterContentHandler theContentHandler,
    char[] text,
    int start,
    int length
  ){
    Gene gene = (Gene)theContentHandler.getStackObject();
    String characters = (new StringBuffer()).append(text,start,length).toString();	
    gene.addSynonym(characters);
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:gene:synonym";
  }
  
  public String getLeafName() {
    return "synonym";
  }
}//end TagHandler
