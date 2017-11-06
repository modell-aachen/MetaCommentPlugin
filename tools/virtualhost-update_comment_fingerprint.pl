#! /usr/bin/env perl

# See bottom of file for license and copyright information
use strict;
use warnings;

use File::Find;

BEGIN {
    $Foswiki::cfg{Engine} = 'Foswiki::Engine::CLI';
    require Carp;
    $SIG{__DIE__} = \&Carp::confess;
    if (-e './setlib.cfg') {
      unshift @INC, '.';
    } elsif (-e '../bin/setlib.cfg') {
      unshift @INC, '../bin';
    }
    require 'setlib.cfg';
    $ENV{FOSWIKI_ACTION} = 'view';
}

use Foswiki ();
use Foswiki::UI ();
use Foswiki::Contrib::VirtualHostingContrib::VirtualHost ();
use Digest::MD5 ();



my $verbose = 1;
my $hostname = '';
my $logging = 0;
my $nodry = 0;

foreach my $arg (@ARGV) {
  if ($arg =~ /^(.*)=(.*)$/) {
    if ($1 eq 'verbose') {
      $verbose = ($2 eq 'on')?1:0;
    } elsif ($1 eq 'logging') {
      $logging = 1 if $2;
    } elsif ($1 eq 'host') {
      $hostname = $2;
    } elsif ($1 eq 'nodry') {
      $nodry = 1 if $2;
    }
  }
}

if ($hostname) {
  Foswiki::Contrib::VirtualHostingContrib::VirtualHost->run_on($hostname, \&doit);
} else {
  Foswiki::Contrib::VirtualHostingContrib::VirtualHost->run_on_each(\&doit);
}

sub doit {
  my $host = $Foswiki::Contrib::VirtualHostingContrib::VirtualHost::CURRENT || $hostname;
  printf("=> Processing %s\n", $host) if $verbose;

  my @dirs = grep { -d } glob "/var/www/qwikis/vhosts/$host/data/*";
  foreach my $dir (@dirs){
    if ($dir =~ m/(System|Trash|Tasks|_default|_empty|Main|ZZCustom|_apps)/){
      next;
    }else{
      find({ wanted => \&find_txt, no_chdir=>1}, "$dir/");
    }
  }
}

sub find_txt {
    my $host =  $Foswiki::Contrib::VirtualHostingContrib::VirtualHost::CURRENT || $hostname;
    my $F = $File::Find::name;

    if ($F =~ /txt$/ ) {
        my $edit = 0;
        open(my $fh, '<', $F);
        my $file_content = do { local $/; <$fh> };
        seek $fh, 0, 0;

        my @comments = (grep{/%META:COMMENT\{/} <$fh>);
        if (@comments){
          $F =~ s/\/var\/www\/qwikis\/vhosts\/$host\/data\///g;
          print "File: $F\n" if $logging;

          #get each comment
          foreach my $comment(@comments){
            my ($author) = $comment =~ m/author="([^"]*)"/i;
            print "author: $author\n" if $logging;
            my $fingerprint = Digest::MD5::md5_hex($author);
            print "new Fingerprint: $fingerprint\n" if $logging;
            my $commentOld = $comment;
            $comment =~ s/fingerPrint="([^"]*)"/fingerPrint="$fingerprint"/g;
            $file_content =~ s/\Q$commentOld\E/$comment/;
            $edit = 1;
          }
        }
        close $fh;
        if($nodry && $edit){
          open($fh, '>', $File::Find::name) or die "Couldn't open: $!";
          print $fh $file_content;
          close $fh;
          print "Save file: $File::Find::name\n\n" if $logging;
        }
    }
}
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2010 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

Additional copyrights apply to some or all of the code in this
file as follows:

Copyright (C) 1999-2007 Peter Thoeny, peter@thoeny.org
and TWiki Contributors. All Rights Reserved. TWiki Contributors
are listed in the AUTHORS file in the root of this distribution.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
