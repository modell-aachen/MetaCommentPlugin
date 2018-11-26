# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2013 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package Foswiki::Plugins::MetaCommentPlugin::Core;

use strict;
use warnings;
use Foswiki::Plugins ();
use Foswiki::Contrib::JsonRpcContrib::Error ();
use Foswiki::Contrib::MailTemplatesContrib;
use Foswiki::Time ();
use Foswiki::Func ();
use Error qw( :try );
use Digest::MD5 ();

use constant DEBUG => 0; # toggle me
use constant DRY => 0; # toggle me

# Error codes for json-rpc response
# 1000: comment does not exist
# 1001: approval not allowed

###############################################################################
sub new {
  my ($class, $session) = @_;

  my $this = {
    session => $session,
    baseWeb => $session->{webName},
    baseTopic => $session->{topicName},
    anonCommenting => $Foswiki::cfg{MetaCommentPlugin}{AnonymousCommenting},
    loginName => Foswiki::Func::getCanonicalUserID(),
  };

  $this->{anonCommenting} = 0 unless defined $this->{anonCommenting};

  my $context = Foswiki::Func::getContext();
  my $canComment = _canComment($this);
  $context->{canComment} = 1 if $canComment; # set a context flag

  return bless($this, $class);
}

##############################################################################
sub jsonRpcReadComment {
  my ($this, $request) = @_;

  my $web = $this->{baseWeb};
  my $topic = $this->{baseTopic};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist") 
    unless Foswiki::Func::topicExists($this->{baseWeb}, $this->{baseTopic});

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{loginName}, undef, $topic, $web);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  my $id = $request->param('comment_id') || '';
  my $comment = $meta->get('COMMENT', $id);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "Comment not found")
    unless $comment;

  my $skipUsers = {};
  if($comment->{notified}) {
      foreach my $user (split(',', $comment->{notified})) {
        $skipUsers->{$user} = 1;
    }
  }
  $skipUsers->{$this->{loginName}} = 1;
  $comment->{notified} = join(',', keys %$skipUsers);

  my $readUsers = {};
  if($comment->{read}) {
      foreach my $user (split(',', $comment->{read})) {
        $readUsers->{$user} = 1;
    }
  }
  $readUsers->{$this->{loginName}} = 1;
  $comment->{read} = join(',', keys %$readUsers);

  Foswiki::Func::saveTopic($web, $topic, $meta, $text, {ignorepermissions=>1, forcenewrevision=>1, minor=>1}) unless DRY;

  writeEvent("commentnotify", "state=(What state?) title=".('')." text=".substr('Schnittlauch', 0, 200));
  return;
}

##############################################################################
sub jsonRpcNotifyComment {
  my ($this, $request) = @_;

  my $web = $this->{baseWeb};
  my $topic = $this->{baseTopic};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist") 
    unless Foswiki::Func::topicExists($this->{baseWeb}, $this->{baseTopic});

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{loginName}, undef, $topic, $web);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  my $id = $request->param('comment_id') || '';
  my $comment = $meta->get('COMMENT', $id);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "Comment not found")
    unless $comment;

  my $skipUsers = {};
  if($comment->{notified}) {
    foreach my $user (split(',', $comment->{notified})) {
      $skipUsers->{$user} = 1;
    }
  }

  my $preferences = _getPreferences($comment);
  #If notification addresses more than one, parameter needs to be casted to array
  if(ref($request->param('who')) eq 'ARRAY') {
    $preferences->{MetaComment_TO_NOTIFY} = join(",", @{$request->param('who')});
  } else {
    $preferences->{MetaComment_TO_NOTIFY} = $request->param('who');
  }

  Foswiki::Contrib::MailTemplatesContrib::sendMail('MetaCommentNotify', {SkipUsers => $skipUsers, GenerateInAdvance => 1}, $preferences, 1 );

  $comment->{notified} = join(',', keys %$skipUsers);
  $meta->putKeyed(
    'COMMENT',
    $comment
  );

  Foswiki::Func::saveTopic($web, $topic, $meta, $text, {ignorepermissions=>1, forcenewrevision=>1, minor=>1}) unless DRY;

  return;
}

