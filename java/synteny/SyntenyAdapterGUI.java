package apollo.dataadapter.synteny;

import java.awt.*;
import java.awt.event.*;
import javax.swing.*;
import java.util.*;
import java.lang.reflect.*;

//import org.apollo.datamodel.*;

import org.bdgp.io.DataAdapter;
import org.bdgp.io.IOOperation;
import org.bdgp.io.DataAdapterRegistry;
import java.util.Properties;
import org.bdgp.swing.AbstractDataAdapterUI;
import org.bdgp.swing.AbstractDataAdapterUI;

import apollo.dataadapter.*;
import apollo.datamodel.*;
import apollo.gui.*;
import apollo.gui.Config;
import apollo.gui.ProxyDialog;
import apollo.gui.EnsemblDbDialog;

public class SyntenyAdapterGUI extends CompositeAdapterUI {

  protected DataAdapter driver;
  protected IOOperation op;

  private Properties props;

  private JButton fullPanelButton;
  
  private FullEnsJDBCSyntenyPanel thePanel;

  public SyntenyAdapterGUI(IOOperation op) {
    super(op);
  }

  /**
   * This sets the SyntenyAdapter as the dataadapter for this GUI. We must
   * propagate this relation down to the children, otherwise none of the
   * GUI's in the child adapters will be connected to the child dataadapers.
  **/
  public void setDataAdapter(DataAdapter driver) {
    Iterator names = getAdapters().keySet().iterator();
    String speciesName;
    AbstractApolloAdapter theAdapter;
    
    this.driver = driver;
    
    while(names.hasNext()){
      speciesName = (String)names.next();
      theAdapter = (AbstractApolloAdapter)getAdapters().get(speciesName);
      
        ((AbstractDataAdapterUI)
          theAdapter
          .getUI(IOOperation.READ)
        ).setDataAdapter(theAdapter);
    }//end while
  }//end setDataAdapter
  
  /**
   * <p>This is called specifically by helpers (like the FullEnsJDBCSyntenyPanel)
   * which need to set values directly into the widgets in its children.
   * -- The point is that we get fed something (currently a SyntenyRegion) from
   * the our invoker (currently the SyntenyMenu). We find the adapter gui's 
   * relevant to the chromosomes on the region and setInput on them, passing
   * in a HashMap of text-field values relevant to each.</p>
   *
   * <p> For instance, when given ranges on Human and Mouse, we will set
   * the Human ranges on the Human adapter, the Mouse ranges on the Mouse
   * adapter, and both ranges on the Human/Mouse adapter. </p>
   *
   * If we get called with anything other than a HashMap, we do nothing.
  **/
  public void setInput(Object input){
    Iterator iterator = getAdapters().values().iterator();
    AbstractDataAdapterUI theUI;
    SyntenyRegion region;
    HashMap nextInput = new HashMap();
    String textValue;
    String logicalQuerySpecies;
    String logicalHitSpecies;
    Iterator adapterNames;
    String adapterName;
    String shortAdapterName;
    int index;
    String comparaName;
    String reverseComparaName;
    
    if(!(input instanceof HashMap)){
      return;
    }//end if
    
    logicalQuerySpecies = (String)((HashMap)input).get("logicalQuerySpecies");
    logicalHitSpecies = (String)((HashMap)input).get("logicalHitSpecies");
    comparaName = logicalQuerySpecies+"-"+logicalHitSpecies;
    reverseComparaName = logicalHitSpecies+"-"+logicalQuerySpecies;
    
    region = (SyntenyRegion)((HashMap)input).get("region");
    
    if(region == null){
      return; //we're not interested if we're passed a null region.
    }

    adapterNames = getAdapters().keySet().iterator();
    
    while(adapterNames.hasNext()){
      adapterName = (String)adapterNames.next();
      //
      //If we match an adapter for the query or hit-species,
      //then set in the range information into the adapter.
      //If we match the compara name (species1-species2) then
      //set up query and hit input simultaneously
      if(
        adapterName.equals(logicalQuerySpecies)
      ){
        nextInput.clear();
        nextInput.put("chr", (String)region.getChromosome1().getDisplayId());
        nextInput.put("start", String.valueOf(region.getStart1()));
        nextInput.put("end", String.valueOf(region.getEnd1()));
        
        theUI = 
          (AbstractDataAdapterUI)
          ((AbstractApolloAdapter)getAdapters().get(adapterName))
            .getUI(IOOperation.READ);

        theUI.setInput(nextInput);
        
      }else if(
        adapterName.equals(logicalHitSpecies)
      ){
        nextInput.clear();
        nextInput.put("chr", (String)region.getChromosome2().getDisplayId());
        nextInput.put("start", String.valueOf(region.getStart2()));
        nextInput.put("end", String.valueOf(region.getEnd2()));
        
        theUI = 
          (AbstractDataAdapterUI)
          ((AbstractApolloAdapter)getAdapters().get(adapterName))
            .getUI(IOOperation.READ);

        theUI.setInput(nextInput);
        
      } else if(
        adapterName.equals(comparaName) ||
        adapterName.equals(reverseComparaName)
      ){
        nextInput.clear();
        nextInput.put("chr", (String)region.getChromosome1().getDisplayId());
        nextInput.put("start", String.valueOf(region.getStart1()));
        nextInput.put("end", String.valueOf(region.getEnd1()));
        nextInput.put("hitChr", (String)region.getChromosome2().getDisplayId());
        nextInput.put("hitStart", String.valueOf(region.getStart2()));
        nextInput.put("hitEnd", String.valueOf(region.getEnd2()));
        
        theUI = 
          (AbstractDataAdapterUI)
          ((AbstractApolloAdapter)getAdapters().get(adapterName))
            .getUI(IOOperation.READ);

        theUI.setInput(nextInput);
      }//end if
    }//end while
    
  }//end setInput

