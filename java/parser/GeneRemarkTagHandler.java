package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;
import apollo.datamodel.*;

public class GeneRemarkTagHandler extends TagHandler{

  public void handleCharacters(
    OtterContentHandler theContentHandler,
    char[] text,
    int start,
    int length
  ){
    Gene gene = (Gene)theContentHandler.getStackObject();
    String characters = (new StringBuffer()).append(text,start,length).toString();
    Comment comment = 
      new Comment(
        gene.getId(),
        characters,
        "no author",
        "no author id",
        0 //should be a long representing a timestamp.
      );
    gene.addComment(comment);
  }//end handleTag

  public String getFullName(){
    return "otter:sequenceset:gene:remark";
  }//end getFullName
  
  public String getLeafName() {
    return "remark";
  }//end getLeafName
}//end TagHandler