##############################################################################
sub jsonRpcGetComment {
  my ($this, $request) = @_;

  my $web = $this->{baseWeb};
  my $topic = $this->{baseTopic};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist") 
    unless Foswiki::Func::topicExists($this->{baseWeb}, $this->{baseTopic});

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{loginName}, undef, $topic, $web);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  my $id = $request->param('comment_id') || '';
  my $comment = $meta->get('COMMENT', $id);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "Comment not found")
    unless $comment;

  return $comment;
}

##############################################################################
sub jsonRpcSaveComment {
  my ($this, $request) = @_;

  my $web = $this->{session}{webName};
  my $topic = $this->{session}{topicName};

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    if Foswiki::Func::isGuest() && !$this->{anonCommenting}; 

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    if Foswiki::Func::isGroupMember("ReadOnlyGroup",$this->{session}{user});

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist") 
    unless Foswiki::Func::topicExists($this->{baseWeb}, $this->{baseTopic});

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{loginName}, undef, $topic, $web);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied") unless $this->_canComment();

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
  my $isModerator = $this->isModerator($web, $topic, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Discussion closed")
    unless $isModerator || (Foswiki::Func::getPreferencesValue("COMMENTSTATE")||'open') ne 'closed';

  my $author = $this->{loginName};
  my $title = $request->param('title') || '';
  my $cmtText = $request->param('text') || '';
  my $ref = $request->param('ref') || '';
  my $id = getNewId($meta);
  my $date = time();
  my $fingerPrint = getFingerPrint($author);

  my @state = ();
  push @state, "new";

  if ($this->isModerated($web, $topic, $meta)) {
    if ($this->isModerator($web, $topic, $meta)) {
      push @state, "approved";
    } else {
      push @state, "unapproved";
    }
  }

  my $state = join(", ", @state);

  my $comment = {
    author => $author,
    fingerPrint => $fingerPrint,
    state => $state,
    date => $date,
    modified => $date,
    name => $id,
    ref => $ref,
    text => $cmtText,
    title => $title,
    read => $this->{loginName},
  };

  $meta->putKeyed(
    'COMMENT',
    $comment
  );

  _notify($meta, $comment, 'MetaCommentSave', {});

  Foswiki::Func::saveTopic($web, $topic, $meta, $text, {ignorepermissions=>1, forcenewrevision=>1}) unless DRY;
  writeEvent("comment", "state=($state) title=".($title||'').' text='.substr($cmtText, 0, 200)); # SMELL: does not objey approval state

  return;
}

sub _notify {
  my ($meta, $comment, $template, $preferences) = @_;

  $preferences = {%$preferences, %{_getPreferences($comment)}};

  my $notifiedUsers = {};
  Foswiki::Contrib::MailTemplatesContrib::sendMail($template, {SkipUsers => $notifiedUsers, GenerateInAdvance => 1}, $preferences, 1 );

  $comment->{notified} = join(',', keys %$notifiedUsers);
  $meta->putKeyed(
    'COMMENT',
    $comment
  );
}

##############################################################################
sub getFingerPrint {
  my $author = shift;

  if ($author eq $Foswiki::cfg{DefaultUserWikiName}) {

    # the fingerprint of a guest matches for one hour
    my $timeStamp = Foswiki::Time::formatTime(time(), '$year-$mo-$day-$hours');

    $author = ($ENV{REMOTE_ADDR}||'???').'::'.$timeStamp;
  }

  return Digest::MD5::md5_hex($author);

}

##############################################################################
sub jsonRpcApproveComment {
  my ($this, $request) = @_;

  my $web = $this->{session}{webName};
  my $topic = $this->{session}{topicName};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist") 
    unless Foswiki::Func::topicExists($this->{baseWeb}, $this->{baseTopic});

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{loginName}, undef, $topic, $web);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission('CHANGE', $this->{loginName}, undef, $topic, $web);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
  my $isModerator = $this->isModerator($web, $topic, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1001, "Approval not allowed")
    unless $isModerator;

  my $id = $request->param('comment_id') || '';
  my $comment = $meta->get('COMMENT', $id);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "Comment not found")
    unless $comment;

  # set the state
  $comment->{state} = "approved";

  Foswiki::Func::saveTopic($web, $topic, $meta, $text, {ignorepermissions=>1}) 
    unless DRY;

  writeEvent("commentapprove", "state=($comment->{state}) title=".($comment->{title}||'').' text='.substr($comment->{text}, 0, 200)); 

  return;
}

