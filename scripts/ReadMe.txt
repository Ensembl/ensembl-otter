
    Installation of Linux otterlace client

You'll need a friendly local Linux administrator
if any of the following instructions don't mean
anything to you.

Please email anacode@sanger.ac.uk if you have
problems getting otterlace to work, discover bugs,
or don't have a Linux administrator and need some
help.

There is a sh script called otterlace in the base
directory.  This should be installed somewhere in
your PATH, or the system PATH.  Edit the commented
out line near top so that OTTER_HOME points to the
directory where you expanded the otterlace client
(ie: the one this ReadMe.txt file is in).

You will almost certainly need to install some
perl modules from CPAN before otterlace will
compile.  Some of these CPAN modules will be
provided as optional components by most Linux
distributions, so try your package manager before
using CPAN.  Modules you are likely to need to
install include:

  Tk
  LWP
  Crypt::SSLeay
  Config::IniFiles
  Ace

"Ace" is AcePerl. It asks a couple of questions
during installation.  I say "yes" to the compiled
C extension, and "no" to acebrowser.

You will need to create a file "~/.otter_config"
(ie: in your home directory) containing:

[client]
author=your@email.address
write_access=1

You can leave off the "write_access" line if you
don't need write access.


    Sanger Authentication

In order to use the system each user will need to
set up a Sanger website "Single Sign-On" account,
which you can do this via this web page:

  http://www.sanger.ac.uk/perl/ssomanager?action=requestcreate

When you have done this, send the email address
you signed up with to anacode@sanger.ac.uk to get
added to the list of permitted users.  (I have
pre-added the email addresses of the Cow
annotation jamboree workshop delegates.)


    Pfetch server

The distribution uses a Sanger service called
pfetch to fetch EMBL, Genbank and Uniprot
entries.  A local process called "local_pfetch"
which is forked by the script, but since it binds
to an IP socket on the local machine, only 1 copy
of it can run at time.  This might be a problem if
you have more than 1 person running otterlace on a
server machine.  The local_pfetch will exit as
soon as a request fails, eg: when the
authentication for that user has expired.  You
will then be able start your own copy by choosing
"Restart local pfetch server" from the "Tools"
menu in the lace transcript chooser window.