  public void buildGUI(){
    super.buildGUI();
  }
  
  /** 
   * Read the style file for the synteny adapter to get a list of
   * child adapters to insert here.
  **/
  protected Map buildAdapters(){
    Iterator names = 
      Config
        .getStyle("apollo.dataadapter.synteny.SyntenyAdapter")
        .getSyntenySpeciesNames()
        .keySet()
        .iterator();
    
    HashMap properties = 
      Config
        .getStyle("apollo.dataadapter.synteny.SyntenyAdapter")
        .getSyntenySpeciesProperties();
    
    String dataAdapterName;
    String logicalName;
    String dataAdapterKey;
    String shortLogicalName;
    AbstractApolloAdapter dataAdapter;
    Class dataAdapterClass;
    String shortDataAdapterName;
    HashMap returnMap = new HashMap();
    HashMap syntenyProperties;
    int index;
    
    while(names.hasNext()){
      //
      //go from the string Name.Human to the string Human
      logicalName = (String)names.next();
      index = logicalName.indexOf(".");
      shortLogicalName = logicalName.substring(index+1);
      
      dataAdapterKey = "Species."+shortLogicalName+".DataAdapter";
      dataAdapterName = (String)properties.get(dataAdapterKey);
      
      //
      //You cant ask the adapter registry for instances of these
      //adapters - you need to create them fresh! Otherwise you'll 
      //end up reusing instances of the same cached adapter.
      try{
        dataAdapterClass = Class.forName(dataAdapterName);
        dataAdapter = (AbstractApolloAdapter)dataAdapterClass.newInstance();
        //
        //This cryptic step allows the child dataadapter to set this
        //class as its parent (if it wants). See SyntenyComparaAdapter
        dataAdapter.getUI(org.bdgp.io.IOOperation.READ).setInput(this);
      }catch(ClassNotFoundException exception){
        throw new IllegalStateException("cant create data adapter");
      }catch(InstantiationException exception){
        throw new IllegalStateException("cant create data adapter");
      }catch(IllegalAccessException exception){
        throw new IllegalStateException("cant create data adapter");
      }//end try
      
      returnMap.put(shortLogicalName, dataAdapter);
    }//end while
    
    return returnMap;
    
  }
  
  /**
   * Gather properties for each child adapter - prefix each gathered property
   * with the name of the species (so, "myProp" -> "Homo_sapiens:myProp")
   * and then glue all child Properties into one big Properties. Hand out!
  **/
  public Properties getProperties(){
    Properties returnedProperties = new Properties();
    Properties childProperties;
    Properties combinedChildProperties = new Properties();
    Iterator names = getAdapters().keySet().iterator();
    String speciesName;
    Iterator childPropertyNames;
    String childPropertyName;
    
    while(names.hasNext()){
      speciesName = (String)names.next();
      
      childProperties = 
        ((AbstractDataAdapterUI)
        ((AbstractApolloAdapter)getAdapters().get(speciesName))
          .getUI(IOOperation.READ)
        ).getProperties();
      
      childPropertyNames = childProperties.keySet().iterator();
      
      while(childPropertyNames.hasNext()){
        childPropertyName = (String)childPropertyNames.next();
        
        combinedChildProperties.setProperty(
          speciesName+":"+childPropertyName, 
          childProperties.getProperty(childPropertyName)
        );
      }//end while
    }//end while
    
    return combinedChildProperties;
  }//end getProperties
    