##############################################################################
sub jsonRpcUpdateComment {
  my ($this, $request) = @_;

  my $web = $this->{session}{webName};
  my $topic = $this->{session}{topicName};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist") 
    unless Foswiki::Func::topicExists($this->{baseWeb}, $this->{baseTopic});

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{loginName}, undef, $topic, $web);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission('COMMENT', $this->{loginName}, undef, $topic, $web) ||
           Foswiki::Func::checkAccessPermission('CHANGE', $this->{loginName}, undef, $topic, $web);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
  my $isModerator = $this->isModerator($web, $topic, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Discussion closed")
    unless $isModerator || (Foswiki::Func::getPreferencesValue("COMMENTSTATE")||'open') ne 'closed';

  my $id = $request->param('comment_id') || '';
  my $comment = $meta->get('COMMENT', $id);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "Comment not found")
    unless $comment;

  my $fingerPrint = getFingerPrint($this->{loginName});

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Acccess denied")
    unless $isModerator || $fingerPrint eq ($comment->{fingerPrint}||'');

  my $title = $request->param('title') || '';
  my $cmtText = $request->param('text') || '';
  my $modified = time();
  my $ref = $request->param('ref');
  $ref = $comment->{ref} unless defined $ref;

  my $state = $comment->{state};
  my @new_state = ();
  push (@new_state, "updated") if $state =~ /\b(new|updated)\b/;
  if ($this->isModerated($web, $topic, $meta)) {
    push (@new_state, "approved") if $state =~ /\bapproved\b/;
    push (@new_state, "unapproved") if $state =~ /\bunapproved\b/;
  }

  $state = join(", ", @new_state);

  my $newComment = {
    author => $comment->{author},
    fingerPrint => $comment->{fingerPrint},
    date => $comment->{date},
    state => $state,
    modified => $modified,
    name => $id,
    text => $cmtText,
    title => $title,
    ref => $ref,
    read => $this->{loginName}
  };

  $meta->putKeyed(
    'COMMENT',
    $newComment
  );

  # This has to come from the old one
  _notify($meta, $newComment, 'MetaCommentUpdate', {MetaComment_notified => ($comment->{notified} || ''), MetaComment_read => ( $comment->{read} || '')});

  Foswiki::Func::saveTopic($web, $topic, $meta, $text, {ignorepermissions=>1}) unless DRY;
  writeEvent("commentupdate", "state=($state) title=".($title||'')." text=".substr($cmtText, 0, 200)); 

  return;
}

sub _getPreferences {
    my ($comment) = @_;

    my $preferences = {};

    foreach my $key ( keys %$comment ) {
        $preferences->{"MetaComment_$key"} = $comment->{$key} if $comment->{$key} ne '';
    }
    return $preferences;
}

