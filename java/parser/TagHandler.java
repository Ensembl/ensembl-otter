package apollo.dataadapter.otter.parser;
import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;


/**
 * General superclass of the command-objects
 * which are used by the OtterContentHandler.
**/
public abstract class TagHandler {
  
  public static String LEFT = "<";
  public static String RIGHT = ">";
  public static String SLASH = "/";
  public static String OTTER = "otter";
  public static String SEQUENCE_SET = "sequence_set";
  public static String INDENT = "  ";
  public static String RETURN = "\n";
  
  public static String AUTHOR ="author";
  public static String AUTHOR_EMAIL ="author_email";
  
  public static String SEQUENCE_FRAGMENT ="seqencefragment";
  public static String NAME ="name";
  public static String ID ="id";
  public static String CHROMOSOME ="chromosome";
  public static String ASSEMBLY_START ="assemblystart";
  public static String ASSEMBLY_END ="assemblyend";
  public static String ASSEMBLY_ORI ="assemblyori";
  public static String ASSEMBLY_OFFSET ="assemblyoffset";
  
  public static String GENE = "gene";
  public static String STABLE_ID = "stable_id";
  public static String REMARK = "remark";
  public static String SYNONYM = "synonym";
  
  public static String TRANSCRIPT = "transcript";
  public static String CDS_START_NOT_FOUND = "cds_start_not_found";
  public static String CDS_END_NOT_FOUND = "cds_end_not_found";
  public static String MRNA_START_NOT_FOUND = "mRNA_start_not_found";
  public static String MRNA_END_NOT_FOUND = "mRNA_end_not_found";
  public static String TRANSLATION_START = "translation_start";
  public static String TRANSLATION_END = "translation_end";
  public static String TRANSCRIPT_CLASS = "transcript_class";
  
  public static String EXON = "exon";
  public static String START = "start";
  public static String END = "end";
  public static String FRAME = "frame";
  public static String STRAND = "strand";
  
  public static String EVIDENCE = "evidence";
  public static String TYPE = "type";
  
  public void handleStartElement(
    OtterContentHandler theContentHandler,
    String namespaceURI,
    String localName,
    String qualifiedName,
    Attributes attributes
  ){
    theContentHandler.setMode(this);
  }//handleStartElement
	
  public void handleEndElement(
    OtterContentHandler theContentHandler,
    String namespaceURI,
    String localName,
    String qualifiedName
  ){
    theContentHandler.closeMode();
  }

  public void handleCharacters(
    OtterContentHandler theContentHandler,
    char[] text,
    int start,
    int length
  ){
  }//end handleTag

  public abstract String getFullName();
  
  public abstract String getLeafName();
}//end TagHandler
