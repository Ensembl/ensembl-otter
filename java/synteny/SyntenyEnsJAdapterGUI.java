package apollo.dataadapter.synteny;


import java.awt.*;
import java.awt.event.*;
import javax.swing.*;
import javax.swing.border.*;
import java.util.*;
import java.io.*;

import apollo.datamodel.*;
import apollo.dataadapter.*;
import apollo.dataadapter.ensj.*;

import org.bdgp.io.*;
import java.util.Properties;
import org.bdgp.swing.AbstractDataAdapterUI;

import apollo.datamodel.CurationSet;
import apollo.datamodel.GenomicRange;
import apollo.gui.*;

import org.ensembl.util.*;
import org.ensembl.gui.*;
import org.ensembl.driver.*;


public class SyntenyEnsJAdapterGUI extends EnsJAdapterGUI {

  private JLabel chrLabel = new JLabel("Chr");
  private JLabel startLabel = new JLabel("Start");
  private JLabel endLabel = new JLabel("End");
  
  private JLabel inputFileLabel;
  private JTextField  inputFileField;
  private JLabel outputFileLabel;
  private JTextField outputFileField;
  private String inputFileName;
  private String outputFileName;
  
  private FileChooserWithHistory inputFileChooser;
  private FileChooserWithHistory outputFileChooser;
  private Vector inputFileVector = new Vector();
  private Vector outputFileVector = new Vector();
  
  public SyntenyEnsJAdapterGUI(IOOperation op) {
    super(op);
  }

  public String getInputFileName(){
    return inputFileName;
  }//end getInputFileName
  
  public void setInputFileName(String newValue){
    inputFileName = newValue;
  }//end setInputFileName
  
  public String getOutputFileName(){
    return outputFileName;
  }//end getOutputFileName
  
  public void setOutputFileName(String newValue){
    outputFileName = newValue;
  }//end setOutputName

  private FileChooserWithHistory getInputFileChooser(){
    return inputFileChooser;
  }//end getInputFileChooser

  private FileChooserWithHistory getOutputFileChooser(){
    return outputFileChooser;
  }//end getOutputFileChooser

  private JPanel buildOtterPanel(){
    JPanel returnPanel = new JPanel();
    returnPanel.setBorder(new TitledBorder("Otter Annotations"));
    inputFileChooser = new FileChooserWithHistory("Input file", new Vector(), this);
    outputFileChooser = new FileChooserWithHistory("Output file", new Vector(), this);
    
    returnPanel.setLayout(new GridBagLayout());
    returnPanel.add(getInputFileChooser(), makeConstraintAt(1,0,1));
    returnPanel.add(getOutputFileChooser(), makeConstraintAt(1,1,1));
    return returnPanel;
  }//end buildOtterPanel

  protected void buildGUI() {
    super.buildGUI();
    add( buildOtterPanel() );
  }

  public Object doOperation(Object values) throws org.bdgp.io.DataAdapterException {
    Object curationSet = super.doOperation(values);
    return curationSet;
  }

  /**
   * We make sure (in addition to the superclass's setStateInfo) that
   * we have added the names of the chosen otter input and output files.
  **/
  public Properties createStateInformation(){
    Properties stateInfo = super.createStateInformation();
    stateInfo.setProperty("region", getSelectedChrStartEnd());
    stateInfo.setProperty("otterInputFile", getInputFileChooser().getSelected());
    stateInfo.setProperty("otterOutputFile", getOutputFileChooser().getSelected());
    return stateInfo;
  }//end createStateInformation
  
  /**
   * Assume that the input is a HashMap, and use it to set values into
   * the chromosome and high/low text fields
  **/
  public void setInput(Object input) {
    HashMap theInput;
    String text;
    JTextField textField;
    
    if(!(input instanceof HashMap)){
      return;
    }//end if
    
    theInput = (HashMap)input;
    text = (String)theInput.get("chr");
    textField = getChrTextBox();
    textField.setText(text);
    
    text = (String)theInput.get("start");
    getStartTextBox().setText(text);
    
    text = (String)theInput.get("end");
    getEndTextBox().setText(text);
  }//end setInput
  