##############################################################################
sub jsonRpcDeleteComment {
  my ($this, $request) = @_;

  my $web = $this->{session}{webName};
  my $topic = $this->{session}{topicName};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist") 
    unless Foswiki::Func::topicExists($this->{baseWeb}, $this->{baseTopic});

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{loginName}, undef, $topic, $web);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission('COMMENT', $this->{loginName}, undef, $topic, $web) ||
           Foswiki::Func::checkAccessPermission('CHANGE', $this->{loginName}, undef, $topic, $web);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
  my $isModerator = $this->isModerator($web, $topic, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Discussion closed")
    unless $isModerator || (Foswiki::Func::getPreferencesValue("COMMENTSTATE")||'open') ne 'closed';

  my $id = $request->param('comment_id') || '';
  my $comment = $meta->get('COMMENT', $id);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "Comment not found")
    unless $comment;

  my $fingerPrint = getFingerPrint($this->{loginName});

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Acccess denied")
    unless $isModerator || $fingerPrint eq ($comment->{fingerPrint}||'');

  # relocate replies by assigning them to the parent
  my $parentId = $comment->{ref} || '';
  my $parentComment = $meta->get('COMMENT', $parentId);
  my $parentName = $parentComment?$parentComment->{name}:'';

  foreach my $reply ($meta->find('COMMENT')) {
    next unless $reply->{ref} && $reply->{ref} eq $comment->{name};
    $reply->{ref} = $parentName;
  }

  # remove this comment
  $meta->remove('COMMENT', $id);

  Foswiki::Func::saveTopic($web, $topic, $meta, $text, {ignorepermissions=>1}) unless DRY;
  writeEvent("commentdelete", "state=($comment->{state}) title=".($comment->{title}||'')." text=".substr($comment->{text}, 0, 200)); 

  my $preferences = _getPreferences($comment);
  Foswiki::Contrib::MailTemplatesContrib::sendMail('MetaCommentDelete', {}, $preferences, 1 );

  return;
}

###############################################################################
sub writeDebug {
  print STDERR "- MetaCommentPlugin - $_[0]\n" if DEBUG;
}

##############################################################################
sub isModerator {
  my ($this, $web, $topic, $meta) = @_;
  
  return 1 if Foswiki::Func::isAnAdmin();
  return 0 unless $this->isModerated($web, $topic, $meta);
  return 1 if Foswiki::Func::checkAccessPermission("MODERATE", $this->{loginName}, undef, $topic, $web, $meta);
  return 0;
}

##############################################################################
sub METACOMMENTS {
  my ($this, $params, $topic, $web) = @_;

  my $context = Foswiki::Func::getContext();
  if ($context->{"preview"} || $context->{"save"} ||  $context->{"edit"}) {
    return;
  }

  Foswiki::Func::readTemplate("metacomments");

  # sanitize params
  $params->{topic} ||= $topic;
  $params->{web} ||= $web;
  my ($theWeb, $theTopic) = Foswiki::Func::normalizeWebTopicName($params->{web}, $params->{topic});
  $params->{topic} = $theTopic;
  $params->{web} = $theWeb;
  $params->{format} = '<h3>$title</h3>$text' 
    unless defined $params->{format};
  $params->{format} = Foswiki::Func::expandTemplate($params->{template})
    if defined $params->{template};
  $params->{subformat} = $params->{format}
    unless defined $params->{subformat};
  $params->{subformat} = Foswiki::Func::expandTemplate($params->{subtemplate})
    if defined $params->{subtemplate};
  unless (defined $params->{subheader}) {
    $params->{subheader} = "<div class='cmtSubComments'>";
    $params->{subfooter} = "</div>";
  }
  $params->{subfooter} ||= '';
  $params->{header} ||= '';
  $params->{footer} ||= '';
  $params->{separator} ||= '';
  $params->{ref} ||= '';
  $params->{skip} ||= 0;
  $params->{limit} ||= 0;
  $params->{moderation} ||= 'off';
  $params->{reverse} ||= 'off';
  $params->{sort} ||= 'name';
  $params->{singular} = 'One comment' 
    unless defined $params->{singular};
  $params->{plural} = '$count comments' 
    unless defined $params->{plural};
  $params->{mindate} = Foswiki::Time::parseTime($params->{mindate})
    if defined $params->{mindate} && $params->{mindate} !~ /^\d+$/;
  $params->{maxdate} = Foswiki::Time::parseTime($params->{maxdate}) 
    if defined $params->{maxdate} && $params->{mindate} !~ /^\d+$/;
  $params->{threaded} = 'off'
    unless defined $params->{threaded};
  $params->{isclosed} = ((Foswiki::Func::getPreferencesValue("COMMENTSTATE")||'open') eq 'closed')?1:0;

  # get all comments data
  my ($meta) = Foswiki::Func::readTopic($theWeb, $theTopic);
  my $comments = $this->getComments($theWeb, $theTopic, $meta, $params);

  return '' unless $comments;
  my $count = scalar(keys %$comments);
  return '' unless $count;

  $params->{count} = ($count > 1)?$params->{plural}:$params->{singular};
  $params->{count} =~ s/\$count/$count/g;
  $params->{ismoderator} = $this->isModerator($theWeb, $theTopic);

  # format the results
  my @topComments;
  if ($params->{threaded} eq 'on') {
    @topComments = grep {!$_->{ref}} values %$comments;
  } else {
    @topComments = values %$comments;
  }
  my @result = formatComments(\@topComments, $params);

  return 
    expandVariables($params->{header}, 
      count=>$params->{count},
      ismoderator=>$params->{ismoderator},
    ).
    join(expandVariables($params->{separator}), @result).
    expandVariables($params->{footer}, 
      count=>$params->{count},
      ismoderator=>$params->{ismoderator},
    );
}

