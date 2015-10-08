
    Installation of Linux otter client

You'll need a friendly local Linux administrator if any of the following
instructions don't mean anything to you.

Please email anacode@sanger.ac.uk if you have problems getting otter to
work, discover bugs, or don't have a Linux administrator and need some help.

There is a sh script called otter in the base directory. This should be
installed somewhere in your PATH, or the system PATH. Edit the commented out
line near top so that OTTER_HOME points to the directory where you expanded
the otter client (ie: the one this ReadMe.txt file is in).

Otter makes use of other code (Zircon and the Hum::* modules)
which have not been published.  Please contact us if you need them.

You will almost certainly need to install some perl modules from CPAN before
otter will compile. Some of these CPAN modules will be provided as
optional components by most Linux distributions, so try your package manager
before using CPAN. Modules you are likely to need to install include:

  CGI
  DBD-mysql
  DBI
  Term::ReadKey
  Digest-MD5
  MIME-Base64
  Tk
  URI
  libnet
  libwww-perl
  LWP
  LWP::Authen::Wsse
  Crypt::SSLeay
  Config::IniFiles
  Proc::ProcessTable
  Ace

"Ace" is AcePerl. It asks a couple of questions during installation. I say
"yes" to the compiled C extension, and "no" to acebrowser.

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
