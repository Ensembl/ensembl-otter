package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import apollo.datamodel.*;

public class EvidenceNameTagHandler extends TagHandler{
  public void handleCharacters(
    OtterContentHandler theContentHandler,
    char[] text,
    int start,
    int length
  ){
    Evidence evidence = (Evidence)theContentHandler.getStackObject();
    String characters = (new StringBuffer()).append(text,start,length).toString();	
    evidence.setSetId(characters);
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:gene:transcript:evidence:name";
  }//end getFullName
  
  public String getLeafName() {
    return "name";
  }//end getLeafName
}//end TagHandler