##############################################################################
sub getComments {
  my ($this, $web, $topic, $meta, $params) = @_;

  ($meta) = Foswiki::Func::readTopic($web, $topic) unless defined $meta;

  my $isModerator = $this->isModerator($web, $topic, $meta);

  #writeDebug("called getComments");

  my @topics = ();
  if (defined $params->{search}) {
    @topics = $this->getTopics($web, $params->{search}, $params);
  } else {
    return undef unless Foswiki::Func::checkAccessPermission('VIEW', $this->{loginName}, undef, $topic, $web);
    push @topics, $topic;
  }

  my $fingerPrint = getFingerPrint($this->{loginName});
  my %comments = ();

  foreach my $thisTopic (@topics) {
    my ($meta) = Foswiki::Func::readTopic($web, $thisTopic);
    my $isModerated = $this->isModerated($web, $thisTopic, $meta);

    my @comments = $meta->find('COMMENT');
    foreach my $comment (@comments) {
      my $id = $comment->{name};
      #writeDebug("id=$id, moderation=$params->{moderation}, isModerator=$isModerator, author=$comment->{author}, loginName=$this->{loginName}, state=$comment->{state}, isclosed=$params->{isclosed}");
      next if $params->{author} && $comment->{author} !~ /$params->{author}/;
      next if $params->{mindate} && $comment->{date} < $params->{mindate};
      next if $params->{maxdate} && $comment->{date} > $params->{maxdate};
      next if $params->{id} && $id ne $params->{id};
      next if $params->{ref} && $params->{ref} ne $comment->{ref};
      next if $params->{state} && (!$comment->{state} || $comment->{state} !~ /^($params->{state})$/);
      if ($isModerated) {
        next if $params->{moderation} eq 'on' && !($isModerator || ($comment->{fingerPrint}||'') eq $fingerPrint) && (!$comment->{state} || $comment->{state} =~ /\bunapproved\b/);
        next if $params->{moderation} eq 'on' && $params->{isclosed} && (!$comment->{state} || $comment->{state} =~ /\bunapproved\b/);
      }

      next if $params->{include} && !(
        $comment->{author} =~ /$params->{include}/ ||
        $comment->{title} =~ /$params->{include}/ ||
        $comment->{text} =~ /$params->{include}/
      );

      next if $params->{exclude} && (
        $comment->{author} =~ /$params->{exclude}/ ||
        $comment->{title} =~ /$params->{exclude}/ ||
        $comment->{text} =~ /$params->{exclude}/
      );

      $comment->{topic} = $thisTopic;
      $comment->{web} = $web;

      #writeDebug("adding $id");
      $comments{$thisTopic.'::'.$id} = $comment;
    }
  }

  # gather children
  if ($params->{threaded} && $params->{threaded} eq 'on') {
    while (my ($key, $cmt) = each %comments) {
      next unless $cmt->{ref};
      my $parent = $comments{$cmt->{topic}.'::'.$cmt->{ref}};
      if ($parent) {
        push @{$parent->{children}}, $cmt;
      } else {
        #writeDebug("parent $cmt->{ref} not found for $cmt->{name}");
        delete $comments{$key};
      }
    }
    # mark all reachable children and remove the unmarked
    while (my ($key, $cmt) = each %comments) {
      $cmt->{_tick} = 1 unless $cmt->{ref};
      next unless $cmt->{children};
      foreach my $child (@{$cmt->{children}}) {
        $child->{_tick} = 1;
      }
    }
    while (my ($key, $cmt) = each %comments) {
      next if $cmt->{_tick};
      #writeDebug("found unticked comment $cmt->{name}");
      delete $comments{$key};
    }
  }

  return \%comments;
}

