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
package Foswiki::Plugins::MetaCommentPlugin::Core;

use strict;
use warnings;
use Foswiki::Plugins ();
use Foswiki::Plugins::JQueryPlugin ();
use Foswiki::Time ();
use Foswiki::Func ();
use Foswiki::OopsException ();
use Error qw( :try );

use constant DEBUG => 0; # toggle me
use constant DRY => 0; # toggle me

# Error codes for json-rpc response
# -32601: unknown action
# -32600: method not allowed
# 0: ok
# 1: unknown error
# 101: topic does not exist
# 102: access denied
# 104: comment does not exist
# 105: approval not allowed


###############################################################################
sub writeDebug {
  print STDERR "- MetaCommentPlugin - $_[0]\n" if DEBUG;
}

##############################################################################
sub printJSONRPC {
  my ($response, $code, $text, $id) = @_;

  $response->header(
    -status  => $code?500:200,
    -type    => 'text/plain',
  );

  my $msg;
  $id = 'id' unless defined $id;
  $text = 'null' unless defined $text;

  if($code) {
    $msg = '{"jsonrpc" : "2.0", "error" : {"code": '.$code.', "message": "'.$text.'"}, "id" : "'.$id.'"}';
  } else {
    $msg = '{"jsonrpc" : "2.0", "result" : '.$text.', "id" : "'.$id.'"}';
  }

  $response->print($msg);

  #writeDebug("JSON-RPC: $msg");
}

