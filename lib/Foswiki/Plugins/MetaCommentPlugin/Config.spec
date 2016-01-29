# ---+ Extensions
# ---++ MetaCommentPlugin

# **BOOLEAN**
# Enable this flag to allow anonymous commenting if not set otherwise using topic access rights.
$Foswiki::cfg{MetaCommentPlugin}{AnonymousCommenting} = 0;

# **BOOLEAN**
# Enable this replace newline characters in comments with %BR% on display.
$Foswiki::cfg{MetaCommentPlugin}{DisplayNewLines} = 0;

# **STRING**
# Set this to an alternative ACL check (TML) or to 0 or an empty string for the default check.<br/>Recommended setting for KVPPlugin:<em>%<nop>WORKFLOWALLOWS{"comment" emptyIs="0"}%</em>
$Foswiki::cfg{MetaCommentPlugin}{AlternativeACLCheck} = '';

1;