##############################################################################
sub getTopics {
  my $this = shift;

  if ($Foswiki::cfg{Plugins}{DBCachePlugin}{Enabled}) {
    require Foswiki::Plugins::DBCachePlugin;
    return $this->getTopics_DBQUERY(@_);
  } else {
    return $this->getTopics_SEARCH(@_);
  }
}

##############################################################################
sub getTopics_DBQUERY {
  my ($this, $web, $where, $params) = @_;

  my $search = new Foswiki::Contrib::DBCacheContrib::Search($where);
  return unless $search;


  my $db = Foswiki::Plugins::DBCachePlugin::getDB($web);
  my @topicNames = $db->getKeys();
  my @selectedTopics = ();

  foreach my $topic (@topicNames) { # loop over all topics
    my $topicObj = $db->fastget($topic);
    next unless $search->matches($topicObj); # that match the query
    next unless Foswiki::Func::checkAccessPermission('VIEW', 
      $this->{loginName}, undef, $topic, $web);
    my $commentDate = $topicObj->fastget("commentdate");
    next unless $commentDate;
    push @selectedTopics, $topic;
  }

  return @selectedTopics;
}

##############################################################################
sub getTopics_SEARCH {
  my ($this, $web, $where, $params) = @_;

  $where .= ' and comment';

  #print STDERR "where=$where, web=$web\n";

  my $matches = Foswiki::Func::query($where, undef, { 
    web => $web,
    casesensitive => 0, 
    files_without_match => 1 
  });

  my @selectedTopics = ();
  while ($matches->hasNext) {
    my $topic = $matches->next;
    (undef, $topic) = Foswiki::Func::normalizeWebTopicName('', $topic);
    push @selectedTopics, $topic;
  }

  #print STDERR "topics=".join(', ', @selectedTopics)."\n";
  return @selectedTopics;
}

