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
import org.ensembl.datamodel.AssemblyLocation;
import org.ensembl.datamodel.Feature;
import org.ensembl.datamodel.FeaturePair;
import org.ensembl.util.*;

import apollo.dataadapter.otter.parser.*;

import Bio.EnsEMBL.*;
import Bio.EnsEMBL.DBSQL.*;
import Bio.EnsEMBL.Compara.DBSQL.*;
import Bio.EnsEMBL.Compara.*;

public class SyntenyComparaAdapter extends EnsJAdapter {
  private SyntenyComparaAdapterGUI theAdapterGUI;
  private String querySpecies;
  private String hitSpecies;
  private int hitStart;
  private int hitEnd;
  private String hitChromosome;
  
  private SyntenyComparaAdapterGUI getGUI(){
    return theAdapterGUI;
  }
  
  private void setGUI(SyntenyComparaAdapterGUI newValue){
    theAdapterGUI = newValue;
  }
  
  public DataAdapterUI getUI(IOOperation op) {
    if(getGUI() != null){
      return getGUI();
    }else{
      setGUI(new SyntenyComparaAdapterGUI(op));
      return getGUI();
    }
  }
  
  public CurationSet getCurationSet(){
    SpeciesConfig speciesConfig = new SpeciesConfig();
    FeatureSetI set3 = null;
    Database compara = speciesConfig.getComparaDatabase();
    MySQLInstance mysql3 = new MySQLInstance(compara.getHost(), compara.getUser(), compara.getPass(), compara.getPort());
    MySQLDatabase db5 = mysql3.fetchDatabaseByName(compara.getName());
    Bio.EnsEMBL.Compara.DBSQL.HomologyAdaptor ha = new Bio.EnsEMBL.Compara.DBSQL.HomologyAdaptor(db5);
    GenomicAlignAdaptor gaa = new GenomicAlignAdaptor(db5);
    Vector dnaDnaFeatures;
    DnaDnaAlignFeature ddaf;

    try{
      mysql3 = 
        new MySQLInstance(
          compara.getHost(),
          compara.getUser(),
          compara.getPass(),
          compara.getPort()
        );

      set3 = 
        ha.fetchBySpeciesAssemblyLocationPair(
          getQuerySpecies(),
          ((AssemblyLocation)getLocation()).getChromosome(),
          getLocation().getStart(),
          getLocation().getEnd(), 
          getHitSpecies(),
          getHitChromosome(),
          getHitStart(),
          getHitEnd()
        );

      dnaDnaFeatures = 
        gaa.fetchDnaDnaAlignsBySpeciesAssemblyLocationHSpecies(
          getQuerySpecies(),
          ((AssemblyLocation)getLocation()).getChromosome(),
          getLocation().getStart(),
          getLocation().getEnd(), 
          getHitSpecies()
        );

      if (set3 == null) {
        set3 = new FeatureSet();
      }

      for (int i = 0; i < dnaDnaFeatures.size(); i++) {
        ddaf = (DnaDnaAlignFeature)dnaDnaFeatures.elementAt(i);
        if (
          ddaf.getName().equals(((AssemblyLocation)getLocation()).getChromosome()) &&
          ddaf.getHname().equals(getHitChromosome())
        ){
          set3.addFeature(ddaf);
        }//end if
      }//end for
    }catch(Exception exception){
      exception.printStackTrace();
      throw new IllegalStateException("Problem with compara");
    }
    
    //
    //do something with set3
    CurationSet curationSet = new CurationSet();
    StrandedFeatureSet featureSet = new StrandedFeatureSet(set3, new FeatureSet());
    curationSet.setResults(featureSet);
    return curationSet;
  }//end getCurationSet
  
  public void setStateInformation(Properties props) {
    
    String logicalSpecies;
    String actualSpecies;
    
    //
    //should set the query's start/end/chr properties
    super.setStateInformation(props);
    //
    //set the hit ranges, species names.
    logicalSpecies = props.getProperty("querySpecies");
    actualSpecies = convertLogicalNameToSpeciesName(logicalSpecies);
    
    setQuerySpecies(actualSpecies);
    
    logicalSpecies = props.getProperty("hitSpecies");
    actualSpecies = convertLogicalNameToSpeciesName(logicalSpecies);
    setHitSpecies(actualSpecies);
    
    setHitStart(Integer.valueOf(props.getProperty("hitStart")).intValue());
    setHitEnd(Integer.valueOf(props.getProperty("hitEnd")).intValue());
    setHitChromosome(props.getProperty("hitChr"));
  }

  public String getQuerySpecies(){
    return querySpecies;
  }
  
  public String getHitSpecies(){
    return hitSpecies;
  }
  
  public int getHitStart(){
    return hitStart;
  }
  
  public int getHitEnd(){
    return hitEnd;
  }

  public String getHitChromosome(){
    return hitChromosome;
  }

  public void setQuerySpecies(String newValue){
    querySpecies = newValue;
  }
  
  public void setHitSpecies(String newValue){
    hitSpecies = newValue;
  }
  
  public void setHitStart(int newValue){
    hitStart = newValue;
  }
  
  public void setHitEnd(int newValue){
    hitEnd = newValue;
  }

  public void setHitChromosome(String newValue){
    hitChromosome = newValue;
  }
  
  /**
   * Use the synteny style to convert from logical to actual species names.
  **/
  private String convertLogicalNameToSpeciesName(String logicalName){
    HashMap speciesNames = 
      Config
        .getStyle("apollo.dataadapter.synteny.SyntenyAdapter")
        .getSyntenySpeciesNames();
    
    Iterator logicalNames = speciesNames.keySet().iterator();
    int index;
    String longName;
    String shortName = null;
    
    while(logicalNames.hasNext()){
      longName = (String)logicalNames.next();
      
      //
      //Convert Name.Human to Human
      index = longName.indexOf(".");
      shortName = longName.substring(index+1);
      
      if(shortName.equals(logicalName)){
        return (String)speciesNames.get(longName);
      }//end if
      
    }//end while
    
    if(true){
      throw new IllegalStateException("No logical species name matches the name input:"+shortName);
    }//end if
      
    return null;
  }//end convertLogicalNameToSpeciesName
  
}





