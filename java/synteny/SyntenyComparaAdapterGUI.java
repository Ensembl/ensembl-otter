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

import edu.stanford.ejalbert.*;

import apollo.datamodel.CurationSet;
import apollo.datamodel.GenomicRange;
import apollo.gui.*;

import org.ensembl.util.*;
import org.ensembl.gui.*;
import org.ensembl.driver.*;


public class SyntenyComparaAdapterGUI extends EnsJAdapterGUI {

  private JTextField hitChrTextField;
  private JTextField hitStartTextField;
  private JTextField hitEndTextField;
  private JLabel hitChrLabel;
  private JLabel hitStartLabel;
  private JLabel hitEndLabel;
  
  private String querySpecies;
  private String hitSpecies;
  
  private String logicalQuerySpecies;
  private String logicalHitSpecies;

  private JLabel chrLabel = new JLabel("Chr");
  private JLabel startLabel = new JLabel("Start");
  private JLabel endLabel = new JLabel("End");

  private JComboBox hitChrStartEndList;
  private Vector hitStartEndVector;
  private JDialog frame;
  private JButton fullPanelButton  ;
  private AbstractDataAdapterUI parent;
  
  //
  //Need to hang onto these two as instance variables in
  //addition to the textfields because their titled borders
  //are set after they're constructed.
  private JPanel hitLocationPanel;
  private JPanel queryLocationPanel;
  private FullEnsJDBCSyntenyPanel thePanel; //syntenypanel
  private ActionListener hitChrAction;
  
  /**
   * Launches the FullEnsjSyntenyPanel when the "view panel" button is hit. 
   * The purpose of the panel is to set the ranges back onto the individual 
   * adapters.
  **/
  public class FullPanelListener implements ActionListener{
    public void actionPerformed(ActionEvent theEvent){
      SyntenyComparaAdapterGUI.this.thePanel = 
        new FullEnsJDBCSyntenyPanel(
          getQuerySpecies(), //logical
          getHitSpecies(), //logical
          getParentAdapter(), //the callback is my parent composite adapter
          null
        );

      thePanel.init();
      SyntenyComparaAdapterGUI.this.frame = new JDialog((JFrame)null, "range chooser", true);
      SyntenyComparaAdapterGUI.this.frame.setDefaultCloseOperation(WindowConstants.DISPOSE_ON_CLOSE);
      SyntenyComparaAdapterGUI.this.frame.getContentPane().setLayout(new BorderLayout());
      SyntenyComparaAdapterGUI.this.frame.getContentPane().add("Center",thePanel);

      SyntenyComparaAdapterGUI.this.frame.setSize(700,700);
      SyntenyComparaAdapterGUI.this.frame.show();
    }//end actionPerformed
  }//end FullPanelListener 
  
  public SyntenyComparaAdapterGUI(IOOperation op) {
    super(op);
  }

  
  protected void buildGUI() {
    setLayout(new GridBagLayout());
    add(buildQueryLocationPanel(), makeConstraintAt(0,0,1));
    
    fullPanelButton = new JButton("View panel");
    FullPanelListener fullPanelListener = new FullPanelListener();
    fullPanelButton.addActionListener(fullPanelListener);
    
    add(fullPanelButton,makeConstraintAt(0,1,1));
    
    add(buildHitLocationPanel(), makeConstraintAt(0,2,1));
    add(getDriverConfigPanel(), makeConstraintAt(0,3,1));
  }

  /**
   * add on the hit-information to the query-information already in there.
  **/
  public Properties createStateInformation() {
    Properties information = super.createStateInformation();
    //
    //This should be getting placed in automatically!
    information.put("region", getSelectedChrStartEnd());

    information.setProperty("querySpecies",getQuerySpecies());
    information.setProperty("hitSpecies",getHitSpecies());
    information.setProperty("hitChr",hitChrTextField.getText());
    information.setProperty("hitStart",hitStartTextField.getText());
    information.setProperty("hitEnd",hitEndTextField.getText());
    return information;
  }