##############################################################################
sub formatComments {
  my ($comments, $params, $parentIndex, $seen) = @_;

  my $session = $Foswiki::Plugins::SESSION;

  $parentIndex ||= '';
  $seen ||= {};
  my @result = ();
  my $index = $params->{index} || 0;
  my @sortedComments;

  if ($params->{sort} eq 'name') {
    @sortedComments = sort {$a->{name} <=> $b->{name}} @$comments;
  } elsif ($params->{sort} eq 'date') {
    @sortedComments = sort {$a->{date} <=> $b->{date}} @$comments;
  } elsif ($params->{sort} eq 'modified') {
    @sortedComments = sort {$a->{modified} <=> $b->{modified}} @$comments;
  } elsif ($params->{sort} eq 'author') {
    @sortedComments = sort {$a->{author} cmp $b->{author}} @$comments;
  }

  @sortedComments = reverse @sortedComments if $params->{reverse} eq 'on';
  my $count = scalar(@sortedComments);
  foreach my $comment (@sortedComments) {
    next if $seen->{$comment->{name}};

    $index++;
    next if $params->{skip} && $index <= $params->{skip};
    my $indexString = ($params->{reverse} eq 'on')?($count - $index +1):$index;
    $indexString = "$parentIndex.$indexString" if $parentIndex;

    # insert subcomments
    my $subComments = '';
    if ($params->{format} =~ /\$subcomments/ && $comment->{children}) {
      my $oldFormat = $params->{format};
      $params->{format} = $params->{subformat};
      $subComments = join(expandVariables($params->{separator}),
        formatComments($comment->{children}, $params, $indexString, $seen));
      $params->{format} = $oldFormat;
      if ($subComments) {
        $subComments =
          expandVariables($params->{subheader}, 
            count=>$params->{count}, 
            index=>$indexString,
            ismoderator=>$params->{ismoderator},
          ).$subComments.
          expandVariables($params->{subfooter}, 
            count=>$params->{count}, 
            ismoderator=>$params->{ismoderator},
            index=>$indexString)
      };
    }

    my $title = $comment->{title};

    my $summary = '';
    if ($params->{format} =~ /\$summary/) {
      $summary = substr($comment->{text}, 0, 100);
      $summary =~ s/^\s*\-\-\-\++//g; # don't remove heading, just strip tml
      $summary = $session->renderer->TML2PlainText($summary, undef, "showvar") . " ...";
      $summary =~ s/\n/<br \/>/g;
    }

    my $permlink = Foswiki::Func::getScriptUrl($comment->{web},
      $comment->{topic}, "view", "#"=>"comment".($comment->{name}||0));

    my $username = Foswiki::Func::getCanonicalUserID();
    my $read = ($comment->{read} && $comment->{read} =~ m/(?:^|,)\Q$username\E(?:,|$)/)?1:0;

    # Substitute newline characters with %BR% on display.
    my $displayNewLines = $Foswiki::cfg{MetaCommentPlugin}{DisplayNewLines} || 0;
    if ( $displayNewLines ) {
        $comment->{text} =~ s/(\r\n|\n|\r)/%BR%/g;
    }

    my $date = Foswiki::Time::formatTime(($comment->{date}||0));
    my $dstr = "%SUBST{text=\"$date\" pattern=\"([A-Za-z]{3})\" format=\"\$percntMAKETEXT{\$1}\$percnt\"}%";
    my ($meta) = Foswiki::Func::readTopic($comment->{web}, $comment->{topic});
    $date = $meta->expandMacros($dstr);
    my $line = expandVariables($params->{format},
      author=>$comment->{author},
      state=>$comment->{state},
      count=>$params->{count},
      ismoderator=>$params->{ismoderator},
      timestamp=>$comment->{date} || 0,
      date=>$date,
      modified=>Foswiki::Time::formatTime(($comment->{modified}||0)),
      isodate=> Foswiki::Func::formatTime($comment->{modified} || $comment->{date}, 'iso', 'gmtime'),
      evenodd=>($index % 2)?'Odd':'Even',
      id=>($comment->{name}||0),
      index=>$indexString,
      ref=>($comment->{ref}||''),
      text=>$comment->{text},
      title=>$title,
      subcomments=>$subComments,
      topic=>$comment->{topic},
      web=>$comment->{web},
      summary=>$summary,
      permlink=>$permlink,
      read=>$read
    );

    next unless $line;
    push @result, $line;
    last if $params->{limit} && $index >= $params->{limit};
  }

  return @result;
}

##############################################################################
sub getNewId {
  my $meta = shift;

  my @comments = $meta->find('COMMENT');
  my $maxId = 0;
  foreach my $comment (@comments) {
    my $id = int($comment->{name});
    $maxId = $id if $id > $maxId;
  }

  $maxId++;

  return "$maxId.".time();
}

##############################################################################
sub expandVariables {
  my ($text, %params) = @_;

  return '' unless $text;

  foreach my $key (keys %params) {
    my $val = $params{$key};
    $val = '' unless defined $val;
    $text =~ s/\$$key\b/$val/g;
  }

  $text =~ s/\$perce?nt/\%/go;
  $text =~ s/\$nop//go;
  $text =~ s/\$n/\n/go;
  $text =~ s/\$dollar/\$/go;

  return $text;
}

##############################################################################
sub writeEvent {
  return unless defined &Foswiki::Func::writeEvent;
  return Foswiki::Func::writeEvent(@_);
}

##############################################################################
sub isModerated {
  my ($this, $web, $topic, $meta) = @_;

  ($meta) = Foswiki::Func::readTopic($web, $topic) unless defined $meta;

  my $prefs = $this->{session}->{prefs}->loadPreferences($meta);
  my $isModerated = $prefs->get("COMMENTMODERATION");
  $isModerated = $prefs->getLocal("COMMENTMODERATION") unless defined $isModerated;
  $isModerated = Foswiki::Func::getPreferencesValue("COMMENTMODERATION", $web) unless defined $isModerated;

  return Foswiki::Func::isTrue($isModerated, 0);
}

