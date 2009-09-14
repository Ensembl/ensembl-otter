
    Installation of Linux otterlace client

You'll need a friendly local Linux administrator if any of the following
instructions don't mean anything to you.

Please email anacode@sanger.ac.uk if you have problems getting otterlace to
work, discover bugs, or don't have a Linux administrator and need some help.

There is a sh script called otterlace in the base directory. This should be
installed somewhere in your PATH, or the system PATH. Edit the commented out
line near top so that OTTER_HOME points to the directory where you expanded
the otterlace client (ie: the one this ReadMe.txt file is in).

You will almost certainly need to install some perl modules from CPAN before
otterlace will compile. Some of these CPAN modules will be provided as
optional components by most Linux distributions, so try your package manager
before using CPAN. Modules you are likely to need to install include:

  Tk
  LWP
  Crypt::SSLeay
  Config::IniFiles
  Ace

"Ace" is AcePerl. It asks a couple of questions during installation. I say
"yes" to the compiled C extension, and "no" to acebrowser.

To use Zmap, you need to compile and install the X11::XRemote extension, which
otterlace uses to communicate with Zmap. To do this cd into the directory
X11-XRemote-0.01, and compile as you would a CPAN module. eg:

  cd X11-XRemote-0.01
  perl Makefile.PL
  make
  make test
  make install

You will need to create a file "~/.otter_config" (ie: in your home directory)
containing:

[client]
author=your@email.address
write_access=1

You can leave off the "write_access" line if you don't need write access.


    Sanger Authentication

In order to use the system each user will need to set up a Sanger website
"Single Sign-On" account, which you can do this via this web page:

  http://www.sanger.ac.uk/perl/ssomanager?action=requestcreate

When you have done this, send the email address you signed up with to
anacode@sanger.ac.uk to get added to the list of permitted users.
