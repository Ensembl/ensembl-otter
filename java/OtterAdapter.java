package apollo.dataadapter.otter;

import java.util.*;
import java.io.*;
import apollo.seq.io.*;
import apollo.datamodel.*;
import apollo.gui.schemes.*;
import apollo.gui.Config;

import org.bdgp.io.IOOperation;
import org.bdgp.io.DataAdapterUI;
import org.bdgp.util.*;
import java.util.Properties;
import org.bdgp.swing.widget.*;
import apollo.dataadapter.*;
import apollo.dataadapter.otter.parser.*;

import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;


public class OtterAdapter extends AbstractApolloAdapter {

  IOOperation [] 
    supportedOperations = {
       ApolloDataAdapterI.OP_READ_DATA,
       ApolloDataAdapterI.OP_READ_SEQUENCE,
       ApolloDataAdapterI.OP_WRITE_DATA
    };

  private String[] speciesNames = {"mouse", "human"};
  
  private HashMap speciesConfiguration = new HashMap();
  
  private InputStream inputStream;
  private OutputStream outputStream;
  
  public OtterAdapter() {
    
  }//end SyntenyAdapter

  public InputStream getInputStream(){
    return inputStream;
  }//end getInputStream

  public void setInputStream(InputStream newValue){
    inputStream = newValue;
  }//end setInputStream
  

  public OutputStream getOutputStream(){
    return outputStream;
  }//end getOutputStream

  public void setOutputStream(OutputStream newValue){
    outputStream = newValue;
  }//end setOutputStream
  
  /**
   * Process the style file for the synteny adaptor
   * so we can read species-specific things like 
   * databases, name adaptors ets. We'll keep an inner
   * class to hang onto each species efficiently, and 
   * store all inner classes by name in a hashmap.
  **/
  private void processSpeciesConfigurations(){
  }//end processSpeciesConfigurations
  
  public String getName() {
    return "Otter";
  }

  public String getType() {
    return "Otter Annotations";
  }

  public DataInputType getInputType() {
    return DataInputType.FILE;
  }
  
  public String getInput() {
    return null;
  }

  public IOOperation [] getSupportedOperations() {
    return supportedOperations;
  }

  public DataAdapterUI getUI(IOOperation op) {
    return new OtterAdapterGUI(op);
  }

  public void setRegion(String region) throws DataAdapterException {
    throw new NotImplementedException("Not yet implemented");
  }

  public Properties getStateInformation() {
    Properties props = new Properties();
    return props;
  }

  public void setStateInformation(Properties props) {
  }//end setStateInformation

  /**
   * These annotations will be read in from the input stream
   * passed into this adapter. They are in otter-xml format, 
   * which will be parsed into a GenericAnnotationSet.
  **/
  private StrandedFeatureSetI getAnnotations(){
    XMLReader parser;
    OtterContentHandler handler;
    InputSource theFileReader;
    GenericAnnotationSet theSet;
    StrandedFeatureSet returnSet;
    Iterator featureIterator;
    SeqFeatureI theResultFeature;
    int low = -1; //lower bound for annotation set
    int high = -1; //upper bound for annotation set
    
    try{
      parser = XMLReaderFactory.createXMLReader();
      handler = new OtterContentHandler();
      theFileReader = new InputSource(getInputStream());
      parser.setContentHandler(handler);
      parser.parse(theFileReader);
    }catch(IOException theException){
      theException.printStackTrace();
      System.out.println(theException);
      throw new IllegalStateException("Error parsing input xml-stream");
    }catch(SAXException theException){
      theException.printStackTrace();
      System.out.println(theException);
      throw new IllegalStateException("Error parsing input xml-stream");
    }//end try
    
    theSet = (GenericAnnotationSet)handler.getReturnedObjects().iterator().next();  

    returnSet = 
      new StrandedFeatureSet(
        new GenericAnnotationSet(), 
        new GenericAnnotationSet()
      );
    
    featureIterator = theSet.getFeatures().iterator();
    while(featureIterator.hasNext()){
      theResultFeature = (SeqFeatureI)featureIterator.next();
      if(low > theResultFeature.getLow() || low < 0){
        low = theResultFeature.getLow();
      }
      if(high < theResultFeature.getHigh() || high < 0){
        high = theResultFeature.getHigh();
      }
      
      //theResultFeature.setType("otter");
      returnSet.addFeature(theResultFeature);
    }//end while
    
    returnSet.setLow(low);
    returnSet.setHigh(high);
    
    return returnSet;
  }//end getAnnotations
  
  public CurationSet getCurationSet() throws DataAdapterException {
    CurationSet curationSet = new CurationSet();
    StrandedFeatureSetI annotations = getAnnotations();
    
    curationSet.setAnnots(annotations);
    
    curationSet.setResults(new StrandedFeatureSet(new FeatureSet(), new FeatureSet()));
    
    curationSet.setLow(annotations.getLow());
    curationSet.setHigh(annotations.getHigh());
    return curationSet;
  }//end getCurationSet

  
  private void setSequence(SeqFeatureI sf, CurationSet curationSet) {
    throw new NotImplementedException("Not yet implemented");
  }

  public SequenceI getSequence(String id) throws DataAdapterException {
    throw new NotImplementedException();
  }
  public SequenceI getSequence(DbXref dbxref) throws DataAdapterException{
    throw new NotImplementedException("Not yet implemented");
  }

  public SequenceI getSequence(
    DbXref dbxref, 
    int start, 
    int end
  ) throws DataAdapterException {
    throw new NotImplementedException();
  }

  public Vector getSequences(DbXref[] dbxref) throws DataAdapterException{
    throw new NotImplementedException();
  }
  
  public Vector getSequences(
    DbXref[] dbxref, 
    int[] start, 
    int[] end
  ) throws DataAdapterException{
    throw new NotImplementedException();
  }
  
  public void commitChanges(CurationSet curationSet) throws DataAdapterException {
    BufferedOutputStream buffer = new BufferedOutputStream(getOutputStream());
    OutputStreamWriter writer = new OutputStreamWriter(buffer);
    OtterXMLRenderingVisitor visitor = new OtterXMLRenderingVisitor();
    FeatureSetI theSet = curationSet.getAnnots();
    theSet.accept(visitor);
    String outputString = visitor.getReturnBuffer().toString();
    try{
      writer.write(outputString);
    }catch(IOException theException){
      throw new DataAdapterException("Error writing annotations",theException);
    }//end try
  }
  
  public String getRawAnalysisResults(String id) throws DataAdapterException{
    throw new NotImplementedException();
  }

  public void init() {
  }
}