##############################################################################
sub indexTopicHandler {
  my ($this, $indexer, $doc, $web, $topic, $meta, $text) = @_;

  # delete all previous comments of this topic
  #$indexer->deleteByQuery("type:comment web:$web topic:$topic");

  my @comments = $meta->find('COMMENT');
  return unless @comments;

  my @aclFields = $indexer->getAclFields($web, $topic, $meta);
  my $isModerated = $this->isModerated($web, $topic, $meta);

  foreach my $comment (@comments) {

    # set doc fields
    my $createDate = Foswiki::Func::formatTime($comment->{date}, 'iso', 'gmtime' );
    my $date = defined($comment->{modified})?Foswiki::Func::formatTime($comment->{modified}, 'iso', 'gmtime' ):$createDate;
    my $webtopic = "$web.$topic";
    $webtopic =~ s/\//./g;
    my $id = $webtopic.'#'.$comment->{name};
    my $url = $indexer->getScriptUrlPath($web, $topic, 'view', '#'=>'comment'.$comment->{name});
    my $title = $comment->{title};
    $title = substr $comment->{text}, 0, 20 unless $title;

    my $collection = $Foswiki::cfg{SolrPlugin}{DefaultCollection} || "wiki";
    my $language = $indexer->getContentLanguage($web, $topic) || 'en';

    my $state = $comment->{state}||'null';

    # escape html
    my $text = $comment->{text};
    $text =~ s#<#&lt;#g;
    $text =~ s#>#&gt;#g;

    # reindex this comment
    my $commentDoc = $indexer->newDocument();
    $commentDoc->add_fields(
      'id' => $id,
      'language' => $language,
      'name' => $comment->{name},
      'type' => 'comment',
      'web' => $web,
      'topic' => $topic,
      'webtopic' => $webtopic,
      'author' => $comment->{author},
      'contributor' => $comment->{author},
      'date' => $date,
      'createdate' => $createDate,
      'title' => $title,
      'text' => $text,
      'url' => $url,
      'state' => $state,
      'container_id' => $web.'.'.$topic,
      'container_url' => Foswiki::Func::getViewUrl($web, $topic),
      'container_title' => $indexer->getTopicTitle($web, $topic, $meta),
    );

    if($comment->{notified}) {
      foreach my $notified ( split(',', $comment->{notified} =~ s#\s##gr) ) {
        $commentDoc->add_fields(
                'notified_lst' => $notified
        );
      }
    }

    if($comment->{read}) {
      foreach my $read ( split(',', $comment->{read} =~ s#\s##gr) ) {
        $commentDoc->add_fields(
                'read_lst' => $read
        );
      }
    }

    if ($isModerated && $state =~ /\bunapproved\b/) {
      $commentDoc->add_fields('access_granted' => '');
    } else {
      $commentDoc->add_fields(@aclFields) if @aclFields;
    }


    $doc->add_fields('catchall' => $title);
    $doc->add_fields('catchall' => $comment->{text});
    $doc->add_fields('contributor' => $comment->{author});

    # add the document to the index
    try {
      $indexer->add($commentDoc);
    } catch Error::Simple with {
      my $e = shift;
      $indexer->log("ERROR: ".$e->{-text});
    };
  }
}

##############################################################################
sub _canComment {
  my ($this) = @_;

  my $canComment = 0;
  if($Foswiki::cfg{MetaCommentPlugin}{AlternativeACLCheck}) {
    $canComment = 1 if Foswiki::Func::isTrue(
        Foswiki::Func::expandCommonVariables($Foswiki::cfg{MetaCommentPlugin}{AlternativeACLCheck})
    );
  } else {
    $canComment = 1 if
      Foswiki::Func::checkAccessPermission('COMMENT', $this->{loginName}, undef, $this->{baseTopic}, $this->{baseWeb}) ||
      Foswiki::Func::checkAccessPermission('CHANGE', $this->{loginName}, undef, $this->{baseTopic}, $this->{baseWeb});
  }

  $canComment = 0 if Foswiki::Func::isGuest() && !$this->{anonCommenting};

  return $canComment;
}

1;
