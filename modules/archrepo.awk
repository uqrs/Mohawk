###############################################################################
# ARCHLINUX REPOSITORY SEARCH
###############################################################################
# LOCALVAR url default_format C_pacman
# VAR command
# RESPOND $2 PRIVMSG
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
# == SEARCH MODE FLAGS - USE ONLY ONE ==
# --description, --desc, -D, -Q
#	Search only by package description.
# --name -n -N
#	Search only by package name (default)
# --all --both -A
#	Search by package names and description.
# --repository, -R=repo,
#	Search only in the specified repository.
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
@include "./src/json.awk"       # json()
@include "./src/arg3.awk"       # arg3()
@include "./src/uri_encode.awk" # uri_encode()

# Apply default variables and such.
BEGIN {
    PAC_ALLOW=\
    "search_all[A all both]2/^$/{?q=} " \
    "search_desc[D Q d desc description]2/^$/{?desc=} " \
    "search_name[N n name]2/^$/{?name=}! " \
    "repository[R repository]5/^(Core|Extra|Testing|Multilib|Multilib-Testing|Community|Community-Testing)$/" \
    "format[f format]3/.+/ " \
    "result[r p result page]4/^[0-9]+$/"

    url || (url="https://www.archlinux.org/")
    C_pacman || (C_pacman="(pkg-info|pacman)")
    command || (command="!")
}

$4 ~ ( "^:[" command "]" C_pacman "$" ) {
    # Reset essential variables:
    json_in="";result_amount=0;dirty=0;
    delete flags; delete results; delete kvpairs; delete keyval;
    delete _jsonout;

    # Remove fields 1-4: we don't need these anymore (except the channel name,
    # which we store in another variable.)
    channel = $3
    $1 = "" ; $2 = "" ; $3 = "" ; $4 = "" 

    # Parse our arguments:
    success=arg3(PAC_ALLOW)
    # If an error was raised by arg3:
    if ( success == 1 ) {
        print "PRIVMSG " channel " :" flags[0]
        done();
    }

    # If no package has been supplied, then throw a fuss:
    if ( !( $0 ) ) {
        print "PRIVMSG " channel " :Usage: !pkg-info [--all|--desc|--name] package-name"
        done();
    }

    # If no number was specified, set it to 1:
    if ( !("result" in flags) ) { flags["result"] = 1 }
    # If a repository was specified, turn it into something URL-Friendly:
    if ( "repository" in flags ) { flags["repository"]="&repo=" flags["repository"] }
    # If no format was specified, use the default format:
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
    # package from online and trims it down to one line.
    GET_PACKAGE="curl '" ( url "/packages/search/json/" flags[-3]["2"] uri_encode($0) flags[-3]["1"] flags["repository"] ) "' 2> /dev/null | tr -d '\n'"
    GET_PACKAGE | getline json_in
    close(GET_PACKAGE)

    # Take the received JSON, and hand it to the parser after allocating an
    # empty destination table:
    split("",_jsonout);
    json(json_in,_jsonout);

    # Store the amount of results we got:
    result_amount=length(_jsonout["results"]);

    # If the result amount is 0, tough luck.
    if ( result_amount == 0 ) {
        # Tell them there's none.
        print "PRIVMSG " channel " :No results for query '" $0 "'"
        done();
    } else if ( flags["result"] > result_amount ) {
        # Else, if the requested result number exceeds the amount of results returned:
        print "PRIVMSG " channel " :Requested result #" flags["result"] ", but only " result_amount " results were found."
        done();
    }

    # Iterate over they key-value pairs in the given result.
    for ( key in _jsonout["results"][flags["result"]] ) {
        # If the value is an array, then just concatenate each entry into
        # one string:
        if ( isarray(_jsonout["results"][flags["result"]][key]) ) {
            for ( i in _jsonout["results"][flags["result"]][key] ) {
                value=value ", " _jsonout["results"][flags["result"]][key][i];
            };
            # Remove the leading comma:
            value=substr(value,3);
        # Else, the value must be a string or number:
        } else {
            value=_jsonout["results"][flags["result"]][key];
        }
        # Now just substitute in the value into the final output string.
        gsub( "\001" key "\001" , value , format )
    }
    # Clean the format string:
    dirty=gsub(/\001/,"",format);

    # If the result was dirty, an invalid page was probably specified:
    if ( dirty ) {
        print "PRIVMSG " channel " :Unclean format. Invalid page?"
        done();
    } else { # Else, if there is a result:
        print "PRIVMSG " channel " :[" flags["result"] "/" result_amount "] " format
        done();
    }
}