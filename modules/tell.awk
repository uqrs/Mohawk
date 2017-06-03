###############################################################################
# Tell Library
###############################################################################
# VAR command SED_PATH
# LOCALVAR C_tell
# RESPOND PRIVMSG
###############################################################################
# Tells are messages that can be left for other individuals by certain users.
# These messages will be delivered to the user upon join. Syntax:
# !tell recipient message
###############################################################################
# Tells are stored in a tellfile, one tell per line in the format:
# recipient sender message\n
# The tellfile resides in cache/tellfile.
# To prevent an incredible amount of file lookups everytime someone sends a
# message, we declare a local variable called 'recipients'. 'recipients' is a
# space separated list of individuals who have messages queued for them.
# Checking this variable should be less resource intensive than checking the
# tellfile every time. The 'recipients' variable is updated everytime a tell is
# sent.
###############################################################################
# Get all the recipients from the tellfile and prepare the recipients var:
BEGIN {
    # Retrieve all recipients and append them to the 'recipients' variable.
    while ( (getline < "cache/tellfile") > 0 ) {
        recipients=(recipients " " tolower($1))
    }; close("cache/tellfile")

    # Don't fuss about case:
    IGNORECASE=1;

    # Set a default:
    C_tell || (C_tell="tell");
}
###############################################################################
# Begin Regular Command Parsing.
$4 ~ ( ":[" command "]" C_tell "$" ) {
    # Reset contents.
    delete contents;

    # Retrieve the sender, desired recipient, and the message by capturing them with
    # match. Store them in array contents[].
    match( $0 , /^:([^!]+)![^:]+:[^ ]+\s+([^ ]+) (.+)$/ , contents )

    # If there aren't three elements in contents[], then let them know the
    # syntax:
    if ( !contents[3] ) {
        print "PRIVMSG " $3 " :Syntax: " substr(command,1,1) "tell recipient Message"; done();
    }

    # Else, add a new entry to the tellfile:
    print (contents[2] " " contents[1] " " contents[3]) >> "cache/tellfile"

    # If the recipients' name does not appear in the recipients string:
    if ( recipients !~ contents[2] ) {
        # Then append it.
        recipients=(recipients " " contents[2])
    }

    # Set an affirmative message to out:
    print "PRIVMSG " $3 " :Message queued appropriately.";
    close("cache/tellfile");
}

###############################################################################
# GET TELLS QUEUED FOR THIS USER
###############################################################################
# If the username is in the "recipients" string, open the tellfile in a loop,
# and look for lines matching the recipient's name. If it matches, send it.
# If not, then put it in an array and store it later.
###############################################################################
recipients ~ gensub( /^:([^!]+)!.+$/ , "\\1" , "G" , $0 ) {
    # Reset these variables.
    sender = "";amount=0; user="";

    # Permanently store user.
    user=gensub( /^:([^!]+)!.+/ , "\\1" , "G" , $0 )

    # Use sed to extract only messages intended for this user.
    GET_TELLS=(SED_PATH " -Ei '/^" user " /I { w /dev/stdout\nd }' cache/tellfile")

    # Keep reading for output:
    while ( (GET_TELLS | getline) > 0 ) {
        print gensub(/^ *([^ ]+) +([^ ]+) +(.+)/,"PRIVMSG \\1 :\\2 sent: \\3","g")
    }
    # Close our process:
    close(GET_TELLS)

    # Remove the user from recipients:
    gsub( user , "" , recipients )
}
