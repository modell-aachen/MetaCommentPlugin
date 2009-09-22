var cmtUpdater = {};

(function($) {
  // switch on the update dialog for a comment
  cmtUpdater.edit = function(container) {
    container.find(".cmtComment:first").hide();
    //$(".cmtAddComment").hide();
    container.find(".cmtUpdater:first").animate({opacity:'toggle'});
    cmtUpdater.cancelReply();
  };

  // cancel updates 
  cmtUpdater.cancelUpdate = function(container) {
    container.find(".cmtComment:first").animate({opacity:'toggle'});
    //$(".cmtAddComment").show();
    container.find(".cmtUpdater:first").hide();
    container.find(".cmtToolbar:first").hide();
  };

  // delete a comment
  cmtUpdater.submitDelete = function(container) {
    container.find("input[name=cmt_action]").val('delete');
    var form = container.find("form[name=updater]"); 
    if (typeof(foswikiStrikeOne) == 'function') {
      foswikiStrikeOne(form[0]); 
    }
    form.submit();
    container.animate({ opacity:'toggle' }, {
      complete: function () {
        container.remove();
      }
    });
    var outer = container.parents(".cmtComments")
    var counter = outer.find(".cmtCounter");
    var text = counter.html();
    if (text.match(/One/)) {
      counter.remove();
      outer.find(".cmtScroller").remove();
    } else {
      var nrComments = parseInt(text)-1;
      if (nrComments == 0) {
        counter.remove();
        outer.find(".cmtScroller").remove();
      } else {
        counter.html(text.replace(/[0-9]+/, nrComments));
        counter.effect("highlight");
      }
    }
  };
  
  // reply to one comment in threaded mode
  cmtUpdater.reply = function(container) {
    var index = container.find(".cmtCommentNr").html();
    var cmtId = container.find("input[name=cmt_id]:first").val();
    var addForm = $(".cmtAddComment")
    
    addForm.hide();
    addForm.find(".cmtCancel").show();
    addForm.find(".cmtAddCommentTitle1").hide();
    addForm.find("input[name=cmt_ref]").val(cmtId);
    addForm.insertAfter(container.find(".cmtUpdater:first"));

    var redirect = addForm.find("input[name=redirectto]").val();
    redirect = redirect.replace(/#.*$/, "#comment"+index);
    addForm.find("input[name=redirectto]").val(redirect);
    
    var replyTitle = addForm.find(".cmtAddCommentTitle2");
    var newTitle = replyTitle.html();
    if (newTitle.match(/\$index/)) {
      newTitle = newTitle.replace(/\$index/, index);
    } else {
      newTitle = newTitle.replace(/\s*[0-9\.]*$/, " "+index);
    }
    replyTitle.html(newTitle);
    replyTitle.show();
    addForm.animate({opacity:'toggle'}, {
      complete: function() {
        addForm.find("textarea").focus();
      }
    });
  };

  // cancel reply to comment
  cmtUpdater.cancelReply = function() {
    var addForm = $(".cmtAddComment")
    addForm.appendTo(".cmtComments");
    addForm.find(".cmtCancel").hide();
    addForm.find(".cmtAddCommentTitle1").show();
    addForm.find(".cmtAddCommentTitle2").hide();
    addForm.find("input[name=cmt_ref]").val('');

    var redirect = addForm.find("input[name=redirectto]").val();
    redirect = redirect.replace(/#.*$/, "#lastcomment");
    addForm.find("input[name=redirectto]").val(redirect);

    var container = addForm.parents(".cmtCommentContainer:first");
    container.find(".cmtToolbar").show();
  };

  // confirm dialog used by delete action
  cmtUpdater.confirmDialog = function(elem, options) {
    $(elem).modal({ 
      close:false,
      onShow: function(dialog) {
        dialog.data.find("h2 .cmtCommentNr").html(options.index);
        dialog.data.find("#submit").click(function() {
          if (typeof(options.onSubmit) == 'function') {
            options.onSubmit(dialog);
          }
          return false;
        });
        dialog.data.find("#cancel").click(function() {
          if (typeof(options.onCancel) == 'function') {
            options.onCancel(dialog);
          }
          $.modal.close();
          return false;
        });
        $(window).trigger("resize.simplemodal");
      },
    });
  };

  // init the gui of a comment inside the given container
  cmtUpdater.init = function(container) {
    container.find(".cmtComment:first").hover(
      function() {
        $(this).find(".cmtToolbar").show();
      },
      function() {
        $(this).find(".cmtToolbar").hide();
      }
    );

    container.find(".cmtEdit:first").click(function() {
      $(".cmtUpdater").hide();
      $(".cmtToolbar").hide();
      $(".cmtComment").show();
      cmtUpdater.edit(container);
      return false;
    });

    container.find(".cmtReply:first").click(function() {
      cmtUpdater.reply(container);
      return false;
    });

    container.find(".cmtSave:first").click(function() {
      var form = container.find(".UpdaterForm:first"); 
      if (typeof(foswikiStrikeOne) == 'function') {
        foswikiStrikeOne(form[0]); 
      }
      form.submit();
      return false;
    });

    container.find(".cmtCancel:first").click(function() {
      cmtUpdater.cancelUpdate(container);
      return false;
    });

    container.find(".cmtDelete:first").click(function() {
      var index = $("input[name=cmt_index]", container).val();
      cmtUpdater.confirmDialog("#cmtConfirmDelete", {
        onSubmit: function(dialog) {
          cmtUpdater.submitDelete(container);
          $.modal.close();
        },
        index: index
      });
      return false;
    });

    container.find(".UpdaterForm:first").each(function() {
      var $this = $(this);
      var target = $this.parents(".cmtCommentContainer:first");
      $this.ajaxForm({
        success: function (data) {
          var $data = $(data);
          $data = $data.children(); // strip off new cmtCommentContainer
          $data.hide();
          target.html($data);
          cmtUpdater.init(target);
          target.find(".cmtCommentContainer").each(function() {
            cmtUpdater.init($(this));
          });
          $data.animate({opacity:'toggle'});
          target.find(".cmtUpdater:first").hide();
          target.find(".cmtToolbar:first").hide();
          target.effect("highlight", {
            duration:3000
          });
        }
      });
    });
  };

  // onload initialization
  $(function() {
    $(".cmtAddComment .cmtCancel").click(function() {
      cmtUpdater.cancelReply();
      return false;
    });
    $(".cmtCommentContainer").each(function() {
      cmtUpdater.init($(this));
    });
    $(".jqHighlight").effect("highlight");
  });
})(jQuery);
