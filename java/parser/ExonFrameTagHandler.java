package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import apollo.datamodel.*;

public class ExonFrameTagHandler extends TagHandler{
  public void handleCharacters(
    OtterContentHandler theContentHandler,
    char[] text,
    int start,
    int length
  ){
    Exon exon = (Exon)theContentHandler.getStackObject();
    String characters = (new StringBuffer()).append(text,start,length).toString();
    if(characters != null && characters.trim().length() >0){
// Convert frame to phase
      exon.setPhase((3-Integer.valueOf(characters).intValue())%3);
    }else{
      exon.setPhase(0);
    }
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:gene:transcript:exon:frame";
  }//end getFullName
  
  public String getLeafName() {
    return "frame";
  }//end getLeafName
}//end TagHandler