  /**
   * <p>This SNEAKY method is invoked by the CompositeAdapter after it's created this adapter 
   * as a child. </p>
   *
   * <p>This is invoked by the SyntenyMenu after the user has chosen a synteny region.</p>
   * 
   * <p>If the input is a HashMap, we use it to set values into the chromosome and 
   * high/low text fields. </p>
   *
   * <p>If the input is an AbstractDataAdapterUI instance, then we
   * are being told that this input is our 'parent'. We will set 
   * this parent on ourselves </p>
   *
   * <p> WHY IS THIS METHOD OVERUSED? </p>
   * <p> (1) It is part of the standard AbstractDataAdapterUI 
   * interface,so I can use it without having to create an interface like "composable" 
   * with a get/setParent() method.</p>
   *
   * <p> (2) I should move the other functionality in here to the setProperties() method. </p>
   *
  **/
  public void setInput(Object input) {
    HashMap theInput;
    String text;
    
    if(input instanceof HashMap){
      
      theInput = (HashMap)input;

      getChrTextBox().setText((String)theInput.get("chr"));
      getStartTextBox().setText((String)theInput.get("start"));
      getEndTextBox().setText((String)theInput.get("end"));
      hitChrTextField.setText((String)theInput.get("hitChr"));
      hitStartTextField.setText((String)theInput.get("hitStart"));
      hitEndTextField.setText((String)theInput.get("hitEnd"));
      
      //
      //If we've received input, then the frame can disappear
      frame.dispose();
      
    }else if(input instanceof AbstractDataAdapterUI){
      
      setParentAdapter((AbstractDataAdapterUI)input);
      
    }//end if
  }//end setInput

  /**
   * Repeats the location panel layout code for the hit-location
  **/
  private JPanel buildHitLocationPanel(){
    final int height = 20;
    final int space = 10;
    Dimension labelSize = new Dimension(150, height);
    Dimension textBoxSize = new Dimension(100, height);
    hitLocationPanel = new JPanel();
    GridBagConstraints theConstraint;
    Insets padRight = new Insets(0,0,0,5);
    
    hitLocationPanel = new JPanel();
    hitLocationPanel.setLayout(new GridBagLayout());
    
    hitChrLabel = new JLabel("Chr");
    hitStartLabel = new JLabel("Start");
    hitEndLabel = new JLabel("End");
    hitChrTextField = new JTextField(5);
    hitStartTextField = new JTextField(15);
    hitEndTextField = new JTextField(15);
    
    hitLocationPanel.setLayout(new GridBagLayout());
    hitChrTextField.setPreferredSize(textBoxSize);
    hitStartTextField.setPreferredSize(textBoxSize);
    hitEndTextField.setPreferredSize(textBoxSize);

    
    if(hitSpecies != null){
      hitLocationPanel.setBorder(new TitledBorder(hitSpecies));
    }else{
      hitLocationPanel.setBorder(new TitledBorder("Hit species"));
    }

    hitLocationPanel.add(hitChrLabel, makeConstraintAt(0,0,1));
    theConstraint = makeConstraintAt(1,0,1);
    theConstraint.insets = padRight;
    hitLocationPanel.add(hitChrTextField, theConstraint);
    
    theConstraint = makeConstraintAt(2,0,1);
    theConstraint.insets = padRight;
    hitLocationPanel.add(hitStartLabel, theConstraint);
    
    hitLocationPanel.add(hitStartTextField, makeConstraintAt(3,0,1));
    
    theConstraint = makeConstraintAt(4,0,1);
    theConstraint.insets = padRight;
    hitLocationPanel.add(hitEndLabel, theConstraint);
    
    hitLocationPanel.add(hitEndTextField, makeConstraintAt(5,0,1));
    
    theConstraint = makeConstraintAt(0,1,7);
    theConstraint.fill = theConstraint.HORIZONTAL;
    
    hitChrStartEndList = new JComboBox();
    hitLocationPanel.add(hitChrStartEndList, makeConstraintAt(0,1,7));

    hitChrStartEndList.setEditable(false);
    
    hitChrStartEndList.addActionListener(getHitChrAction());
    
    return hitLocationPanel;
    
  }
  
  /**
   * Utility for grid-bag constraints
  **/
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
   * <p> This contains the properties stored in the adapter history,
   * which are read when the adapter is created. They will populate
   * the history-comboboxes etc. </p>
   *
   * <p> It also contains the NAMES of the query and hit species - 
   * note that these properties live in the style file for the 
   * synteny adapter. They are added onto the history-file properties
   * passed into this adapter by the CompositeAdapterUI class.
  **/
  public void setProperties(Properties properties){
    
    super.setProperties(properties);
    
    hitChrTextField.setText(properties.getProperty("hitChr"));
    hitStartTextField.setText(properties.getProperty("hitStart"));
    hitEndTextField.setText(properties.getProperty("hitEnd"));
    
    hitStartEndVector = getPrefixedProperties(properties, "hitStartEndHistory", false);
    ActionListener a = getHitChrAction();
    hitChrStartEndList.removeActionListener(a);
    hitChrStartEndList.setModel(new DefaultComboBoxModel(hitStartEndVector));
    hitChrStartEndList.addActionListener(a);

    //
    //As passed by the parent adapter, these are LOGICAL names for
    //the species, like "Human" or "Mouse", or "Human1" and "Human2"
    querySpecies = properties.getProperty("querySpecies");
    hitSpecies = properties.getProperty("hitSpecies");
    
    queryLocationPanel.setBorder(new TitledBorder(querySpecies));
    hitLocationPanel.setBorder(new TitledBorder(hitSpecies));
  }//end setProperties
  
