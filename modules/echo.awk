###############################################################################
# Echo - Revised memo storage/retrieval system.
###############################################################################
# VAR command cmd_plain SED_PATH SED_SANDBOX
# LOCALVAR echoes verbose color C_echo
# RESPOND PRIVMSG
###############################################################################
# Allows users to store and retrieve messages using 'echo', and retrieve them
# using 'cat'.
# @echoes refers to the file echoes are stored in.
# @default_verbosity refers to the default verbosity level- 0, 1, or 2. This
# verbosity level is assumed if neither the -v or -q flags have been
# specified.
# @color is one of 'always', 'auto', or 'never'. It dictates when output is
# coloured.
#
# ==ECHO SYNTAX==
# echo [flags] file_message
#
###############################################################################
# Echoes are stored in a file @echoes. In this file, echoes are stored in
# fields delimited by ASCII 001s. These fields are:
# echo_name - type - contents
# echo_name is the name of the echo, 'type' is either ' ' or 'l' (if it's
# the latter, it's a symbolic link), and 'contents' are the contents of the
# echo itself.
############################################################################### 
# Include our arg3() argparsing module:
@include "./src/arg3.awk" # Provides arg3()
###############################################################################
# Create allowed-strings for 'cat' (CAT_ALLOW) and 'echo' (ECHO_ALLOW)
BEGIN {
    CAT_ALLOW=\
    "raw[raw r]1/^$/ " \
    "nocol[nocolours nocolors C]1/^$/"

    ECHO_ALLOW=\
    "ln[L ln link]1/^$/ " \
    "rm[R rm remove]1/^$/ " \
    "mv[M mv move]1/^$/ " \
    "cat[C cat catenate]1/^$/ " \
    "mv,ln->clobber[N clobber force]5/^$/{} " \
    "mv,ln->no-clobber[n no-clobber]5/^$/{-n}! " \
    "ls[S ls list]1/^[0-9]*$/ " \
    "ls->expand[e expand]/^$/ " \
    "ls->literal[none literal]9/^$/{l} " \
    "ls->simple[simple]9/^$/{s}! " \
    "ls->regex[regex]9/^$/{r} " \
    "ls->case[case case-sensitive I]10/^$/{}! " \
    "ls->ignore_case[ignore_case ignorecase nocase i]10/^$/{-i} " \
    "ls->page[p page]11/^$/ " \
    "sed[D sed s]1/^$/ " \
    "help[h help usage]1/^$/ " \
    "sed->extended[extended E r]3/^$/{-r} " \
    "sed->POSIX[POSIX P]3/^$/{--posix}! " \
    "sed->follow[follow-symlinks follow y]6/^$/{f}! " \
    "sed->no-follow[no-follow Y clone]6/^$/{n}" \
    "sed->dry[d dry]4/^$/" \
    "format[ircf format f]2/^$/ " \
    "no_format[no-ircf no-format F]2/^$/ " \
    "verbose[v verbose]4m2/^$/ " \
    "quiet[q quiet]4/^$/ "

    # Safe-ify the quotes in @echoes:
    gsub(/'/,"'\\''",echoes); #"

    # 'echoes' defaults to 'cache/echo':
    echoes || (echoes="cache/echo")
    # Set 'verbose' to the default:
    verbose || (verbose=1)
    # Make sure it's a number:
    verbose=strtonum(verbose);

    # Set some more defaults:
    C_echo || (C_echo="(echo|coreutils?|cu|rem|note)")
}
###############################################################################
# Now, we can start the real deal:
$4 ~ ( "^:[" command "]" C_echo "$" ) {
    # Wipe important variables:
    remname="";remname_safe="";result="";PROC="";
    v1r="";v2r="";vdr="";ver="";link_notice="";verbosity="";

    # Remove input records 1-4, keep the channel safe too.
    channel=$3;
    $1="";$2="";$3="";$4="";

    # First, parse our arguments:
    success=arg3(ECHO_ALLOW);

    # If an error was raised, complain:
    if ( success == 1 ) {
        print "PRIVMSG " channel " :" flags[0];
        done();
    }

    # If the help flag was specified, print a notice:
    if ( "help" in flags ) {
        print "PRIVMSG " channel " :[Mohawk/coreutils] Specify any of the following flags without any additional arguments (OR the help flag) for usage: --mv, --rm, --sed, --ln, --ls Supply none of these for usage on echo."
        done();
    }

    # Take the appropriate action dependent on which combination of
    # verbosity flags were specified:
    switch( flags[-1]["4"] ) {
        # If a verbose flag was specified, assign the intensity:
        case "verbose": verbosity=flags[-2]["verbose"]; break;
        # If 'quiet' was specified, assign '0' (quiet)
        case "quiet": verbosity=0; break;
        # Else, assign the default_verbosity:
        default: verbosity=default_verbosity; break;
    }

    # Nuke $1 and remove the leading spaces:
    remname=tolower($1);$1="";
    gsub(/^\s*/,"");

    # If remname contains any dashes or underscores:
    gsub(/[-_]/," ",remname);

    # Remname_safe is a RegEx-safe version of remname.
    remname_safe=gensub(/[\.\^\$\\\[\]\|\(\)\*\+\?\{\}\/]/,"\\\\&","G",remname);
    # Safe-ify all single quotes in remname_safe:
    gsub(/'/,"'\\''",remname_safe);

    # If 'format' has been specified:
    if ( "format" in flags ) {
        # Substitute in our easy-format options:
        gsub(/\\b/,"\002") 
        gsub(/\\c/,"\003")
        gsub(/\\i/,"\029")
        gsub(/\\u/,"\031")
        gsub(/\\r/,"\x0F")
    }

    # Iterate over all possible operations.
    switch ( flags[-1]["1"] ) {
        #######################################################################
        # HANDLE EXECUTION OF SED COMMANDS
        #######################################################################
        case "sed":
            if ( SED_SANDBOX != "yes" ) { ver="Inappropriate sed version- no sandboxing capabilities (not GNU/sed or < 4.3)" }
            else if ( $0 ~ /^\s*$/ ) { ver="[sed/stream edit] Usage: " cmd_plain "echo --sed echo expressions" } else {
                # Check whether the specified file even exists:
                PROC="(grep -iE '^" remname_safe "\001' '" echoes "' &>/dev/null) && echo 0 || echo 1"
                PROC | getline result; close(PROC)
                if ( result == "1" ) {
                    ver="No such file: '" remname "'";
                } else {
                    # Safe-ify these expressions:
                    gsub(/'/,"'\\''",$0)

                    # Check whether the second field is a symbolic link (result is 'l' if it is, ' ' if it isn't.)
                    PROC="(grep -iE '^" remname_safe "\001' '" echoes "' 2>/dev/null | cut -d '\001' -f 2,3)"
                    PROC | getline result
                    # If the result starts with an 'l', it's a symlink...
                    if ( result ~ /^l/ ) {
                        # If the 'follow' flag has been specified, OR we're dry-running:
                        if ( (flags[-3]["6"] == "f") || ("dry" in flags) ) {
                            # Substitute remname_safe for whatever the symbolic link points to:
                            remname_safe=gensub(/[\.\^\$\\\[\]\|\(\)\*\+\?\{\}\/]/,"\\\\&","G",substr(result,3))

                            # Allocate some text for the verbose output results explaining it linked somewhere:
                            link_notice=" (which '" substr(result,3) "' refers to)"
                            # Else, if we're not supposed to follow:
                        } else {
                            # Turn the symbolic link into a copy of what it points to:
                            PROC="(" SED_PATH " -Ei 's/^" remname_safe "\001.+/" remname "\001 \001'$(grep -Ei '^" substr(result,3) "\001' '" echoes "' | cut -d '\001' -f 3 | " SED_PATH " -E 's/([\\\\\\/])/\\\\1/')'/' '" echoes "' 2>/dev/null);"
                            system(PROC); close(PROC);
                        }
                    }

                    # 'result' holds the altered string. The final character is '1' if an error was raised, a '0' otherwise.
                    PROC="(grep -iE '^" remname_safe "\001' '" echoes "' 2>/dev/null | cut -d '\001' -f 3 | " \
                    SED_PATH " " flags[-3]["3"] " --sandbox '" $0 "' && echo 0 || echo 1) 2>&1 | tr -d '\\n'"
                    PROC | getline result ; close(PROC)

                    # If the final character is a one, an error was raised:
                    if ( substr(result,length(result)) == "1" ) {
                        ver=substr(result,1,length(result)-1)
                    } else if ( !("dry" in flags) ) {
                        # Substitute in the proper new echo.
                        print "RESULT: " result >> "/dev/stderr"
                        PROC="(" SED_PATH " -Ei 's/^" remname_safe "\001([ l])\001.+/" remname_safe "\001\\1\001" gensub(/[\/\\]/,"\\\\1","G",substr(result,1,length(result)-1)) "/g' '" echoes "') &>/dev/stderr"
                        system(PROC) ; close(PROC);
                        vdr="";v1r=("Successfully updated " remname link_notice);v2r=(remname link_notice " is now: '" substr(result,1,length(result)-1) "\x1F'");
                    } else { 
                        vdr=substr(result,1,length(result)-1); v1r=vdr; v2r=vdr;
                    }
                }
            } break;
        #######################################################################
        # HANDLE LINKING FILES
        #######################################################################
        case "ln":
            if ( $1 ~ /^\s*$/ ) { ver="[ln/link] Usage: " cmd_plain "echo --ln [--clobber|--no-clobber] source destination" } else {
                # Check whether the specified file even exists:
                PROC="(grep -iE '^" remname_safe "\001' '" echoes "' &>/dev/null) && echo 0 || echo 1"
                PROC | getline result; close(PROC)
                if ( result == "1" ) {
                    ver="No such file: '" remname "'";
                } else {
                    # Turn the underscores/dashes in the first input record into spaces:
                    gsub(/[-_]/," ",$1)

                    # Check whether the first field is a symbolic link (result is 'l' if it is, ' ' if it isn't.)
                    PROC="(grep -iE '^" remname_safe "\001' '" echoes "' 2>/dev/null | cut -d '\001' -f 2,3)"
                    PROC | getline result
                    # If the result starts with an 'l', it's a symlink...
                    if ( result ~ /^l/ ) {
                        # And create a notice:
                        link_notice=" (which " remname " refers to)"

                        # Now, dereference it:
                        remname_safe=gensub(/[\.\^\$\\\[\]\|\(\)\*\+\?\{\}\/]/,"\\\\&","G",substr(result,3))
                        remname=substr(result,3)
                    }

                    # Check whether the destination exists:
                    PROC="(grep -iE '^" gensub(/[\/\.\^\$\\\[\]\|\(\)\*\+\?\{\}]/,"\\\\&","G",$1) "\001' '" echoes "' &>/dev/null) && echo 1 || echo 0"
                    PROC | getline result; close(PROC)
                    # If it does, and no-clobber is enabled, complain:
                    if ( (result == "1") && (flags[-3]["5"] == "-n") ) {
                        ver="Entry '" $1 "' exists; no-clobber enabled.";
                    } else {
                        # Remove the older entry if it exists, then add a link to remname:
                        PROC="(" SED_PATH " -Eni '/^" gensub(/[\/\.\^\$\\\[\]\|\(\)\*\+\?\{\}]/,"\\\\&","G",$1) "\001/ !p' '" echoes "' 2>/dev/null); " \
                        "(echo '" $1 "\001l\001" remname_safe "' >> '" echoes "')"
                        system(PROC); close(PROC);
                        # Specify the output messages:
                        v1r=("Linked entry to '" remname "'" link_notice);v2r=("Linked entry '" $1 "' to '" remname "'" link_notice);vdr="";
                        # Notify that files've been clobbered if appliccable.
                        if ( result == "1" ) {v1r=(v1r "; Clobbered old file."); v2r=(v2r "; Clobbered old '" $1 "'"); }
                    }
                }
            } break;
        #######################################################################
        # HANDLE REMOVAL OF FILES
        #######################################################################
        case "rm":
            if ( remname ~ /^\s*$/ ) { ver="[rm/removal] Usage: " cmd_plain "echo --rm echo" } else {
                # Check to see whether the entry appears in echoes. If it does, remove it. If it doesn't, complain.
                PROC="(grep -iE '^" remname_safe "\001' '" echoes "' &>/dev/null) && " \
                "( (" SED_PATH " -Eni '/^" remname_safe "\001/ !p' '" echoes "' 2>/dev/null) && " \
                "( echo 0 ) ) || (echo 1)"
                PROC | getline result; close(PROC);

                # If the result was '0', meaning a removal was done, also clean up all symlinks pointing to the removed file:
                if ( result == "0" ) {
                    PROC=(SED_PATH " -Ei '/^[^\001]+\001l\001" remname_safe "\\s*$/I { w /dev/stdout\nd }' '" echoes "' | wc -l")
                    PROC | getline amnt ; close(PROC)
                    if ( amnt != "0" ) { link_notice =(" and " amnt " broken links.") }
                }

                # Allocate the appropriate messages:
                switch (result) {
                    case "0": v1r="Successfully deleted entry" link_notice; v2r="Successfully deleted entry '" remname "'" link_notice; vdr=""; break
                    case "1": ver="No such entry: '" remname "'"; break;
                }
            } break;
        #######################################################################
        # HANDLE MOVING OF FILES
        #######################################################################
        case "mv":
            if ( remname ~ /^\s*$/ ) { ver="[mv/moving] Usage: " cmd_plain "echo --mv [--clobber|--no-clobber] source destination" } else {
                # Check whether the specified file exists:
                PROC="(grep -iE '^" remname_safe "\001' '" echoes "' &>/dev/null) && echo 0 || echo 1"
                PROC | getline result; close(PROC)
                # If it doesn't, complain:
                if ( result == "1" ) {
                    ver="No such file: '" remname "'";
                } else {
                    # Turn the underscores/dashes in the first input record into spaces:
                    gsub(/[-_]/," ",$1)

                    # Check whether the destination exists:
                    PROC="(grep -iE '^" gensub(/[\/\.\^\$\\\[\]\|\(\)\*\+\?\{\}]/,"\\\\&","G",$1) "\001' '" echoes "' &>/dev/null) && echo 1 || echo 0"
                    PROC | getline result; close(PROC)
                    # If it does, and no-clobber is enabled, complain:
                    if ( (result == "1") && (flags[-3]["5"] == "-n") ) {
                        ver="Entry '" $1 "' exists; no-clobber enabled.";
                    } else {
                        # Yeah, nice try.
                        gsub(/\//,"\\/",$1)
                        # Remove the older entry if it exists, then move the new one over after verifying it exists.
                        PROC="(" SED_PATH " -Eni '/^" gensub(/[\/\.\^\$\\\[\]\|\(\)\*\+\?\{\}]/,"\\\\&","G",$1) "\001/ !p' '" echoes "' 2>/dev/null); " \
                        "(" SED_PATH " -Ei 's/^" remname_safe "\001/" $1 "\001/' '" echoes "' 2>/dev/null)"
                        system(PROC); close(PROC);

                        # A file was moved- so we need to relink old symlinks:
                        PROC=(SED_PATH " -Ei '/l\001" remname_safe "\\s*$/ { s/l\001" remname_safe "\\s*$/l\001" gensub(/[\/\.\^\$\\\[\]\|\(\)\*\+\?\{\}]/,"\\\\&","G",$1)"/" \
                        "\nw /dev/stdout\n }' '" echoes "' | wc -l")
                        PROC | getline amnt ; close(PROC)
                        if ( amnt != "0" ) { link_notice=(" and relinked " amnt " links.") }

                        # Specify the output messages:
                        v1r=("Moved entry to '" $1 "'" link_notice);v2r=("Moved entry from '" remname "' to '" $1 "'" link_notice);vdr="";
                        # Notify that files've been clobbered if appliccable.
                        if ( result == "1" ) {v1r=(v1r "; Clobbered old file."); v2r=(v2r "; Clobbered old '" $1 "'"); }
                    }
                }
            } break;
        #######################################################################
        # HANDLE CONCATENATION OF FILES
        #######################################################################
        case "cat":
            if ( remname ~ /^\s*$/ ) { ver="[cat] Usage: " cmd_plain "echo --cat echo" } else {
                # In case of cat- remname_safe allows usage of spaces:
                gsub(/[-_]/," ",remname)
                remname_safe=gensub(/[\.\^\$\\\[\]\|\(\)\*\+\?\{\}\/]/,"\\\\&","G",remname)

                # Check whether the specified file exists:
                PROC="(grep -iE '^" remname_safe "\001' '" echoes "' &>/dev/null) && echo 0 || echo 1"
                PROC | getline result; close(PROC)
                # If it doesn't, complain:
                if ( result == "1" ) {
                    ver="No such file: '" remname "'";
                } else {
                    # Turn the underscores/dashes in the first input record into spaces:
                    gsub(/[-_]/," ",$0)
                    # Check whether the second field is a symbolic link (result is 'l' if it is, ' ' if it isn't.)
                    PROC="(grep -iE '^" remname_safe "\001' '" echoes "' 2>/dev/null | cut -d '\001' -f 2,3)"
                    PROC | getline result ; close(PROC)
                    # If the result starts with an 'l', it's a symlink...
                    if ( result ~ /^l/ ) {
                        # So, dereference it:
                        remname_safe=gensub(/[\.\^\$\\\[\]\|\(\)\*\+\?\{\}\/]/,"\\\\&","G",substr(result,3))
                        # And create a notice:
                        link_notice="[@" remname " -> " substr(result,3) "] "
                    }
                    
                    # Now, retrieve the contents:
                    PROC="(grep -iE '^" remname_safe "\001' '" echoes "' 2>/dev/null | cut -d '\001' -f 3)"
                    PROC | getline result ; close(PROC)
                    vdr=result; v1r=(link_notice result); v2r=v1r;
                }
            }

            break;
        #######################################################################
        # HANDLE ECHO LISTING
        #######################################################################
        # Handle listing of echoes.
        case "ls":
            # Let the arguments for 'ls' default to 1.
            if ( flags["ls"] ~ /^\s*$/ ) { flags["ls"]=1 }
            # If remname_safe is empty, set the mode to 'r' and the pattern to '.':
            if ( remname_safe ~ /^\s*$/ ) {
                flags[-3]["9"]="r"; search=".";
            }

            # First, we take appropriate action dependent on the pattern mode
            # given- 'l' (literal filenames only), 's' (simple matching- *
            # and ?) and 'r' (regex matching).
            #
            # 's' is treated as the default in order to sort-of simulate
            # most common shells.
            #
            # With 's' and 'l', all search queries are anchored to the
            # beginning of the string:
            # e.g. $0 = 'ab', then the pattern used will be: '^ab'. This is
            # done because usually, when searching through echoes, often
            # this is within the best interests of the command's caller.
            #
            # Of course, using 'r', the anchor is not assigned. This is
            # because when explicitly using regular expression, correctness
            # is often favoured over convenience.
            switch ( flags[-3]["9"] ) {
                case "l": search="^" gensub(/[\.\^\$\\\[\]\|\(\)\*\+\?\{\}\/]/,"\\\\&","G",remname); break
                case "r": search=remname ; break
                default: 
                    # First, turn all double-backslashes into NULLs:
                    gsub(/\\\\/,"\000",remname);
                    # Turn all literal *s and literal ?s into ASCII 001 and 002s:
                    gsub(/\\\*/,"\001",remname);
                    gsub(/\\\?/,"\002",remname);
                    # Literalise the rest:
                    remname=gensub(/[\.\^\$[\]\|\(\)\+\{\}\/]/,"\\\\&","G",remname);
                    # Now prepend a . to the '*' and '?'s:
                    remname=gensub(/[\?\*]/,".&","G",remname);
                    # Turn the ASCII 001 and 002s back:
                    gsub(/\001/,"\\*",remname);
                    gsub(/\002/,"\\?",remname);
                    # Turn all NULLs back into single backslashes, anchor
                    # the string, and assign it to 'search':
                    search="^" gensub(/\000/,"\\","G",remname); break;
            }
            # Safe-ify our pattern:
            gsub(/'/,"'\\''",search);

            # If no page has been given, default to page 1:
            if ( !("page" in flags) ) { flags["page"]=1 }
            else { flags["page"]=strtonum(flags["page"]) }

            # Use grep to retrieve only matching lines. Note: flags[-3]["10"]
            # refers to either '-i' or '' (dependent on whether case
            # insensitivity flags have been specified).
            PROC="(cat '" echoes "' | cut -d '\001' -f -2 | grep " flags[-3]["10"] " -E '" search "' | tr '\\n' '\002')"
            PROC | getline results; close(PROC)

            # If no results have been found, then complain:
            if ( results ~ /^\s*$/ ) { ver="No results for '" remname "'" }

            # Separate all results:
            split(results,matches,"\002");
            # Generate an output string:
            for ( matched in matches ) {
                # Split the string:
                split(matches[matched],parts,"\001");
                # If it's a symlink, append an '@':
                if ( parts[2] == "l" ) { vdr=vdr "  \002\00311" parts[1] "\x0F@" }
                # Else just let it be a regular match:
                else { vdr=vdr "  " parts[1] }
            } delete matches;delete parts;
            # Remove leading spaces:
            gsub(/^\s*/,"",vdr);
            # Copy everything over.
            v1r=vdr; v2r=vdr;
            break;
        #######################################################################
        # HANDLE ECHOING NEW DATA
        #######################################################################
        # Handle just adding/revising an entry normally:
        default:
            if ( remname ~ /^\s*$/ ) { ver="[echo] Usage: " cmd_plain "echo name contents" } else
            # If the echo's name is over the maximum (32), complain:
            if ( length(remname) > 32 ) { ver="The echo's name length (" length(remname) ") exceeds the maximum permitted length (32)." }
            else {
                # Check whether the echo's name is already allocated to a symlink.
                PROC="(grep -iE '^" remname_safe "\001' '" echoes "' 2>/dev/null | cut -d '\001' -f 2,3) || echo ' '"
                PROC | getline result
                # If the result is a symlink, dereference it:
                if ( result ~ /^l/ ) {
                    # Allocate some text for the verbose output results explaining it linked somewhere:
                    link_notice=" (which '" remname "' refers to)"

                    # Substitute remname_safe for whatever the symbolic link points to:
                    remname_safe=gensub(/[\.\^\$\\\[\]\|\(\)\*\+\?\{\}\/]/,"\\\\&","G",substr(result,3))
                    remname=substr(result,3)
                }

                # Check whether 'remname' appears in the echoes file. If so, use sed to replace it with the new entry. Else, use echo to add an entry.
                PROC="(grep -iE '^" remname_safe "\001' '" echoes "' &>/dev/null) && " \
                "( (" SED_PATH " -Ei 's/^" remname_safe "\001([ l])\001.+/" remname "\001\\1\001" gensub(/\//,"\\/","G",$0) "/' '" echoes "' 2>/dev/null) && " \
                "( echo 0 ) ) || " \
                "( (echo '" remname "\001 \001" $0 "' >> '" echoes "') && " \
                "( echo 1 ) )"
                PROC | getline result; close(PROC);
                # Allocate appropriate messages:
                switch (result) {
                    case "0": v1r="Successfully revised entry."; v2r="Successfully revised entry '" remname "'" link_notice; vdr=""; break
                    case "1": v1r="Successfully added entry."; v2r="Successfully added entry '" remname "'" link_notice; vdr=""; break
                }
            } break;
    }

    # If an error was raised, print that:
    if ( ver != "" ) { print "PRIVMSG " channel " :" ver ; done(); } else {
    # Else, print the appropriate notice for the given verbosity level:
        switch ( verbosity ) {
            case 2: print "PRIVMSG " channel " :" v2r ; break;
            case 1: print "PRIVMSG " channel " :" v1r ; break;
            case 0: print "PRIVMSG " channel " :" vdr ; break;
        }
    }
}