package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import apollo.datamodel.*;

public class TranscriptMRNAStartNotFoundTagHandler extends TagHandler{
  public void handleCharacters(
    OtterContentHandler theContentHandler,
    char[] text,
    int start,
    int length
  ){
    Transcript transcript = (Transcript)theContentHandler.getStackObject();
    String characters = (new StringBuffer()).append(text,start,length).toString();	
    transcript.addProperty(TagHandler.MRNA_START_NOT_FOUND, characters);
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:gene:transcript:mRNA_start_not_found";
  }//end getFullName
  
  public String getLeafName() {
    return "mRNA_start_not_found";
  }//end getLeafName
}//end TagHandler
