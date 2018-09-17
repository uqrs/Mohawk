###############################################################################
# GNU/Awk Interpreter
###############################################################################
# LOCALVAR timeout default_set default_expressions C_gawk
# VAR command
###############################################################################
# Interprets GNU/Awk commands, and returns whatever is printed to STDOUT. We do
# this by running a shell command that pipes an input record into a 'gawk'
# call. The GNU/Awk call itself is run with the '-S' flag, which prevents
# reading of files or system() calls. The call itself is also enclosed in a
# 'timeout' call, as to avoid things like { while (1) {} } halting the program
# indefinitely.
#
# Everything following the call up to the separator is the gawk command.
# Everything following the separator will be treated as the input record. If no
# input record is specified, '' will be used. Whatever the Awk command outputs
# to stdout will be forwarded to IRC. If it outputs multiple lines, then they
# will be concatenated together, substituting the newlines with spaces. If the
# 'expressions' variable is '-e', then every expression in the input record
# (such as \n) will be interpreted. Users may toggle this variable by
# specifying the string 'e' before the gawk instructions. Likewise, 'E'
# disables expression parsing.
#
# Assume '<' is the separator:
# !gawk e { print "Line: " $0 "," } < abc\ndef\nghi
# Outputs to the channel:
# Line: abc, Line: def, Line: ghi
# You may escape the separator if so desired.
###############################################################################
# Include the advanced argparse module:
@include "./src/arg3.awk" # Supplies the arg3() function.
###############################################################################
# Set the arg3 allowedstring:
BEGIN {
    GAWK_FLAGS= \
    "whitespace:[space s spacing]1/^$/{ }! " \
    "no_whitespace:[no-spacing S no-space]1/^$/{} " \
    "expressions:[expr e expressions]2/^$/{-e} " \
    "no_expressions:[no-expr E no-expressions]2/^$/{}! " \
    "separator:[sep separator delimiter d]3/^.$/"

    # Set the defaults in case they don't appear in the configuration file:
    timeout || (timeout=1000)
    default_sep || (default_sep="<")
    expressions || (default_expressions="-e")
    C_gawk || (C_gawk="(g?awk)")
}
###############################################################################
$4 ~ ( "^:[" command "]" C_gawk "$" ) {
    # Reset essential variables:
    outstr="";spacing="";expressions=default_expressions;sep=default_sep; success=0
    delete arr; delete flags;

    # Remove fields 1-4: we don't need these anymore (except the channel name,
    # which we store in another variable.)
    channel = $3;
    $1 = "" ; $2 = "" ; $3 = "" ; $4 = ""; $0;

    # Parse our arguments:
    success=arg3(GAWK_FLAGS)
    # If an error was raised by arg3:
    if ( success == 1 ) {
        print "PRIVMSG " channel " :" flags[0];
        done();
    }

    # If there's a separator in the flags, use it:
    if ( "separator" in flags ) { sep = flags["separator"] }

    # Remove those heading spaces.
    sub( /^\s+/ , "" )
    # First, turn every double backslash into NULLs:
    gsub( /\\\\/ , "\000" )
    # Next, turn every escaped separator into STXs:
    gsub( "\\\\" sep , "\002" )

    # Match the command part, and input record part. Store the former in
    # arr[1], and the latter in arr[2].
    match( $0 , "^(.+)\\s*" sep "\\s?(.*)$" , arr )

    # If erroneous input.
    if ( !(arr[1]) ) {
        print "PRIVMSG " channel " :Usage: !gawk [-e|-E] [-S|-s] gawk_command < input_record";
        done();
    }

    # Turn all STXs back into regular separators:
    gsub( /\002/ , sep , arr[1] )
    gsub( /\002/ , sep , arr[2] )
    # Also turn all NULLs back into double backslashes.
    gsub( /\000/ , "\\\\" , arr[1] )
    gsub( /\000/ , "\\\\" , arr[2] )

    # Safe-ify our input strings:
    gsub( /'/ , "'\\''" , arr[1] )
    gsub( /'/ , "'\\''" , arr[2] )

    # FOR GOD'S SAKE PREVENT INJECTIONS:
    gsub( /\\r/ , "" , arr[1] );

    # Construct a command:
    GAWK_PROC="echo " flags[-3]["2"] " '" arr[2] "' | timeout --foreground 0.5 gawk -S '" arr[1] "' 2>&1 || echo -e '\\000'"

    # Get our output.
    while ((GAWK_PROC | getline output) > 0) {
        # If the output is a NULL, then it has timed out.
        # If no timeout, then:
        if ( output ~ /^\000$/ ) {
            outstr = "gawk: Timed out or insifficient privilege."
            break
        } else {
            outstr = outstr output flags[-3]["1"]
        }
    }

    # Remove hazardous characters from output string:
    gsub("[\x0\x1\x4\x5\x6\x7\x8\x9\xA\xB\xC\xD\xE\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1E]","",outstr);

    # Print our output:
    print "PRIVMSG " channel " :" outstr;
    
    # Close the process.
    close(GAWK_PROC)
}