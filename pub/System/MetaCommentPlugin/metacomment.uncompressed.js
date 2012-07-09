/*

Foswiki - The Free and Open Source Wiki, http://foswiki.org/

(c)opyright 2010-2012 Michael Daum http://michaeldaumconsulting.com

are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.

*/

jQuery(function($) {
  $(".cmtComments:not(.cmtCommentsInited)").livequery(function() {
    var $this = $(this),
        $container = $this.parent(),
        defaults = {
          topic: foswiki.getPreference("TOPIC"),
          web: foswiki.getPreference("WEB")
        },
        doneLoadDialogs = false;
        opts = $.extend({}, defaults, $this.metadata());

    /* function to reload all dialogs **************************************/
    function loadDialogs(callback) {
      if (!doneLoadDialogs) {
        doneLoadDialogs = true;
        $.get(
          foswiki.getPreference("SCRIPTURL") + "/rest/RenderPlugin/template", 
          {
            name:'metacomments',
            render:'on',
            topic:opts.web+"."+opts.topic,
            expand:'comments::dialogs'
          }, function(data, status, xhr) {
            $('body').append(data);
            window.setTimeout(callback, 100); // wait for livequeries ...
          }
        );
      } else {
        callback.call();
      }
    };

    /* function to reload all comments *************************************/
    function loadComments(message) {
      var url = foswiki.getPreference("SCRIPTURL") + 
          "/rest/RenderPlugin/template" +
          "?name=metacomments" + 
          ";render=on" +
          ";topic="+opts.web+"."+opts.topic +
          ";expand=metacomments";

      if (!message) {
        message = "Loading ...";
      }
      message = "<h1>"+message+"</h1>";
      $.blockUI({
        message:message,
        fadeIn: 0,
        fadeOut: 0,
        overlayCSS: {
          cursor:'progress'
        }
      });
      $container.load(url, function() {
        $.unblockUI();
        $container.height('auto');
      });
    }

    /* add hover ***********************************************************/
    $this.find(".cmtComment").hoverIntent({
      over: function() {
        var $this = $(this), $controls = $this.find(".cmtControls");
        $this.addClass("cmtHover");
        $controls.fadeIn(500, function() {
          $controls.css({opacity: 1.0});
        });
      },
      out: function() {
        var $this = $(this), $controls = $this.find(".cmtControls");
        $controls.stop();
        $controls.css({display:'none', opacity: 1.0});
        $this.removeClass("cmtHover");
      }
    });

    /* ajaxify add and reply forms ******************************************/
    $(".cmtAddCommentForm, .cmtReplyCommentForm").livequery(function() {
      var $form = $(this), rev, $errorContainer;

      $form.ajaxForm({
        dataType:"json",
        beforeSubmit: function() {
          rev = $form.find("input[name='ref']").val(),
          $errorContainer = rev?$this.find("a[name='comment"+rev+"']").parent().parent():$form.parent();

          $this.find(".foswikiErrorMessage").remove();
          $.blockUI({
            message:"<h1>Submitting comment ...</h1>",
            fadeIn: 0,
            fadeOut: 0
          });
        },
        success: function(data, statusText, xhr) {
          $.unblockUI();
          if(data.error) {
            $errorContainer.after("<p><div class='foswikiErrorMessage'>Error: "+data.error.message+"</div></p>");
          } else {
            loadComments();
          }
          $form.parent().dialog("close");
        },
        error: function(xhr, msg) {
          var data = $.parseJSON(xhr.responseText);
          $.unblockUI();
          $errorContainer.after("<p><div class='foswikiErrorMessage'>Error: "+data.error.message+"</div></p>");
          $form.parent().dialog("close");
        }
      });
    });

    /* ajaxify update form **************************************************/
    $(".cmtUpdateCommentForm").livequery(function() {
      var $form = $(this), 
          $errorContainer, 
          id, index;

      $form.ajaxForm({
        dataType:"json",
        beforeSubmit: function() {
          id = $form.find("input[name='comment_id']").val();
          index = $form.find("input[name='index']").val();
          $errorContainer = $this.find("a[name='comment"+id+"']").parent().parent();
          $this.find(".foswikiErrorMessage").remove();
          $.blockUI({
            message:"<h1>Updating comment "+index+" ...</h1>",
            fadeIn: 0,
            fadeOut: 0
          });
        },
        success: function(data, statusText, xhr) {
          $.unblockUI();
          if(data.error) {
            $errorContainer.after("<div class='foswikiErrorMessage'>Error: "+data.error.message+"</div>");
          } else {
            loadComments();
          }
          $("#cmtUpdateComment").dialog("close");
        },
        error: function(xhr, msg) {
          var data = $.parseJSON(xhr.responseText);
          $.unblockUI();
          $errorContainer.after("<div class='foswikiErrorMessage'>Error: "+data.error.message+"</div>");
          $("#cmtUpdateComment").dialog("close");
        }
      });
    });

    /* ajaxify confirm delete form ******************************************/
    $(".cmtConfirmDeleteForm").livequery(function() {
      var $form = $(this),
          $errorContainer,
          id, index;

      $form.ajaxForm({
        beforeSubmit: function() {
          id = $form.find("input[name='comment_id']").val();
          index = $form.find("input[name='index']").val();
          $errorContainer = $this.find("a[name='comment"+id+"']").parent().parent();
          $this.find(".foswikiErrorMessage").remove();
          $.blockUI({
            message:"<h1>Deleting comment "+index+" ...</h1>",
            fadeIn: 0,
            fadeOut: 0
          });
        },
        success: function(data, statusText, xhr) {
          $.unblockUI();
          if(data.error) {
            $errorContainer.after("<div class='foswikiErrorMessage'>Error: "+data.error.message+"</div>");
          } else {
            loadComments();
          }
          $("#cmtConfirmDelete").dialog("close");
        },
        error: function(xhr, msg) {
          var data = $.parseJSON(xhr.responseText);
          $.unblockUI();
          $errorContainer.after("<div class='foswikiErrorMessage'>Error: "+data.error.message+"</div>");
          $("#cmtConfirmDelete").dialog("close");
        }
      });
    });

    /* ajaxify confirm approve form *****************************************/
    $(".cmtConfirmApproveForm").livequery(function() {
      var $form = $(this),
          $errorContainer,
          id, index;

      $form.ajaxForm({
        beforeSubmit: function() {
          id = $form.find("input[name='comment_id']").val();
          index = $form.find("input[name='index']").val();
          $errorContainer = $this.find("a[name='comment"+id+"']").parent().parent();
          $this.find(".foswikiErrorMessage").remove();
          $.blockUI({
            message:"<h1>Approving comment "+index+" ...</h1>",
            fadeIn: 0,
            fadeOut: 0
          });
        },
        success: function(data, statusText, xhr) {
          $.unblockUI();
          if(data.error) {
            $errorContainer.after("<div class='foswikiErrorMessage'>Error: "+data.error.message+"</div>");
          } else {
            loadComments();
          }
          $("#cmtConfirmApprove").dialog("close");
        },
        error: function(xhr, msg) {
          var data = $.parseJSON(xhr.responseText);
          $.unblockUI();
          $errorContainer.after("<div class='foswikiErrorMessage'>Error: "+data.error.message+"</div>");
          $("#cmtConfirmApprove").dialog("close");
        }
      });
    });

    /* add reply behaviour **************************************************/
    $this.find(".cmtReply").click(function() {
      var $comment = $(this).parents(".cmtComment:first"),
          commentOpts = $.extend({}, $comment.metadata());

      $this.find(".foswikiErrorMessage").remove();

      loadDialogs(function() {
        $("#cmtReplyComment").dialog("option", "open", function() {
          var $this = $(this);
          $this.find(".cmtCommentIndex").text(commentOpts.index);
          $this.find("input[name='ref']").val(commentOpts.comment_id);
        }).dialog("open");
      });

      return false;
    });

    /* add edit behaviour ***************************************************/
    $this.find(".cmtEdit").click(function() {
      var $comment = $(this).parents(".cmtComment:first"),
          commentOpts = $.extend({}, $comment.metadata());

      $this.find(".foswikiErrorMessage").remove();

      loadDialogs(function() {
        $.jsonRpc(foswiki.getPreference("SCRIPTURL")+"/jsonrpc", {
          namespace: "MetaCommentPlugin",
          method: "getComment",
          params: {
            "topic": opts.web+"."+opts.topic,
            "comment_id": commentOpts.comment_id
          },
          success: function(json, msg, xhr) {
            $.unblockUI();
            $("#cmtUpdateComment").dialog("option", "open", function() {
              var $this = $(this);
              $this.find("input[name='comment_id']").val(commentOpts.comment_id);
              $this.find("input[name='index']").val(commentOpts.index);
              $this.find(".cmtCommentIndex").text(commentOpts.index);
              $this.find("input[name='title']").val(json.result.title);
              $this.find("textarea[name='text']").val(json.result.text);
            }).dialog("open");
          },
          error: function(json, msg, xhr) {
            $.unblockUI();
            $comment.parent().append("<div class='foswikiErrorMessage'>Error: "+json.error.message+"</div>");
          }
        });
      });
      return false;
    });

    /* add delete behaviour *************************************************/
    $this.find(".cmtDelete").click(function() {
      var $comment = $(this).parents(".cmtComment:first"),
          commentOpts = $.extend({}, $comment.metadata());

      $this.find(".foswikiErrorMessage").remove();

      loadDialogs(function() {
        $("#cmtConfirmDelete").dialog("option", "open", function() {
          var $this = $(this);
          $this.find("input[name='comment_id']").val(commentOpts.comment_id);
          $this.find("input[name='index']").val(commentOpts.index);
          $this.find(".cmtCommentNr").text(commentOpts.index);
          $this.find(".cmtAuthor").text(commentOpts.author);
          $this.find(".cmtDate").text(commentOpts.date);
        }).dialog("open");
      });

      return false;
    });

    /* add approve behaviour ************************************************/
    $this.find(".cmtApprove").click(function() {
      var $comment = $(this).parents(".cmtComment:first"),
          commentOpts = $.extend({}, $comment.metadata());

      $this.find(".foswikiErrorMessage").remove();

      loadDialogs(function() {
        $("#cmtConfirmApprove").dialog("option", "open", function() {
          var $this = $(this);
          $this.find("input[name='comment_id']").val(commentOpts.comment_id);
          $this.find("input[name='index']").val(commentOpts.index);
          $this.find(".cmtCommentNr").text(commentOpts.index);
          $this.find(".cmtAuthor").text(commentOpts.author);
          $this.find(".cmtDate").text(commentOpts.date);
        }).dialog("open");
      });
      return false;
    });

    // work around blinking twisties
    setTimeout(function() {
      $this.find(".twistyPlugin").show();
    }, 1);
  });
});
