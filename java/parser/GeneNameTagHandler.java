package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import apollo.datamodel.*;

public class GeneNameTagHandler extends TagHandler{

  public void handleCharacters(
    OtterContentHandler theContentHandler,
    char[] text,
    int start,
    int length
  ){
    Gene gene = (Gene)theContentHandler.getStackObject();
    String characters = (new StringBuffer()).append(text,start,length).toString();	
    DbXref dbx = new DbXref("OtterName",characters,"otter");
    gene.addDbXref(dbx);
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:gene:name";
  }
  
  public String getLeafName() {
    return "name";
  }
}//end TagHandler