##############################################################################
sub restHandle {
  my ($session, $subject, $verb, $response) = @_;

  my $web= $session->{webName};
  my $topic= $session->{topicName};

  my $request = Foswiki::Func::getCgiQuery();
  my $wikiName = Foswiki::Func::getWikiName();

  unless (Foswiki::Func::topicExists($web, $topic)) {
    printJSONRPC($response, 101, "topic does not exist");
    return;
  }

  unless (Foswiki::Func::checkAccessPermission('VIEW', $wikiName, undef, $topic, $web)) {
    printJSONRPC($response, 102, "Access denied");
    return;
  }

  unless (Foswiki::Func::checkAccessPermission('COMMENT', $wikiName, undef, $topic, $web)
    || Foswiki::Func::checkAccessPermission('CHANGE', $wikiName, undef, $topic, $web)) {
    printJSONRPC($response, 102, "Access denied");
    return;
  }

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  my $action = $request->param('action') || '';

  #writeDebug("action=$action, wikiName=$wikiName");

  ### get ###
  if ($action eq 'get') {
    my $id = $request->param('id') || '';
    my $comment = $meta->get('COMMENT', $id);

    unless ($comment) {
      printJSONRPC($response, 104, "comment not found");
      return;
    }
    my @data = ();
    foreach my $key (keys %$comment) {
      my $val = $comment->{$key};
      #$val =~ s/'/\\'/g;
      $val =~ s/([^0-9a-zA-Z-_.:~!*'\/])/'%'.sprintf('%02x',ord($1))/ge;
      push @data, '"'.$key.'":"'.$val.'"';
    }
    printJSONRPC($response, 0, '{'.join(', ', @data).'}');
    return;
  }

  ### save ###
  elsif ($action eq 'save') {
    my $author = $request->param('author') || $wikiName;
    my $title = $request->param('title') || '';
    my $cmtText = $request->param('text') || '';
    my $ref = $request->param('ref') || '';
    my $id = getNewId($meta);
    my $date = time();
    $meta->putKeyed(
      'COMMENT',
      {
        author => $author,
        state => "new, unapproved",
        date => $date,
        modified => $date,
        name => $id,
        ref => $ref,
        text => $cmtText,
        title => $title,
      }
    );

    my $error;
    unless (DRY) {
      try {
        Foswiki::Func::saveTopic($web, $topic, $meta, $text, {ignorepermissions=>1});
      } catch Error::Simple with {
        $error = shift->{-text};
      };
    }

    if ($error) {
      printJSONRPC($response, 1, $error)
    } else {
      printJSONRPC($response, 0, undef)
    }

    return;
  } 

  ### approve ###
  elsif ($action eq 'approve') {
    my $id = $request->param('id') || '';
    my $comment = $meta->get('COMMENT', $id);
    my $state = $request->param('state') || 'approved';

    unless ($comment) {
      printJSONRPC($response, 104, "comment not found");
      return;
    }

    # check if this is an approver
    unless (isApprover($wikiName, $web, $topic)) {
      printJSONRPC($response, 105, "approval not allowed");
      return;
    }

    # set the state
    $comment->{state} = $state;

    my $error;
    unless (DRY) {
      try {
        Foswiki::Func::saveTopic($web, $topic, $meta, $text, {ignorepermissions=>1});
      } catch Error::Simple with {
        $error = shift->{-text};
      };
    }

    if ($error) {
      printJSONRPC($response, 1, $error)
    } else {
      printJSONRPC($response, 0, undef)
    }

    return;
  }
  
  ### update ###
  elsif ($action eq 'update') {
    my $id = $request->param('id') || '';
    my $comment = $meta->get('COMMENT', $id);

    unless ($comment) {
      printJSONRPC($response, 104, "comment not found");
      return;
    }

    #print STDERR "COMMENT $id found\n";

    my $title = $request->param('title') || '';
    my $cmtText = $request->param('text') || '';
    my $author = $comment->{author};
    my $date = $comment->{date};
    my $state = $comment->{state};
    my $modified = time();
    my $ref = $request->param('ref');
    $ref = $comment->{ref} unless defined $ref;

    my @new_state = ();
    push (@new_state, "updated") if $state =~ /\b(new|updated)\b/;
    push (@new_state, "approved") if $state =~ /\bapproved\b/;
    push (@new_state, "unapproved") if $state =~ /\bunapproved\b/;

    $meta->putKeyed(
      'COMMENT',
      {
        author => $author,
        state => join(", ", @new_state),
        date => $date,
        modified => $modified,
        name => $id,
        text => $cmtText,
        title => $title,
        ref => $ref,
      }
    );

    my $error;
    unless (DRY) {
      try {
        Foswiki::Func::saveTopic($web, $topic, $meta, $text, {ignorepermissions=>1});
      } catch Error::Simple with {
        $error = shift->{-text};
      };
    }

    if ($error) {
      printJSONRPC($response, 1, $error)
    } else {
      printJSONRPC($response, 0, undef)
    }

    return;
  } 
  
  ### delete ###
  elsif ($action eq 'delete') {
    my $id = $request->param('id') || '';
    my $comment = $meta->get('COMMENT', $id);

    unless ($comment) {
      printJSONRPC($response, 104, "comment not found");
      return;
    }

    $meta->remove('COMMENT', $id);

    # TODO relocate subcomments

    # save
    my $error;
    unless (DRY) {
      try {
        Foswiki::Func::saveTopic($web, $topic, $meta, $text, {ignorepermissions=>1});
      } catch Error::Simple with {
        $error = shift->{-text};
      };
    }

    if ($error) {
      printJSONRPC($response, 1, $error)
    } else {
      printJSONRPC($response, 0, undef)
    }

    return;
  } 
  
  ### unknown command ###
  else {
    printJSONRPC($response, -32601, "unknown action");
    return;
  }
}

##############################################################################
sub isApprover {
  my ($wikiName, $web, $topic) = @_;
  
  $wikiName = Foswiki::Func::getWikiName()
    unless defined $wikiName;

  return 1 if Foswiki::Func::checkAccessPermission("APPROVE", $wikiName, undef, $topic, $web);
  return 0;
}

##############################################################################
sub METACOMMENTS {
  my ($session, $params, $topic, $web) = @_;

  Foswiki::Plugins::JQueryPlugin::createPlugin("simplemodal");
  Foswiki::Plugins::JQueryPlugin::createPlugin("form");
  Foswiki::Func::addToZone("head", "METACOMMENTPLUGIN::CSS", <<'HERE', 'JQUERYPLUGIN::SIMPLEMODAL');
<link rel='stylesheet' href='%PUBURLPATH%/%SYSTEMWEB%/MetaCommentPlugin/metacomment.css' type='text/css' media='all' />
HERE

  Foswiki::Func::addToZone("script", "METACOMMENTPLUGIN::JS", <<'HERE', 'JQUERYPLUGIN::SIMPLEMODAL');
<script type='text/javascript' src='%PUBURLPATH%/%SYSTEMWEB%/MetaCommentPlugin/metacomment.js'></script>
HERE

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
  $params->{approval} ||= 'off';
  $params->{reverse} ||= 'off';
  $params->{sort} ||= 'name';
  $params->{singular} = 'One comment' 
    unless defined $params->{singular};
  $params->{plural} = '$count comments' 
    unless defined $params->{plural};
  $params->{mindate} = Foswiki::Time::parseTime($params->{mindate})
    if defined $params->{mindate};
  $params->{maxdate} = Foswiki::Time::parseTime($params->{maxdate}) 
    if defined $params->{maxdate};
  $params->{threaded} = 'off'
    unless defined $params->{threaded};
  $params->{isclosed} = ((Foswiki::Func::getPreferencesValue("COMMENTSTATE")||'open') eq 'closed')?1:0;

  # get all comments data
  my $comments = getComments($theWeb, $theTopic, $params);

  return '' unless $comments;
  my $count = scalar(keys %$comments);
  return '' unless $count;

  $params->{count} = ($count > 1)?$params->{plural}:$params->{singular};
  $params->{count} =~ s/\$count/$count/g;
  $params->{isapprover} = isApprover(undef, $theWeb, $theTopic);

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
      isapprover=>$params->{isapprover},
    ).
    join(expandVariables($params->{separator}), @result).
    expandVariables($params->{footer}, 
      count=>$params->{count},
      isapprover=>$params->{isapprover},
    );
}

##############################################################################
sub getComments {
  my ($web, $topic, $params, $meta) = @_;

  my $wikiName = Foswiki::Func::getWikiName();

  #writeDebug("called getComments");

  unless ($meta) {
    return undef unless Foswiki::Func::checkAccessPermission('VIEW', $wikiName, undef, $topic, $web);
    ($meta, undef) = Foswiki::Func::readTopic($web, $topic);
  }

  my %comments = ();
  my $isApprover = isApprover($wikiName, $web, $topic);

  my @comments = $meta->find('COMMENT');
  foreach my $comment (@comments) {
    my $id = $comment->{name};
    #writeDebug("id=$id, approval=$params->{approval}, isApprover=$isApprover, author=$comment->{author}, wikiName=$wikiName, state=$comment->{state}, isclosed=$params->{isclosed}");
    next if $params->{author} && $comment->{author} !~ /$params->{author}/;
    next if $params->{mindate} && $comment->{date} < $params->{mindate};
    next if $params->{maxdate} && $comment->{date} > $params->{maxdate};
    next if $params->{id} && $id ne $params->{id};
    next if $params->{ref} && $params->{ref} ne $comment->{ref};
    next if $params->{approval} eq 'on' && !($isApprover || $comment->{author} eq $wikiName) && (!$comment->{state} || $comment->{state} !~ /\bapproved\b/);
    next if $params->{isclosed} && (!$comment->{state} || $comment->{state} !~ /\bapproved\b/);

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

    #writeDebug("adding $id");
    $comments{$id} = $comment;
  }

  # gather children
  if ($params->{threaded} && $params->{threaded} eq 'on') {
    foreach my $id (keys %comments) {
      my $cmt = $comments{$id};
      next unless $cmt->{ref};
      my $parent = $comments{$cmt->{ref}};
      if ($parent) {
        push @{$parent->{children}}, $cmt;
      } else {
        #writeDebug("parent $cmt->{ref} not found for $id");
        delete $comments{$id};
      }
    }
    # mark all reachable children and remove the unmarked
    foreach my $id (keys %comments) {
      my $cmt = $comments{$id};
      $cmt->{_tick} = 1 unless $cmt->{ref};
      next unless $cmt->{children};
      foreach my $child (@{$cmt->{children}}) {
        $child->{_tick} = 1;
      }
    }
    foreach my $id (keys %comments) {
      my $cmt = $comments{$id};
      next if $cmt->{_tick};
      #writeDebug("found unticked comment $id");
      delete $comments{$id};
    }
  }


  return \%comments;
}

##############################################################################
sub formatComments {
  my ($comments, $params, $parentIndex, $seen) = @_;

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
    @sortedComments = sort {$a->{modifed} <=> $b->{modified}} @$comments;
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
            isapprover=>$params->{isapprover},
          ).$subComments.
          expandVariables($params->{subfooter}, 
            count=>$params->{count}, 
            isapprover=>$params->{isapprover},
            index=>$indexString)
      };
    }

    my $title = $comment->{title};
    $title = substr($comment->{text}, 0, 10)."..." unless $title;

    my $line = expandVariables($params->{format},
      author=>$comment->{author},
      state=>$comment->{state},
      count=>$params->{count},
      isapprover=>$params->{isapprover},
      date=>Foswiki::Time::formatTime(($comment->{date}||0)),
      modified=>Foswiki::Time::formatTime(($comment->{modified}||0)),
      evenodd=>($index % 2)?'Odd':'Even',
      id=>($comment->{name}||0),
      index=>$indexString,
      ref=>($comment->{ref}||''),
      text=>$comment->{text},
      title=>$title,
      subcomments=>$subComments,
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
sub indexTopicHandler {
  my ($indexer, $doc, $web, $topic, $meta, $text) = @_;

  # delete all previous comments of this topic
  $indexer->deleteByQuery("type:comment web:$web topic:$topic");

  my @comments = $meta->find('COMMENT');
  return unless @comments;


  foreach my $comment (@comments) {

    # set doc fields
    my $date = Foswiki::Func::formatTime($comment->{modified}, 'iso', 'gmtime' );
    my $createDate = Foswiki::Func::formatTime($comment->{date}, 'iso', 'gmtime' );
    my $webtopic = "$web.$topic";
    $webtopic =~ s/\//./g;
    my $id = $webtopic.'#'.$comment->{name};
    my $url = Foswiki::Func::getScriptUrl($web, $topic, 'view', '#'=>'comment'.$comment->{name});
    my $title = $comment->{title};
    $title = substr $comment->{text}, 0, 20 unless $title;

    # reindex this comment
    my $commentDoc = $indexer->newDocument();
    $commentDoc->add_fields(
      'id' => $id,
      'type' => 'comment',
      'web' => $web,
      'topic' => $topic,
      'webtopic' => $webtopic,
      'author' => $comment->{author},
      'contributor' => $comment->{author},
      'date' => $date,
      'createdate' => $createDate,
      'title' => $title,
      'text' => $comment->{text},
      'url' => $url,
      'state' => ($comment->{state}||''),
    );
    $doc->add_fields('catchall' => $title);
    $doc->add_fields('catchall' => $comment->{text});
    $doc->add_fields('contributor' => $comment->{author});

    # add the document to the index
    try {
      $indexer->add($commentDoc);
      $indexer->commit();
    } catch Error::Simple with {
      my $e = shift;
      $indexer->log("ERROR: ".$e->{-text});
    };
  }
}

1;
