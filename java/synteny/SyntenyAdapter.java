package apollo.dataadapter.synteny;

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

/**
 * When the user selects "Synteny" from the datachooser menu, I am the
 * adapter that's loaded. Note that all of my hard work is really done
 * by my GUI - SyntenyAdapterGUI. In particular, the data-fetching is
 * run by the doOperation method on the GUI.
**/
public class SyntenyAdapter extends AbstractApolloAdapter{

  //
  //child data adapters keyed by species name.
  private HashMap adapters;
  private SyntenyAdapterGUI theGUI;
  
  IOOperation [] 
    supportedOperations = {
       ApolloDataAdapterI.OP_READ_DATA,
       ApolloDataAdapterI.OP_READ_SEQUENCE
    };

  public void setAdapters(HashMap newValue){
    adapters = newValue;
  }//end setAdapters
  
  public HashMap getAdapters(){
    return adapters;
  }//end getAdapters
  
  public String getName() {
    return "Synteny";
  }

  public String getType() {
    return "Multiple Species and Compara Data";
  }

  public DataInputType getInputType() {
    throw new NotImplementedException("Not yet implemented");
  }
  
  public String getInput() {
    throw new NotImplementedException("Not yet implemented");
  }

  public IOOperation [] getSupportedOperations() {
    return supportedOperations;
  }

  public DataAdapterUI getUI(IOOperation op) {
    if(getGUI() == null){
      setGUI(new SyntenyAdapterGUI(op));
    }
    
    return getGUI();
  }

  public void setRegion(String region) throws DataAdapterException {
    throw new NotImplementedException("Not yet implemented");
  }

  public Properties getStateInformation() {
    Properties props = new Properties();
    return props;
  }

  public void setStateInformation(Properties props) {
  }

  /**
   * Visit each child adapter and ask each one for its CurationSet.
   * combine the results into a composite curation set.
  **/
  public CurationSet getCurationSet() throws DataAdapterException {
    throw new NotImplementedException("Not yet implemented");
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
    throw new NotImplementedException();
  }
  
  public String getRawAnalysisResults(String id) throws DataAdapterException{
    throw new NotImplementedException();
  }

  public void init() {
  }
  
  public class SpeciesConfiguration{
    String name;
    String nameAdaptor;
    
    public String getName(){
      return name;
    }//end getName

    public void setName(String newValue){
      name = newValue;
    }//end setName
    
    public String getNameAdaptor(){
      return nameAdaptor;
    }//end getNameAdaptor

    public void setNameAdaptor(String newValue){
      nameAdaptor = newValue;
    }//end setNameAdaptor
    
  }//end SpeciesConfig
  
  private SyntenyAdapterGUI getGUI(){
    return theGUI;
  }//end getGUI
  
  private void setGUI(SyntenyAdapterGUI newValue){
    theGUI = newValue;
  }//end setSyntenyAdapterGUI
}
