# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009 Michael Daum http://michaeldaumconsulting.com
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
use Foswiki::Plugins ();
use Foswiki::Plugins::JQueryPlugin ();
use Foswiki::Time ();
use Foswiki::Func ();
use Foswiki::OopsException ();
our $mixedAlphaNum = $Foswiki::regex{'mixedAlphaNum'};

use constant DEBUG => 0; # toggle me

###############################################################################
sub writeDebug {
  print STDERR "- MetaCommentPlugin - $_[0]\n" if DEBUG;
}

##############################################################################
sub restComment {
  my ($session, $subject, $verb, $response) = @_;

  my $web= $session->{webName};
  my $topic= $session->{topicName};

  my $request = Foswiki::Func::getCgiQuery();
  my $useAjax = $request->param('useajax') || 'off';

  unless (Foswiki::Func::checkAccessPermission(
    'VIEW', Foswiki::Func::getWikiName(), undef, $topic, $web)) {
    if ($useAjax eq 'on') {
      returnRESTResult($response, 403, "Access denied");
    } else {
      throw Foswiki::OopsException(
        'accessdenied',
        status => 403,
        def    => 'topic_access',
        web    => $web,
        topic  => $topic,
        params => [ 'VIEW', 'Access denied' ]
      );
    }
    return;
  }

  unless (Foswiki::Func::checkAccessPermission(
    'COMMENT', Foswiki::Func::getWikiName(), undef, $topic, $web)) {
    if ($useAjax eq 'on') {
      returnRESTResult($response, 403, "Access denied");
    } else {
      throw Foswiki::OopsException(
        'accessdenied',
        status => 403,
        def    => 'topic_access',
        web    => $web,
        topic  => $topic,
        params => [ 'COMMENT', 'Access denied' ]
      );
    }
    return;
  }

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  my $cmt_action = $request->param('cmt_action') || '';
  my $cmt_id;

  ### save ###
  if ($cmt_action eq 'save') {
    my $cmt_author = $request->param('cmt_author') || Foswiki::Func::getWikiName();
    my $cmt_title = $request->param('cmt_title') || '';
    my $cmt_text = $request->param('cmt_text') || '';
    my $cmt_ref = $request->param('cmt_ref') || '';
    $cmt_id = getNewId($meta);
    my $cmt_date = time();
    $meta->putKeyed(
      'COMMENT',
      {
        author => $cmt_author,
        date => $cmt_date,
        modified => $cmt_date,
        name => $cmt_id,
        ref => $cmt_ref,
        text => $cmt_text,
        title => $cmt_title,
      }
    );

    Foswiki::Func::saveTopic($web, $topic, $meta, $text);
  } 
  
  ### update ###
  elsif ($cmt_action eq 'update') {
    $cmt_id = $request->param('cmt_id') || '';
    my $comment = $meta->get('COMMENT', $cmt_id);
    unless ($comment) {
      #print STDERR "COMMENT $cmt_id NOT found\n";
      if ($useAjax eq 'on') {
        returnRESTResult($response, 500, "invalid action '$cmt_action' ");
      } else {
        throw Foswiki::OopsException(
          'attention',
          def    => 'generic',
          web    => $web,
          topic  => $topic,
          params => [ "ERROR: comment '$cmt_id' not found" ]
        );
      }
      return;
    }
    #print STDERR "COMMENT $cmt_id found\n";

    my $cmt_title = $request->param('cmt_title') || '';
    my $cmt_text = $request->param('cmt_text') || '';
    my $cmt_author = $comment->{author};
    my $cmt_date = $comment->{date};
    my $cmt_modified = time();
    my $cmt_ref = $request->param('cmt_ref');
    $cmt_ref = $comment->{ref} unless defined $cmt_ref;

    $meta->putKeyed(
      'COMMENT',
      {
        author => $cmt_author,
        date => $cmt_date,
        modified => $cmt_modified,
        name => $cmt_id,
        text => $cmt_text,
        title => $cmt_title,
        ref => $cmt_ref,
      }
    );

    Foswiki::Func::saveTopic($web, $topic, $meta, $text);
  } 
  
  ### delete ###
  elsif ($cmt_action eq 'delete') {
    $cmt_id = $request->param('cmt_id') || '';
    my $comment = $meta->get('COMMENT', $cmt_id);
    if ($comment) {
      #print STDERR "COMMENT $cmt_id found\n";
      $meta->remove('COMMENT', $cmt_id);

      # TODO relocate subcomments

      # save
      Foswiki::Func::saveTopic($web, $topic, $meta, $text);
    } else {
      #print STDERR "COMMENT $cmt_id NOT found\n";
      # not a fatal error when it is already gone
    }
  } 
  
  ### unknown command ###
  else {
    if ($useAjax eq 'on') {
      returnRESTResult($response, 500, "invalid action '$cmt_action' ");
    } else {
      throw Foswiki::OopsException(
        'attention',
        def    => 'generic',
        web    => $web,
        topic  => $topic,
        params => [ "ERROR: invalid action '$cmt_action'" ]
      );
    }
    return; 
  }

  # lets have a nice return value
  if ($useAjax eq 'on') {
    my $result = '';

    if ($cmt_action =~ /^(save|update)$/) {
      # read the comment format string
      Foswiki::Func::readTemplate("metacomments");
      my $formatName = Foswiki::Func::expandTemplate("comments::format");
      $formatName = Foswiki::Func::expandCommonVariables($formatName, $web, $topic);
      my $format = Foswiki::Func::expandTemplate($formatName);
      my $subformat = Foswiki::Func::expandTemplate($formatName."::subcomment");

      # format it
      my $isThreaded = Foswiki::Func::getPreferencesValue("COMMENTSTRUCTURE") || '';
      $isThreaded = $isThreaded eq 'threaded'?'on':'off';
      my $comments = getComments($web, $topic, {threaded=>$isThreaded}, $meta);
      if ($comments) {
        my @comments = ();
        push @comments, $comments->{$cmt_id};
        my $cmt_index = $request->param('cmt_index');
        my @result = formatComments(\@comments, {
          format=>$format, 
          subformat=>$subformat, 
          subheader=>"<div class='cmtSubComments'>",
          subfooter=>"</div>",
          separator=>"",
          index=>($cmt_index-1)# TODO strip off numeric part and parentIndex
        });
        $result = join('', @result);
        $result = Foswiki::Func::expandCommonVariables($result, $web, $topic);

        $result =~ s/(cmtCommentContainer)/$1 jqHighlight/;

        return Foswiki::Func::renderText($result, $web, $topic);
      }
    }

    return 'done';

  } else {
    my $redirectUrl = $session->getScriptUrl(1, 'view', $web, $topic);
    $redirectUrl = $session->redirectto($redirectUrl);
    $session->redirect($redirectUrl);
  }
}