  /**
   * <p> Walk each property we've been handed. Strip off the species name at the
   * front of the property, and gather the properties into species-specific
   * groups. </p>
   *
   * <p> Add to these properties the configuration information in the synteny
   * style file for this species (in particular, we'll throw in the query- and
   * hit-species for the compara-adapters we load into the properties list)</p>
   *
   * <p> Call setProperties() on each species' adapter, 
   * passing in the specific groups we've gathered.</p>
  **/
  public void setProperties(Properties combinedProperties){
    String combinedPropertyName;
    Iterator combinedPropertyNames = combinedProperties.keySet().iterator();
    String propertyValue;
    String speciesName;
    String childPropertyName;
    Properties childProperty;
    HashMap childPropertiesMap = new HashMap();
    HashMap syntenyStyleSpeciesProperties;
    int index;
    Iterator adaptorNames;
    Iterator styleKeyIterator;
    String styleKey;
    String styleValue;
    
    while(combinedPropertyNames.hasNext()){
      combinedPropertyName = (String)combinedPropertyNames.next();
      propertyValue = (String)combinedProperties.get(combinedPropertyName);
      index = combinedPropertyName.indexOf(":");
      
      if(index > 0){
        //
        //split out the species name from the property key.
        speciesName = combinedPropertyName.substring(0,index);
        childPropertyName = combinedPropertyName.substring(index+1);
        childProperty = (Properties)childPropertiesMap.get(speciesName);

        //
        //dig out our child Properties from the temporary map. Create if we 
        //have to.
        if(childProperty == null){
          childProperty = new Properties();
          childPropertiesMap.put(speciesName, childProperty);
        }//end if

        childProperty.put(childPropertyName, propertyValue);
      }//end while
    }//end if

    syntenyStyleSpeciesProperties = 
      Config
        .getStyle("apollo.dataadapter.synteny.SyntenyAdapter")
        .getSyntenySpeciesProperties();

    //now set each child property we've set up into its respective adapter.
    adaptorNames = getAdapters().keySet().iterator();
    
    
    while(adaptorNames.hasNext()){
      speciesName = (String)adaptorNames.next();

      childProperty = (Properties)childPropertiesMap.get(speciesName);
      
      //
      //If you've got historical input data for this species, then use it,
      //otherwise proceed with a new Properties.
      if(childProperty == null){
        childProperty = new Properties();
      }

      styleKeyIterator = syntenyStyleSpeciesProperties.keySet().iterator();
      while(styleKeyIterator.hasNext()){
        styleKey = (String)styleKeyIterator.next();

        //e.g., if the entry species.Human-Mouse.querySpecies => Homo_sapiens
        //contains the string Human-Mouse, place the entry 
        //querySpecies => Homo_sapiens into the properties file.
        if(styleKey.indexOf(speciesName)>0){
          index = styleKey.lastIndexOf(".");
          childProperty.put(
            styleKey.substring(index+1),
            syntenyStyleSpeciesProperties.get(styleKey)
          );
        }//end if

      }//end if
      
      ((AbstractDataAdapterUI)
      ((AbstractApolloAdapter)getAdapters().get(speciesName))
        .getUI(IOOperation.READ)
      ).setProperties(childProperty);
    }//end while
  }
  
  /** 
   * The order of the adapters is given by the synteny style's
   * syntenySpeciesOrder vector.
  **/
  protected java.util.List buildAdapterOrder() {
    int index;
    java.util.List syntenySpeciesOrder = 
      Config
        .getStyle("apollo.dataadapter.synteny.SyntenyAdapter")
        .getSyntenyAdapterOrder();
    
    java.util.List newList = new ArrayList();
    for(int i=0; i<syntenySpeciesOrder.size(); i++){
      index = ((String)syntenySpeciesOrder.get(i)).lastIndexOf(".");
      newList.add(((String)syntenySpeciesOrder.get(i)).substring(index+1));
    }//end for
    
    return newList;
  }
  
//end setProperties
}
