###############################################################################
# DATE AND TIME RETRIEVER
###############################################################################
# LOCALVAR defaultzone zonelocations C_date
# VAR command
# RESPOND PRIVMSG
###############################################################################
# Outputs date and time. 'nuff naid.
# Syntax:
# RE: !date timezone[/subzone]	
# RE: !date -z timezone[/subzone[/subzone [...]]]
# Will call 'TZ=timezone date', and return it.
# Timezones can be found in /usr/share/zoneinfo/ on most computers (can be
# altered by changing @zonelocations). Another command, called "zoneinfo" will
# be implemented to show a list of available timezones.
# If the timezone is invalid, an error will be thrown.
# EXAMPLE: Show the time in Detroit:
# !date America/Detroit
###############################################################################
# Include our flag parser:
@include "./src/arg3.awk" # Supplies arg3()
###############################################################################
# First, generate our flagparser:
BEGIN {
    DATE_ARG= \
    "date:[date d]1/^$/ " \
    "zoneinfo:[zones zoneinfo z i]1/^$/ " \
    "zoneinfo->page:[p page]2/^[0-9]+$/"

    # Set the defaults if they've not been specified:
    zonelocations || (zonelocations="/usr/share/zoneinfo/")
    defaultzone || (defaultzone="UTC")
    C_date || (C_date="(date|time)")
    command || (command="!")
}
###############################################################################
$4 ~ ( "^:[" command "]" C_date "$" ) {
    # Reset essential variables:
    timeanddate=""; zoneinfo="";line="";

    # Save our channel and wipe the first four record:
    channel=$3
    $1="";$2="";$3="";$4="";

    # Parse our flags:
    success=arg3(DATE_ARG)

    # Print an error if one was raised:
    if ( success == 1 ) {
        print "PRIVMSG " channel " :" flags[0];
        done();
    }

    # If the 'zoneinfo' flag hasn't been specified:
    if ( !("zoneinfo" in flags) ) {
        # First, check to see if a timezone has been specified.
        if ( $1 ) {
            # Safe-ify it to prevent dodgy business.
            gsub( /'/ , "'\\''" , $1 )

            # Check if the timezone even exists by trying to open it:
            getline line < (zonelocations $1)

            # If the timezone is invalid, throw an error.
            if ( !line ) {
                print "PRIVMSG " channel " :No such timezone: '" $1 "'. Call 'date -z' for a list.";
                done();
            }
        } else {
            # If no timezone has been specified, use the default zone.
            $1 = defaultzone
        }

        # Output our time!
        DATE_PROC="TZ='" $1 "' date"
        DATE_PROC | getline timeanddate
        close(DATE_PROC)
        
        # And tell us the date!
        print "PRIVMSG " channel " :" timeanddate
    # Else, if zone information HAS Been called for:
    } else {
        if ( !("page" in flags) ) {
            # If no page number has been specified, default to 1.
            flags["page"]=1
        }

        # First, check to see if an argument that is not 'list' has been specified.
        if ( $1 !~ /^list$/ ) {
            # If so, safe-ify it.
            gsub( /'/ , "'\\''" , $1 )
            # No dodgy business with accessing parent directories.
            gsub( /\.\./ , "" , $1 )
            # Alter zonelocations so it looks somewhere else.
            location = zonelocations $1
        } else {
            # If not, then just show the contents of @zonelocations:
            location = zonelocations
        }

        # I'm going to elaborate on this step by step.
        # > GET_ZONEINFO="RESULT=$( ls -l '" location "' | grep -v .tab | "
        # Store the final variable in $RESULT. First, call ls -l on location
        # to get all the files. Next, have grep remove all entries with ".tab"
        # files.
        #
        # > "sed -Ene 's/^([d-]).+ (.+)$/\\1 \\2/gp' | sort | "
        # This sed statement takes the first character (which is - if the entry is
        # a file, and 'd' if the entry is a directory) and the name of the file,
        # and puts them together. The 'sort' statement sort-of-sorts it neatly.
        #
        # > "sed -Ee 's/d /+/' -e 's/- //' | tr '\\n' ' ' ) ; "
        # This next sed statement turns entries like "d entry" into "+entry", and
        # "- entry" into "entry". Finally, 'tr' puts everything on one single line.
        #
        # > echo -n 'Page [" pagenum[1] "/'`expr $( echo $RESULT | wc -w ) / 40 + 1`'] ' ; " \
        # Now, we print at which mage we currently are.
        #
        # > "LINE=`expr \\( 1 + \\( \\( " pagenum[1] " - 1 \\) \\* 40 \\) \\)`-`expr \\( " pagenum[1] " \\* 40 \\)` ; "
        # Next, we need to resolve our page number. A page is 40 consecutive
        # entries. So, 1-40, 41-80, 81-120, etc. We calculate this as follows:
        # First entry: ( 1 + ( (pagenum[1]-1) * 40 ) )
        # Final entry: ( pagenum[1] * 40 )
        # e.g. pagenum[1]=2
        # First entry: ( 1 + ( ( 2 - 1 ) * 40 ) ) = 41
        # Final entry: ( 2 * 40 ) = 80
        # Thus we get 41-80. We resolve this using expr.
        #
        # And print all the desired fields.
        # "echo $RESULT | cut -d ' ' -f $LINE"
        GET_ZONEINFO="RESULT=$( ls -l '" location "' | grep -v .tab | " \
        "sed -Ene 's/^([d-]).+ (.+)$/\\1 \\2/gp' | sort | " \
        "sed -Ee 's/d /+/' -e 's/- //' | tr '\\n' ' ' ) ; " \
        "echo -n 'Page [" flags["page"] "/'`expr $( echo $RESULT | wc -w ) / 40 + 1`'] ' ; " \
        "LINE=`expr \\( 1 + \\( \\( " flags["page"] " - 1 \\) \\* 40 \\) \\)`-`expr \\( " flags["page"] " \\* 40 \\)` ; " \
        "echo $RESULT | cut -d ' ' -f $LINE"
        # AND DONE.
        
        GET_ZONEINFO | getline zoneinfo
        close(GET_ZONEINFO)

        # If the result is the zone's full path (i.e. they hit the nail right on
        # the head), then show the time in that zone.
        if ( zoneinfo ~ location ) {
            # Retrieve the date...
            DATE_PROC="TZ='" $1 "' date"
            DATE_PROC | getline timeanddate
            close(DATE_PROC)
            # and print it.
            print "PRIVMSG " channel " :" timeanddate
        } else if ( zoneinfo ~ /^Page \[.*\] ./ ) {
            # Else, print the timezones:
            print "PRIVMSG " channel " :Timezones: " zoneinfo
        } else {
            # If no result was given, then throw an error:
            print "PRIVMSG " channel " :No such timezone: '" $1 "'"
        }
    }
}