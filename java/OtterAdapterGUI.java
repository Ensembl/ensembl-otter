package apollo.dataadapter.otter;

import java.awt.*;
import java.awt.event.*;
import javax.swing.*;
import java.util.*;
import java.io.*;

//import org.apollo.datamodel.*;

import java.util.Properties;
import org.bdgp.swing.AbstractDataAdapterUI;
import org.bdgp.io.IOOperation;
import org.bdgp.io.DataAdapter;


import apollo.dataadapter.*;
import apollo.datamodel.CurationSet;
import apollo.datamodel.Range;
import apollo.datamodel.RangeI;
import apollo.gui.Config;
import apollo.gui.ProxyDialog;
import apollo.gui.EnsemblDbDialog;

public class OtterAdapterGUI extends AbstractDataAdapterUI {//JPanel implements DataAdapterUI {

  protected DataAdapter driver;
  protected IOOperation op;
  private JLabel inputFileLabel;
  private JTextField inputFileField;
  private JLabel outputFileLabel;
  private JTextField outputFileField;

  private Properties props;

  public OtterAdapterGUI(IOOperation op) {
    this.op = op;
    inputFileLabel = new JLabel("Otter Input File:");
    inputFileField = new JTextField(20);
    outputFileLabel = new JLabel("Otter Output File:");
    outputFileField = new JTextField(20);
    buildGUI();
  }

  public void setProperties(Properties in) {
  }

  public Properties getProperties() {
    return new Properties();
  }

  public void buildGUI() {
    JPanel internalPanel = new JPanel();
    internalPanel.setLayout(new GridBagLayout());
    
    internalPanel.add(inputFileLabel, makeConstraintAt(0,0,1));
    internalPanel.add(inputFileField, makeConstraintAt(0,1,1));
    internalPanel.add(outputFileLabel, makeConstraintAt(1,0,1));
    internalPanel.add(outputFileField, makeConstraintAt(1,1,1));
    add(internalPanel);
  }

  public void setDataAdapter(DataAdapter driver) {
    this.driver = driver;
  }
  
  public DataAdapter getDataAdapter(){
    return driver;
  }

  public Object doOperation(Object values) throws DataAdapterException {
    CurationSet curationSet;
    String fileName = inputFileField.getText();
    FileInputStream theInputStream;
    File outputFile;
    FileOutputStream outputStream;
    
    if(fileName == null || fileName.trim().length() <=0){
      fileName = "/auto/acari/vvi/src/apollo-current/apollo/src/java/apollo/dataadapter/otter/parser/test4.xml";
    }//end if
    
    try{
      theInputStream = new FileInputStream(fileName);
    }catch(FileNotFoundException theException){
      throw new DataAdapterException("File not found");
    }//end try
    
    fileName = outputFileField.getText();

    if(fileName == null || fileName.trim().length() <=0){
      fileName = "/auto/acari/vvi/src/apollo-current/apollo/src/java/apollo/dataadapter/otter/parser/annotation-output.xml";
    }//end if
    
    outputFile = new File(fileName);
    
    if(outputFile.exists()){
      outputFile.delete();
    }//end if

    try{
      outputFile.createNewFile();

      outputStream = new FileOutputStream(outputFile);
    }catch(IOException theException){
      throw new DataAdapterException("problems creating output file", theException);
    }//end try
    
    ((OtterAdapter)getDataAdapter()).setInputStream(theInputStream);
    ((OtterAdapter)getDataAdapter()).setOutputStream(outputStream);
    
    if (op.equals(ApolloDataAdapterI.OP_READ_DATA)) {
      curationSet = ((ApolloDataAdapterI) driver).getCurationSet();
      return curationSet;
    } else {
      return null;
    }//end if

  }//end doOperation
  
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
  
}