##############################################################################
sub METACOMMENTS {
  my ($session, $params, $topic, $web) = @_;

  Foswiki::Plugins::JQueryPlugin::createPlugin("simplemodal");
  Foswiki::Plugins::JQueryPlugin::createPlugin("form");
  Foswiki::Func::addToHEAD("METACOMMENTPLUGIN", <<'HERE', 'JQUERYPLUGIN::SIMPLEMODAL');

<link rel='stylesheet' href='%PUBURLPATH%/%SYSTEMWEB%/MetaCommentPlugin/metacomment.css' type='text/css' media='all' />
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

  # get all comments data
  my $comments = getComments($theWeb, $theTopic, $params);

  return '' unless $comments;
  my $count = scalar(keys %$comments);
  return '' unless $count;

  $params->{count} = ($count > 1)?$params->{plural}:$params->{singular};
  $params->{count} =~ s/\$count/$count/g;

  # format the results
  my @topComments;
  if ($params->{threaded} eq 'on') {
    @topComments = grep {!$_->{ref}} values %$comments;
  } else {
    @topComments = values %$comments;
  }
  my @result = formatComments(\@topComments, $params);

  # add the lastcomment anchor to the last comment
  $count = scalar(@result);
  if ($count > 0) {
    $count--;
    my $lastComment = $result[$count];
    $result[$count] = '<a name="lastcomment"></a>'.$result[$count];
  }

  return 
    expandVariables($params->{header}, count=>$params->{count}).
    join($params->{separator}, @result).
    expandVariables($params->{footer}, count=>$params->{count});
}

