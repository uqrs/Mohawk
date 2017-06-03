###############################################################################
# ARCHLINUX REPOSITORY SEARCH
###############################################################################
# LOCALVAR url default_format C_pacman
# VAR command
# RESPOND PRIVMSG
###############################################################################
# Performs searches on the Arch Linux repository. Doesn't use pacman, but
# rather looks them up via the web interface. Full web interface instructions
# at: https://wiki.archlinux.org/index.php/Official_repositories_web_interface
# Essentially, it curls from url/packages/search/json/?q=packagename, retrieves
# the desired json, parses it, formats it, then returns it to chat.
# Requires curl.
###############################################################################
# PKG-INFO - ArchLinux Package Info Fetcher
###############################################################################
# Fetches information on a specific package in the ArchLinux repositories.
#
# The sole argument must be the name of a package in the (official) ArchLinux
# (thus only for i686 and x86_64) repositories.
# == ARCHITECTURE FLAGS - USE ONLY ONE ==
# --x86_64, --x64, --64bit, --64, -x
#	Search only for x86_64 packages.
# --i686, --x86, --32bit, --32, -i
#	Search only for i686 packages.
# --any, -a
# 	Search for any architectures
# == SEARCH MODE FLAGS - USE ONLY ONE ==
# --description, --desc, -D, -Q
#	Search only by package description.
# --name -n -N
#	Search only by package name (default)
# --all --both -A
#	Search by package names and description.
# == MISC. OPTIONS ==
# --result, --page, -p, -r=n
#	Return only the nth result.
# --format, -f=fstr
#	Control output format. See below.
# == FORMAT ==
# The output format is a string with several escape sequences that correspond
# to certain details:
# \n - pkgname - name of the package.
# \v - pkgver - version of the package.
# \r - repo - repository package is in.
# \m - maintainer - maintainer of package.
# \M - packager - packager of package.
# \d - description - description of package.
# \D - depends - dependencies of package.
# \l - license - licenses of package.
# \u - last update - when package was last updated.
# \b - build date - when the package was builded.
# \s - compressed size - package size when compressed.
# \S - installed size - package size when installed.
# \f - filename - name of package file.
# \P - provides - provides.
# \g - groups - groups this package is in.
# \C - conflicts - conflicts with packages.
# \a - architecture - this package's architecture.
# \R - replaces - which packages this one replaces.
# \U - url - url to package source
###############################################################################
# Include our specialised argument parser:
@include "./src/arg3.awk"       # Supplies arg3()
@include "./src/uri_encode.awk" # Supplies uri_encode()
###############################################################################
# Apply default variables and 
BEGIN {
    PAC_ALLOW=\
    "x86_64[x x64 x86_64 64bit 64]1/^$/{&arch=x86_64} " \
    "i686[i i686 x86 32bit 32]1/^$/{&arch=i686} " \
    "any[a any]1/^$/{}! " \
    "search_all[A all both]2/^$/{?q=} " \
    "search_desc[D Q d desc description]2/^$/{?desc=} " \
    "search_name[N n name]2/^$/{?name=}! " \
    "format[f format]3/.+/ " \
    "result[r p result page]4/^[0-9]+$/"

    url || (url="https://www.archlinux.org/")
    C_pacman || (C_pacman="(pkg-info|pacman)$")
    command || (command="!")
}

