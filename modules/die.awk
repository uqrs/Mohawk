###############################################################################
# LINUX MANPAGE SEARCH
###############################################################################
# VAR command
# LOCALVAR url C_die
# RESPOND PRIVMSG
###############################################################################
# Retrieves manual pages from https://linux.die.net/man (which you should put as
# the @url unless the site's moved)
# Syntax:
# RE: [0-9A-Za-z_\-]+\([1-8ln]?\)
# Retrieves either a manual page from the first section it can find if no
# sections have been specified. Else, it retrieves a manual page from the
# desired sections. Uses curl.
#
# Because FFT is such a fussy little shit- here's a !man / !die command:
# Syntax: !man (section) page
###############################################################################
BEGIN {
    url || (url="https://linux.die.net/man")
    C_die || (C_die="(die|man)")
}

$4 ~ ( ":[" command "]" C_die "$" ) {
    # We are TOTALLY not cheating by turning the fourth input record into a
    # spoofed command by taking the argument(s) and generating a new string
    # from it.

    # If the fifth argument starts with a '-', then it must be a section flag.
    if ( $5 ~ /^-/ ) {
        match($5,/s([1-8ln]+)/,sectnum)
        $5 = $6
        $6 = ""
        # If no -s flag has been found, throw an error.
        if ( !sectnum[1] ) {
            print "PRIVMSG " $3 " :Inappropriate flags supplied."
            done();
        }
    }

    # Modify the fourth input record.
    $4 = $5 "(" sectnum[1] ")"
}

$4 ~ /^:?[0-9A-Za-z_\-]+\([1-8ln]?\)\s*$/ {
    # Reset essential variables:
    delete desired; output="";

    # First, retrieve the manual's name (desired[1]) and section (desired[2])
    match( $4 , /^:?([0-9A-Za-z_\-]+)\(([1-8ln]?)\)/ , desired )

    # If no section has been specified:
    if ( !desired[2] ) {
        # Retrieve the first letter of the article name, and retrieve the index
        # page for that letter. Next, grep the desired articles, and then use
        # sed to turn them into results.
        GET_PAGE="curl '" url "/" substr( desired[1] , 1 , 1 ) ".html' 2> /dev/null | " \
        "grep -oE '" desired[1] "\">" desired[1] "</a>\\(.\\)<dd>.+' | " \
        "sed -ne 's|" desired[1] "\">\\(" desired[1] "\\)</a>.\\(.\\).<dd>\\(.*\\)|\\1(\\2) \\3 (" url "/\\2/\\1); |p' | " \
        "tr '\\n' ' '"
    } else {
        # Retrieve the article directly, and get the title.
        GET_PAGE="curl '" url "/" desired[2] "/" desired[1] "' 2> /dev/null | " \
        "grep -Eo '<title>.*</title>' | sed -ne 's|^<title>\\(.*\\)</title>$|\\1 (" url "/" desired[2] "/" desired[1] ")|p' | " \
        "tr '\\n' ' '"
    }

    # Retrieve the page itself.
    GET_PAGE | getline output;
    close(GET_PAGE);

    # If the output line is missing, or is "404 Not Found - die.net", throw an
    # error.
    if ( (!output) || (output == "404 Not Found - die.net") ) {
        print "PRIVMSG " $3 " :No results for " desired[1] "(" desired[2] ")"
    } else {
        # Else, just print out output:
        print "PRIVMSG " $3 " :" output
    }
}