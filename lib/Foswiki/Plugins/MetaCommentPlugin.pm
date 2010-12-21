# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2010 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
package Foswiki::Plugins::MetaCommentPlugin;

use strict;
use Foswiki::Func ();

our $VERSION = '$Rev$';
our $RELEASE = '0.9.0';
our $SHORTDESCRIPTION = 'An easy to use comment system';
our $NO_PREFS_IN_TOPIC = 1;
our $baseWeb;
our $baseTopic;
our $isInitialized;

sub initPlugin {
  ($baseTopic, $baseWeb) = @_;

  Foswiki::Func::registerTagHandler('METACOMMENTS', \&METACOMMENTS);
  Foswiki::Func::registerRESTHandler('handle', \&restHandle);
  $isInitialized = 0;

  # SMELL this is not reliable as it depends on plugin order
  # if (Foswiki::Func::getContext()->{SolrPluginEnabled}) {
  if ($Foswiki::cfg{Plugins}{SolrPlugin}{Enabled}) {
    require Foswiki::Plugins::SolrPlugin;
    Foswiki::Plugins::SolrPlugin::registerIndexTopicHandler(\&indexTopicHandler);
  }

  return 1;
}

sub init {
  return if $isInitialized;
  require Foswiki::Plugins::MetaCommentPlugin::Core;
  $isInitialized = 1;
}

sub METACOMMENTS {
  init();
  Foswiki::Plugins::MetaCommentPlugin::Core::METACOMMENTS(@_);
}

sub restHandle {
  init();
  Foswiki::Plugins::MetaCommentPlugin::Core::restHandle(@_);
}

sub restIndex {
  init();
  Foswiki::Plugins::MetaCommentPlugin::Core::restIndex(@_);
}

sub indexTopicHandler {
  init();
  Foswiki::Plugins::MetaCommentPlugin::Core::indexTopicHandler(@_);
}

1;