$4 ~ ( ":[" command "]" C_pacman "$" ) {
    # Reset essential variables:
    json="";result_amount=0;dirty=0;
    delete flags; delete results; delete kvpairs; delete keyval;

    # Remove fields 1-4: we don't need these anymore (except the channel name,
    # which we store in another variable.)
    channel = $3
    $1 = "" ; $2 = "" ; $3 = "" ; $4 = "" 

    # Parse our arguments:
    success=arg3(PAC_ALLOW)
    # If an error was raised by arg3:
    if ( success == 1 ) {
        print "PRIVMSG " channel " :" flags[0];
        done();
    }

    # If no package has been supplied, then throw a fuss:
    if ( !( $0 ) ) {
        print "PRIVMSG " channel " :Usage: !pkg-info [--any|--x86_64|--i686] [--all|--desc|--name] package-name"
        done();
    }

    # If no number was specified, set it to 1:
    if ( !("result" in flags) ) { flags["result"] = 1 }
    if ( !("format" in flags) ) {
        if ( default_format ) { format = default_format }
        else { format ="\\n [\\v] [From \\r] [\\a] (\\d); [\\l] (\\U)" }
    } else { format = flags["format"] }

    # Turn the format into something usable:
    gsub(/\\n/,"\001pkgname\001",format)
    gsub(/\\v/,"\001pkgver\001",format)
    gsub(/\\r/,"\001repo\001",format)
    gsub(/\\m/,"\001maintainers\001",format)
    gsub(/\\M/,"\001packager\001",format)
    gsub(/\\d/,"\001pkgdesc\001",format)
    gsub(/\\D/,"\001depends\001",format)
    gsub(/\\l/,"\001licenses\001",format)
    gsub(/\\u/,"\001last_update\001",format)
    gsub(/\\b/,"\001build_date\001",format)
    gsub(/\\s/,"\001compressed_size\001",format)
    gsub(/\\S/,"\001installed_size\001",format)
    gsub(/\\f/,"\001filename\001",format)
    gsub(/\\P/,"\001provides\001",format)
    gsub(/\\g/,"\001groups\001",format)
    gsub(/\\C/,"\001conflicts\001",format)
    gsub(/\\a/,"\001arch\001",format)
    gsub(/\\R/,"\001replaces\001",format)
    gsub(/\\U/,"\001url\001",format)
    gsub(/\\./,"",format)

    # GET_PACKAGE is the process that retrieves the json for the desired
    # package from online. The grep statements trim the entire thing down a
    # bit.
    GET_PACKAGE="curl '" ( url "/packages/search/json/" flags[-3]["2"] uri_encode($0) flags[-3]["1"] ) "' 2> /dev/null | " \
    "grep -Eo '\"results\": \\[(.*)\\]}$' | grep -Eo '\\[(.*)\\]'"
    GET_PACKAGE | getline json
    close(GET_PACKAGE)
    # So we don't have to deal with quoted strings... turn all escaped doublequotes
    # into NULLs.
    gsub( /\\"/ , "\000" , json )

    # Take each result and index them separately in results.
    patsplit( json , results , /{[^}]+}/ )

    # Iterate over the results.
    for ( result in results ) {
        # Result_amount is the amount of results found.
        result_amount++
        # Only add this number to the output if the specified number
        # matches result_amount.
        if ( ( result_amount == flags["result"] )  ) {
            # This monstrosity takes each key value pair, and puts them in array kvpairs.
            patsplit( results[result] , kvpairs , /"([^"]+)"(:\s*(\[[^\]]*\]|"[^"]*"|[0-9\.Ee\+\-]+|null|true|false),?|,?)/ )
            # Iterate over each pair.
            for ( field in kvpairs ) {
                # This monstrosity takes the key and the value, and puts them in
                # keyval[1] and keyval[2] respectively.
                match( kvpairs[field] , /"([^"]+)":\s*(\[[^\]]*\]|"[^"]*"|[0-9\.Ee\+\-]+|null|true|false),?/ , keyval )
                gsub( /["\[\]\{\}]/ , "" , keyval[2] )
                gsub( "\000" , "\"" , keyval[2] )
                gsub( "\001" keyval[1] "\001" , keyval[2] , format )
            }
        }
    }
    # Clean the format string:
    dirty=gsub(/\001/,"",format)

    # If the result was dirty, an invalid page was probably specified:
    if ( dirty ) {
        print "PRIVMSG " channel " :Unclean format. Invalid page?"
    # Else, if there's no result:
    } else if ( result_amount == 0 ) {
        # Tell them there's none.
        print "PRIVMSG " channel " :No results for query '" $0 "'"
    } else { # Else, if there is a result:
        # Print it.
        print "PRIVMSG " channel " :[" flags["result"] "/" result_amount "] " format
    }
}