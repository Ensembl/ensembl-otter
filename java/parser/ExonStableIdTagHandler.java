package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import apollo.datamodel.*;

public class ExonStableIdTagHandler extends TagHandler{
  public void handleCharacters(
    OtterContentHandler theContentHandler,
    char[] text,
    int start,
    int length
  ){
    Exon exon = (Exon)theContentHandler.getStackObject();
    String characters = (new StringBuffer()).append(text,start,length).toString();	
    exon.setId(characters);
    exon.setName(characters);
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:gene:transcript:exon:stable_id";
  }//end getFullName
  
  public String getLeafName() {
    return "stable_id";
  }//end getLeafName
}//end TagHandler
