package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import apollo.datamodel.*;

public class ExonStrandTagHandler extends TagHandler{
  public void handleCharacters(
    OtterContentHandler theContentHandler,
    char[] text,
    int start,
    int length
  ){
    Exon exon = (Exon)theContentHandler.getStackObject();
    String characters = (new StringBuffer()).append(text,start,length).toString();	
    int strand = Integer.valueOf(characters).intValue();
    exon.setStrand(strand);
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:gene:transcript:exon:strand";
  }//end getFullName
  
  public String getLeafName() {
    return "strand";
  }//end getLeafName
}//end TagHandler