  /**
   * Builds a stripped-down version of the standard ensj-location panel
   * (we don't need clone-locations).
  **/
  protected JPanel buildQueryLocationPanel() {
    final int height = 20;
    final int space = 10;
    Dimension labelSize = new Dimension(150, height);
    Dimension textBoxSize = new Dimension(100, height);
    queryLocationPanel = new JPanel();
    GridBagConstraints theConstraint;
    Insets padRight = new Insets(0,0,0,5);
    
    chrLabel = new JLabel("Chr");
    startLabel = new JLabel("Start");
    endLabel = new JLabel("End");

    queryLocationPanel.setLayout(new GridBagLayout());
    getChrTextBox().setPreferredSize(textBoxSize);
    getStartTextBox().setPreferredSize(textBoxSize);
    getEndTextBox().setPreferredSize(textBoxSize);

    if(querySpecies != null){
      queryLocationPanel.setBorder(new TitledBorder(querySpecies));
    }else{
      queryLocationPanel.setBorder(new TitledBorder("Query region"));
    }

    queryLocationPanel.add(chrLabel, makeConstraintAt(0,0,1));
    theConstraint = makeConstraintAt(1,0,1);
    theConstraint.insets = padRight;
    queryLocationPanel.add(getChrTextBox(), theConstraint);
    
    theConstraint = makeConstraintAt(2,0,1);
    theConstraint.insets = padRight;
    queryLocationPanel.add(startLabel, theConstraint);
    
    queryLocationPanel.add(getStartTextBox(), makeConstraintAt(3,0,1));
    
    theConstraint = makeConstraintAt(4,0,1);
    theConstraint.insets = padRight;
    queryLocationPanel.add(endLabel, theConstraint);
    
    queryLocationPanel.add(getEndTextBox(), makeConstraintAt(5,0,1));
    
    theConstraint = makeConstraintAt(0,1,7);
    theConstraint.fill = theConstraint.HORIZONTAL;
    queryLocationPanel.add(getChrStartEndList(), makeConstraintAt(1,1,7));

    getChrStartEndList().setEditable(false);
    getChrStartEndList().addActionListener(getChrAction());
    return queryLocationPanel;
  }//end buildLocationPanel
  
  private String getQuerySpecies(){
    return querySpecies;
  }//end getQuerySpecies
  
  private String getHitSpecies(){
    return hitSpecies;
  }//end getHitSpecies

  private AbstractDataAdapterUI getParentAdapter(){
    return parent;
  }//end getParent
  
  /**
   * This MUST be invoked if this adapter is created as part of a composite-
   * I do it in the setInput method
  **/
  private void setParentAdapter(AbstractDataAdapterUI newValue){
    parent = newValue;
  }//end setParent

  /**
   * Returns the current state of the adapter - this just adds on the hit-location-panel
   * state to the superclass function.
  **/
  public Properties getProperties() {
    Properties properties = super.getProperties();

    String selectedHitLocation = 
      "Chr "+ 
      hitChrTextField.getText() + " " +
      hitStartTextField.getText() + " " +
      hitEndTextField.getText();
    
    if ( hitStartEndVector != null && !hitStartEndVector.contains(selectedHitLocation) ) {
      hitStartEndVector.insertElementAt(selectedHitLocation, 0);
    }//end if
    
    putPrefixedProperties(properties, hitStartEndVector, "hitStartEndHistory");
    
    return properties;
  }//end 
  
  private ActionListener getHitChrAction(){
    if (hitChrAction == null){
      hitChrAction = new ActionListener() {
        public void actionPerformed(ActionEvent evt) {
          GenomicRange loc = 
            EnsJAdapterGUI.parseChrStartEndString(
              (String)hitChrStartEndList.getSelectedItem()
            );

          if (loc != null) {
            hitChrTextField.setText(loc.getChromosome());
            hitStartTextField.setText(loc.getStart() + "");
            hitEndTextField.setText(loc.getEnd() + "");
          }//end if
        }//end actionPerformed
      };
    }//end if
    
    return hitChrAction;
  }
}