  protected GridBagConstraints makeConstraintAt(
    int x,
    int y,
    int width
  ) {
    GridBagConstraints gbc = new GridBagConstraints();
    gbc.gridx = x;
    gbc.gridy = y;
    gbc.gridwidth = width;
    gbc.gridheight = 1;
    gbc.weightx = 0.0;
    gbc.weighty = 0.0;
    gbc.anchor = GridBagConstraints.WEST;
    gbc.fill = GridBagConstraints.NONE;
    gbc.insets = new Insets(0, 0, 0, 0);
    return gbc;
  }//end makeConstraintAt

  /**
   * <p>This method is run to capture the state of the GUI. It returns all GUI-state -
   * the contents of the fields, as well as the history vectors in the fields. </p>
   * 
   * <p> It is run when the adapter gui has successfully read data once (to
   * write out the history file, as well as keep state information to help with
   * navigation)</p>
   * 
   * <p> In addition to the superclass method's work, this method writes out the otter
   * file information and history.</p>
  **/
  public Properties getProperties(){
    Properties properties = super.getProperties();
    String fileName = getInputFileChooser().getSelected();
    Vector history = getInputFileChooser().getHistory();
    
    if(fileName != null){
      history.add(0, fileName);
    }//end if
    
    putPrefixedProperties(properties, history, "OtterInputFileName");
    
    fileName = getOutputFileChooser().getSelected();
    history = getOutputFileChooser().getHistory();
    
    if(fileName != null){
      history.add(0, fileName);
    }//end if
    
    putPrefixedProperties(properties, history, "OtterOutputFileName");
    
    return properties;
  }//end getProperties
    
  /**
   * <p>This is run by apollo to set the GUI state: it is run when the adapter is first
   * started up, as well as when the user moves around or reloads data.</p>
   *
   * <p> I set the widgets to reflect the history fields passed in - the otter file
   * chooser histories, in addition to the superclass.</p>
  **/
  public void setProperties(Properties input){
    super.setProperties(input);
    Vector fileVector =  getPrefixedProperties(input, "OtterInputFileName", true);
    
    getInputFileChooser().setHistory(fileVector);
    
    fileVector =  getPrefixedProperties(input, "OtterOutputFileName", true);

    getOutputFileChooser().setHistory(fileVector);
  }//end setProperties

  /**
   * This is the cut-down panel that describes the location you want to load
  **/
  protected JPanel buildLocationPanel() {
    final int height = 20;
    final int space = 10;
    Dimension labelSize = new Dimension(150, height);
    Dimension textBoxSize = new Dimension(100, height);
    JPanel locationPanel = new JPanel();
    GridBagConstraints theConstraint;
    Insets padRight = new Insets(0,0,0,5);
    
    chrLabel = new JLabel("Chr");
    startLabel = new JLabel("Start");
    endLabel = new JLabel("End");

    locationPanel.setLayout(new GridBagLayout());
    getChrTextBox().setPreferredSize(textBoxSize);
    getStartTextBox().setPreferredSize(textBoxSize);
    getEndTextBox().setPreferredSize(textBoxSize);

    
    locationPanel.setBorder( createBorder("Region") );
    locationPanel.add(chrLabel, makeConstraintAt(0,0,1));
    theConstraint = makeConstraintAt(1,0,1);
    theConstraint.insets = padRight;
    locationPanel.add(chrLabel, theConstraint);
    
    locationPanel.add(getChrTextBox(), makeConstraintAt(2,0,1));

    
    theConstraint = makeConstraintAt(3,0,1);
    theConstraint.insets = padRight;
    locationPanel.add(startLabel, theConstraint);
    
    locationPanel.add(getStartTextBox(), makeConstraintAt(4,0,1));
    
    theConstraint = makeConstraintAt(5,0,1);
    theConstraint.insets = padRight;
    locationPanel.add(endLabel, theConstraint);
    
    locationPanel.add(getEndTextBox(), makeConstraintAt(6,0,1));
    
    theConstraint = makeConstraintAt(0,1,7);
    theConstraint.fill = theConstraint.HORIZONTAL;
    locationPanel.add(getChrStartEndList(), makeConstraintAt(0,1,7));

    getChrStartEndList().setEditable(false);
    getChrStartEndList().addActionListener(getChrAction());
    return locationPanel;
  }//end buildLocationPanel
}


