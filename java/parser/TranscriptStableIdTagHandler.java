package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import apollo.datamodel.*;

public class TranscriptStableIdTagHandler extends TagHandler{
  public void handleCharacters(
    OtterContentHandler theContentHandler,
    char[] text,
    int start,
    int length
  ){
    Transcript transcript = (Transcript)theContentHandler.getStackObject();
    String characters = (new StringBuffer()).append(text,start,length).toString();	
    transcript.setDescription(characters);
    transcript.setId(characters);
    transcript.setName(characters);
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:gene:transcript:stable_id";
  }//end getFullName
  
  public String getLeafName() {
    return "stable_id";
  }//end getLeafName
}//end TagHandler
