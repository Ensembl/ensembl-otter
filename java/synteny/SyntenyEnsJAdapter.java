package apollo.dataadapter.synteny;

import java.util.*;
import java.io.*;
import apollo.seq.io.*;
import apollo.datamodel.*;
import apollo.gui.schemes.*;
import apollo.gui.Config;
import apollo.dataadapter.*;
import apollo.dataadapter.ensj.*;

import org.bdgp.io.*;
import org.bdgp.util.*;
import java.util.Properties;
import org.bdgp.swing.widget.*;
import org.apache.log4j.*;

import org.ensembl.*;
import org.ensembl.driver.*;
import org.ensembl.query.*;
import org.ensembl.datamodel.Accessioned;
import org.ensembl.datamodel.Location;
import org.ensembl.datamodel.LinearLocation;
import org.ensembl.datamodel.AssemblyLocation;
import org.ensembl.datamodel.CloneFragmentLocation;
import org.ensembl.datamodel.CompositeCloneFragmentLocation;
import org.ensembl.datamodel.CloneFragment;
import org.ensembl.datamodel.DnaProteinAlignment;
import org.ensembl.datamodel.PredictionTranscript;
import org.ensembl.datamodel.PredictionExon;
import org.ensembl.datamodel.SimplePeptideFeature;
import org.ensembl.datamodel.Feature;
import org.ensembl.datamodel.RepeatFeature;
import org.ensembl.util.*;

import apollo.dataadapter.otter.parser.*;

import org.xml.sax.*;
import org.xml.sax.ext.*;
import org.xml.sax.helpers.*;
import org.xml.sax.helpers.DefaultHandler;


public class SyntenyEnsJAdapter extends EnsJAdapter {
  
  private SyntenyEnsJAdapterGUI theAdapterGUI;
  private InputStream inputStream;
  private OutputStream outputStream;

  public String getName() {
    return "Synteny/Otter EnsemblJava";
  }


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
    * @return object graph containing genes, transcripts and exons from the currently
    * specified region as apollo annotation objects.  */
  protected FeatureSetI getAnnotatedRegion()
  throws apollo.dataadapter.DataAdapterException 
  {

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
      throw new apollo.dataadapter.DataAdapterException("IO Error parsing input xml-stream", theException);
    }catch(SAXException theException){
      throw new apollo.dataadapter.DataAdapterException("SAX Error parsing input xml-stream", theException);
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
      
      theResultFeature.setType("otter");
      returnSet.addFeature(theResultFeature);
    }//end while
    
    returnSet.setLow(low);
    returnSet.setHigh(high);
    returnSet.setHolder(true);
    
    return returnSet;
  }//end getAnnotatedRegion
  
  private SyntenyEnsJAdapterGUI getGUI(){
    return theAdapterGUI;
  }
  
  private void setGUI(SyntenyEnsJAdapterGUI newValue){
    theAdapterGUI = newValue;
  }
  
  public DataAdapterUI getUI(IOOperation op) {
    if(getGUI() != null){
      return getGUI();
    }else{
      setGUI(new SyntenyEnsJAdapterGUI(op));
      return getGUI();
    }
  }
  
  public void commitChanges(CurationSet curationSet)
  throws apollo.dataadapter.DataAdapterException {
    BufferedOutputStream buffer = new BufferedOutputStream(getOutputStream());
    OutputStreamWriter writer = new OutputStreamWriter(buffer);
    OtterXMLRenderingVisitor visitor = new OtterXMLRenderingVisitor();
    FeatureSetI theSet = curationSet.getAnnots();
    theSet.accept(visitor);
    String outputString = visitor.getReturnBuffer().toString();
    try{
      writer.write(outputString);
    }catch(IOException theException){
      throw new apollo.dataadapter.DataAdapterException("Error writing annotations",theException);
    }//end try
  }
    
  /**
   * In addition to superclass processing,
   * We will be passed otter-i/o file names. Create file handles from these.
  **/
  public void setStateInformation(Properties stateInformation){
    super.setStateInformation(stateInformation);
    
    String inputFileName = stateInformation.getProperty("otterInputFile");
    String outputFileName = stateInformation.getProperty("otterOutputFile");
    File outputFile;
    
    try{
      inputStream = new FileInputStream(inputFileName);
    }catch(FileNotFoundException theException){
      throw new IllegalStateException("File "+inputFileName+" not found");
    }//end try
    
    outputFile = new File(outputFileName);
    
    if(outputFile.exists()){
      outputFile.delete();
    }//end if
    
    try{
      outputFile.createNewFile();
      outputStream = new FileOutputStream(outputFile);
    }catch(IOException theException){
      throw new IllegalStateException("Unable to create output file "+outputFileName);
    }//end try
    
  }//end setStateInformation

}