##############################################################################
sub getComments {
  my ($web, $topic, $params, $meta) = @_;

  unless ($meta) {
    return undef unless Foswiki::Func::checkAccessPermission('VIEW');
    ($meta, undef) = Foswiki::Func::readTopic($web, $topic);
  }

  my @comments = $meta->find('COMMENT');

  my %comments = ();

  foreach my $comment (@comments) {
    next if $params->{author} && $comment->{author} !~ /$params->{author}/;
    next if $params->{mindate} && $comment->{date} < $params->{mindate};
    next if $params->{maxdate} && $comment->{date} > $params->{maxdate};
    next if $params->{id} && $comment->{name} ne $params->{id};
    next if $params->{ref} && $params->{ref} ne $comment->{ref};

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

    my $cmt = $comments{$comment->{name}} || {};
    %$cmt = (%$cmt, %$comment);
    $comments{$cmt->{name}} = $cmt;

    if ($params->{threaded} && $params->{threaded} eq 'on' && $cmt->{ref}) {
      my $parent = $comments{$cmt->{ref}};
      unless ($parent) {
        $parent = {};
        $comments{$cmt->{ref}} = $parent;
      }
      push @{$parent->{children}}, $cmt;
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
  foreach my $comment (sort {$a->{name} <=> $b->{name}} @$comments) {
    next if $seen->{$comment->{name}};

    $index++;
    next if $params->{skip} && $index <= $params->{skip};
    my $indexString = ($parentIndex)?"$parentIndex.$index":$index;

    # insert subcomments
    my $subComments = '';
    if ($params->{format} =~ /\$subcomments/ && $comment->{children}) {
      my $oldFormat = $params->{format};
      $params->{format} = $params->{subformat};
      $subComments = join($params->{separator},
        formatComments($comment->{children}, $params, $indexString, $seen));
      $params->{format} = $oldFormat;
      if ($subComments) {
        $subComments =
          expandVariables($params->{subheader}, 
            count=>$params->{count}, 
            index=>$indexString
          ).$subComments.
          expandVariables($params->{subfooter}, 
            count=>$params->{count}, 
            index=>$indexString)
      };
    }

    my $line = expandVariables($params->{format},
      author=>$comment->{author},
      count=>$params->{count},
      date=>Foswiki::Time::formatTime(($comment->{date}||0)),
      modified=>Foswiki::Time::formatTime(($comment->{modified}||0)),
      evenodd=>($index % 2)?'Odd':'Even',
      id=>($comment->{name}||0),
      index=>$indexString,
      ref=>($comment->{ref}||''),
      text=>$comment->{text},
      title=>$comment->{title},
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

  $text =~ s/\$percnt/\%/go;
  $text =~ s/\$nop//go;
  $text =~ s/\$n([^$mixedAlphaNum]|$)/\n$1/go;
  $text =~ s/\$dollar/\$/go;

  foreach my $key (keys %params) {
    my $val = $params{$key} || '';
    $text =~ s/\$$key\b/$val/g;
  }

  return $text;
}

##############################################################################
sub returnRESTResult {
  my ($response, $status, $text) = @_;

  $response->header(
    -status  => $status,
    -type    => 'text/html',
  );

  $response->print($text);
  writeDebug($text) if $status >= 400;
}

1;
