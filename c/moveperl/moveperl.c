#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <sys/param.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <ctype.h>

typedef enum FileTypeEnum {
  NONE,
  EMPTY,
  SCRIPT,
  BINARY,
  TEXT
} FileType;

char *typeStrings[] = {
  "NONE",
  "EMPTY",
  "SCRIPT",
  "BINARY",
  "TEXT"
};

char *copyAndReplace(char *fromBuf,char *toBuf,char *baseFromName, char *baseToName, int len, int *toLen, FileType type);
FileType fileType(char *fileBuf,int len);
void descendAndDo(DIR *dir, char *fromDirName, char *toDirName, 
                  char *baseFromName, char *baseToName, int doFunc());
int doFunc(char *fromName, char *toName, char *baseFromName, char *baseToName); 

int main(int argc, char *argv[]) {
  DIR *fromdir;
  char fullFromName[MAXPATHLEN];
  char fullDestName[MAXPATHLEN];
  char baseFromPath[MAXPATHLEN];
  char baseToPath[MAXPATHLEN];
  struct stat st;

  if (argc != 3) {
    printf("Usage: moveperl <fromdir> <todir>\n");
    exit(1);
  }

  if ((fromdir = opendir(argv[1])) == NULL) {
    printf("Error - couldn't open source perl directory %s\n",argv[1]);
    exit(1);
  }

  if ((opendir(argv[2])) != NULL) {
    printf("Error - destination perl directory already exists\n");
    exit(1);
  }
/*
  if (!realpath(argv[1],fullFromName)) {
    printf("Error - couldn't get realpath to fromdir\n");
    exit(1);
  }
  if (!realpath(argv[2],fullDestName)) {
    printf("Error - couldn't get realpath to destdir\n");
    exit(1);
  }
*/
  strcpy(fullFromName,argv[1]);
  strcpy(fullDestName,argv[2]);

  if (strlen(fullFromName) < strlen(fullDestName)) {
    printf("Length of to path can't be longer than from path\n");
    exit(1);
  }

  stat(fullFromName,&st);
  if (mkdir(fullDestName,st.st_mode)) {
    printf("Failed making directory %s\n",fullDestName);
    exit(1);
  }
  strcpy(baseFromPath,fullFromName);
  strcpy(baseToPath,fullDestName);
  descendAndDo(fromdir,fullFromName,fullDestName,baseFromPath,baseToPath,doFunc);
}

void descendAndDo(DIR *dir, char *fromDirName, char *toDirName, char *baseFromName, char *baseToName, int doFunc()) {
  struct dirent *dp;
  char fromName[MAXPATHLEN];
  char toName[MAXPATHLEN];
  struct stat st;

  while ((dp = readdir(dir)) != NULL) {
    sprintf(fromName,"%s/%s",fromDirName,dp->d_name);
    sprintf(toName,"%s/%s",toDirName,dp->d_name);
    
    if (strcmp(dp->d_name,".") && strcmp(dp->d_name,"..")) {
      stat(fromName,&st);
      if (st.st_mode & S_IFDIR) {
        DIR *childdir;
        printf("  is a directory\n");
        if ((childdir = opendir(fromName)) == NULL) {
          printf("Error - couldn't open directory %s\n",fromName);
          exit(1);
        }
        if (!doFunc(fromName,toName,baseFromName,baseToName)) {
          printf("Failed executing doFunc\n");
          exit(1);
        }
        descendAndDo(childdir,fromName,toName,baseFromName,baseToName,doFunc);
      } else {
        if (!doFunc(fromName,toName,baseFromName,baseToName)) {
          printf("Failed executing doFunc\n");
          exit(1);
        }
      }
    } 
  }
  (void)closedir(dir);
}

int doFunc(char *fromName, char *toName, char *baseFromName, char *baseToName) {
  FILE *fp;
  char *fileBuf;
  char *toBuf;
  int ch;
  char *chP;
  struct stat st;
  int count=0;
  FileType type;
  int toLen;
  
  printf("%s %s %s %s\n",fromName,toName,baseFromName,baseToName);

  stat(fromName,&st);
  if (st.st_mode & S_IFDIR) {
    if (mkdir(toName,st.st_mode)) {
      printf("Failed making directory %s\n",toName);
      exit(1);
    }
  } else {
    if ((fileBuf = calloc(st.st_size+1,sizeof(char))) == NULL) {
      printf("Failed allocating space for file buffer\n");
      exit(1);
    }
    if ((toBuf = calloc(st.st_size+1,sizeof(char))) == NULL) {
      printf("Failed allocating space for file buffer\n");
      exit(1);
    }
  
    if ((fp = fopen(fromName,"r")) == NULL) {
      printf("Failed opening from perl file %s\n",fromName);
      exit(1);
    }
    chP = fileBuf;
    
    while ((ch = getc(fp)) != EOF) {
      count++;
      *chP = ch;
      chP++;
    }
    fclose(fp);
    if ((fp = fopen(toName,"w")) == NULL) {
      printf("Failed opening to perl file %s\n",toName);
      exit(1);
    }
    type = fileType(fileBuf,st.st_size);
    printf("Type = %d (%s)\n",type,typeStrings[type]);
    copyAndReplace(fileBuf,toBuf,baseFromName,baseToName,st.st_size,&toLen,type);
    fwrite(toBuf,toLen,1,fp); 
    fclose(fp);
    chmod(toName,st.st_mode);

    free(fileBuf);
    free(toBuf);
  }
  return 1;
}

char *copyAndReplace(char *fromBuf,char *toBuf,char *baseFromName, char *baseToName, int fromLen, int *toLen, FileType type) {
  char *fromChP;
  char *toChP;
  int nToCopy = 0;
  int lenBaseFromName = strlen(baseFromName);
  int lenBaseToName = strlen(baseToName);
  int i;

  
  
  fromChP = fromBuf;
  toChP = toBuf;

  while ((fromChP-fromBuf) < fromLen) {
    if (*fromChP == baseFromName[0] && 
        !strncmp(baseFromName,fromChP,lenBaseFromName)) {
      strcpy(toChP,baseToName);
    
      printf("NOTE NOTE NOTE NOTE NOTE Match to baseFromName\n");

      fromChP  += lenBaseFromName;
      toChP    += lenBaseToName;
      while (!iscntrl(*fromChP) && !isspace(*fromChP)) {
        printf("%c",*fromChP);
        *toChP = *fromChP;
        toChP++;
        fromChP++;
      }
      if (type == BINARY) {
        printf("padding with %d chars\n",lenBaseFromName-lenBaseToName);
        for (i=0;i<lenBaseFromName-lenBaseToName;i++) {
          (*toChP)='\0';
          toChP++;
        }
      }
      printf("\n");
    } else {
      *toChP = *fromChP;
      fromChP++;
      toChP++;
    }
  } 
  
  *toLen = toChP-toBuf;
  printf("From len = %d,  To len = %d\n",fromLen, *toLen);
  return toBuf;
}

FileType fileType(char *fileBuf,int len) {
  char *chP;
  int i;
  int nNewline = 0;
  int nToGet=2000;

  if (!len) return EMPTY;

  if (!strncmp(fileBuf,"#!",2)) {
    return SCRIPT;  
  }

  if (len < nToGet) {
    nToGet = len;
  }
  for (i=0;i<nToGet;i++) {
    if (fileBuf[i] == '\n') {
      nNewline++;
    }
  }
  if (!nNewline) return BINARY;

  if ((float)nToGet/(float)nNewline < 50) {
    return TEXT;
  }

  return BINARY;
}
