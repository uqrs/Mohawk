#!/usr/bin/gawk -f
################################################################################
# Mohawk v4.3.2-0 - Holy Shit It's Done
################################################################################
# I honestly didn't think Mohawk would ever get this stable or headache free
# (aside from the MODE handler). Holy fuck.
################################################################################
# Recurring Conventions Throughout The Source Code
################################################################################
# 'i', 'j', and 'k' are always used as "counter variables" of some sorts.
# Usually for use within a (for) loop, or just some sort of disposable
# number to keep track of. They are ALWAYS set before being used, but
# never re-set to 0 or anything similar. You can always rest easy knowing
# you can use these variables for whatever, as they are never used for any
# important overarching code.
#
# To aid the hypothetical programmer in keeping apart arrays and scalars,
# every identifier pointing to any array starts with a '_' (e.g.
# _global). Notable exceptions(!) are any arrays residing in
# _global["_channels"] and _global["_plugins"] (considering these are the
# names of literal plugins and channels, which should not be altered.)
################################################################################
# On The Use Of Comments
################################################################################
# I've tried to comment out the code as much as possible. Expect a lot of
# extraneous detail and such. I use these 80-column wide octotrophe walls to
# separate large sections of text so it's easy to read. If you're at all
# worried about size limits... well, tell me how you managed to travel back
# to the stone age. We have two terabyte big HDDs. Surely you can handle 80
# kilobytes of text, can't you? If not, you're probably smart enough to
# write an awk one-liner to generate a non-commented one.
################################################################################
# A Note To Contributors
################################################################################
# Read the comments before editing. Please. they are there for a reason.
################################################################################
# License (GNU GPL V3.0)
################################################################################
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
################################################################################
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
################################################################################
# A (rather small) function that is often repeated throughout the program is
# a 'shell sanitiser' function, that properly escapes single quotes so that
# they may be used in the shell to circumvent code injection. This boils
# down to escaping single quotes: ' => '\''. Consequently, appropriate shell
# processes should always use single quotes.
function sanitise_squote (input)
{
   return gensub(/'/,"'\\''","G",input)
}
################################################################################
# A function similar to sanitise() which escapes all magic characters in any
# GNU/awk RegEx string. Essentially it turns the first argument of gensub(),
# gsub(), and sub() into its literal form so we can use gensub/gsub
# literally (to operate on strings that include these special characters).
function sanitise_regex (input)
{
   return gensub(/[\.\^\$\\\[\]\|\(\)\*\+\?\{\}\/]/,"\\\\&","G",input);
}
################################################################################
# Another function similar to sanitise() which escapes all forward slashes
# for easy use in sed commands.
function sanitise_sed (input)
{
   return gensub(/\//,"\\/","G",input);
}
################################################################################
# Combines all three earlier functions into one single function:
function sanitise (input)
{
   return sanitise_squote(sanitise_regex(sanitise_sed(input)));
}
################################################################################
# The process for initialising plugins happens in three steps:
# start_proc() is called, often by the function power_on() (which is
# declared down below, and is often called when a channel is joined.)
# start_proc() accepts only one argument: 'plugin' .It then calls
# plugin_header(), which then attempts to generate a process for the specified
# plugins' file. This process is a shell command in the form of:
# `gawk [varlist] [respondto] [addon] -f 'file' -e '{ print"";fflush() }' [end]`
# The -e flag is used to enter raw code onto the command line. This final
# clause: {print"";fflush()} (which always executes) flushes the output buffer,
# handing control back to Mohawk.
#
# 'varlist' is a sequence of variable statements (in the form of '-v var1=val1 -v
# var2=val2') Following 'varlist' is 'respondto'. 'respondto' is another string
# generated by plugin_header(). It looks a tiny bit like:
# `-e '$2 !~ /^(COMMAND)$/ { print "" ; fflush() ; next }'`
# This line of code is generated by plugin_header(). It essentially makes it
# so that if a certain IRC message that is not one of the operations COMMAND
# denotes where an 'operation' can be KICK, PRIVMSG, MODE, etc.) then the
# plugin flushes the output buffer (causing it to hand control back to Mohawk
# immediately) and calls 'next', causing the plugin to evaluate the next
# line it is given from the top.
#
# The other expression, [end] modifies (or creates) the plugins' end block by
# adding a singular `print ""` statement so that control is always handed
# back to Mohawk once the plugin has finished cleaning up. This expression
# would look like:
# `-e 'END { print ""; fflush(); }'`
#
# The final expression is [addon]. [addon] is a list of @include directives
# pointing to all the files specified in this plugins' 'include' plugin
# variable. This allows for extra functionality to be added to plugins at
# will, letting maintainers further customise the ways their plugin behaves.
# [addon] would look a little something like this:
# `-e '@include "modules/addon/addon_1.awk"; @include "modules/addon/addon_2.awk"'`
#
# One @include statement is always added to [addon]. This is:
# `@include "src/done.awk"`
# This file supplies a single function called "done()" which allows a module
# to cleanly hand control back to Mohawk anywhere in the script by executing
# done().
#
# start_proc() assigns the final generated string to _proc[plugin].
#
# run_proc() takes only two arguments: the name of the current plugin which
# needs to be executed, and the input record that shall be handed to the
# plugin. It takes the appropriate process from the _proc table, and then
# executes it, collecting the output from it, terminating once it receives
# an empty string. It then parses the output of the plugin:
# run_proc() recognises two "output modes": socket mode, and interpret mode.
# The mode can be toggled by letting the plugin output a line containing
# only a single "/".
# During the "socket mode", all output from the plugin will be passed to
# send(), and consequently passed to the IRC Handler.
# During the "interpret mode", all output from the plugin will be passed to
# parse_configline(), allowing plugins to alter the global and local
# configuration.
#
# Now, we iterate over the three aforementioned functions in detail:
################################################################################
# plugin_header() opens the files for the given plugin (both the plugin itself,
# and all files listed in @include), and keeps parsing lines looking for the
# following patterns:
# /^\s*#\s*VAR/
# /^\s*#\s*LOCALVAR/
# /^\s*#\s*RESPOND/
# /^\s*#\s*LOCALISE/
# /^\s*#+\s*$/
# The former four patterns correspond to certain so-called 'directives'.
# These directives are read and parsed by plugin_header, and they influence
# both the [varlist] and [respondto] parts of the process generated by
# start_proc().
#
# The former two directives, VAR and LOCALVAR influence the [varlist] part
# of the process string.
# The VAR directive may be followed by a space-delimited list of names that
# correspond to the identifiers of global configuration variables.
#
# The LOCALVAR directive may be followed by a space-delimited list of names
# that correspond to the identifiers of this plugin's plugin blocks'
# configuration variables.
#
# Both VAR and LOCALVAR will prompt plugin_header() to add a '-v' flag
# (command-line variable declaration) to [varlist] that looks like:
# `-v identifier='value'`. e.g. say 'VAR' contains "server" (and the server
# field is set to 'irc.synirc.net' in the configuration,) then plugin_header()
# will add `-v server='irc.synirc.net` to the end of [varlist]. If a
# variable with an identical identifier appears both in LOCALVAR and VAR
# (both the plugin block and the global configuration have a similarily
# named variable), the one that was specified second takes precedence.
#
# The RESPOND directive may be followed by a space-delimited list of
# IRC commands. plugin_header will generate a small block of code. Namely,
# it generates [respondto]. If the RESPOND directive looks a bit like:
# `# RESPOND PRIVMSG NOTICE MODE`
# Then [respondto] shall look like:
# `-e '$2 !~ /^(PRIVMSG|NOTICE|MODE)$/ { print ""; fflush() ; next }'`
#
# The LOCALISE directive disambiguates NICK and QUIT messages
# by modifying them: the name of the relevant channel is inserted after the
# command name. e.g.:
# :John!Drugs@are.bad NICK :Paul => :John!Drugs@are.bad NICK #main :Paul
# :Ellie!Puppies@are.cute QUIT => :Ellie!Puppies@are.cute QUIT #main :Leaving...
################################################################################
function plugin_header(plugin)
{
   # Reset these variables:
   line="";respondto="";arglist="";directive="";include_list="";
   delete _contents; delete _includes; delete _files;

   # Force _files into an array:
   split("",_files);

   # First, if this plugins' configuration has a 'include' field, add @include
   # statements for each field. Don't use spaces, please.
   if ( "include" in _global["_plugins"][plugin] ) {
      split(_global["_plugins"][plugin]["include"],_includes);
      for ( include in _includes ) {
         # Sanitise single quotes and escape double quotes. Deal with it.
         gsub(/[" ]/,"",_includes[include]);
         # Add an @include statement:
         include_list=include_list "@include \"" sanitise_squote(_includes[include]) "\"; "
         # Add the include file to _files:
         _files[length(_files)+1]=_includes[include]
      }
   }

   # Add the plugin's file to the end of _files:
   _files[length(_files)+1]=_global["_plugins"][plugin]["file"]

   # Now, we parse every single file in _files for directives:
   for ( f in _files ) {
      # Store a shortcut:
      file=_files[f];

      # Keep retrieving lines from the file until (for the second time) no
      # valid directive or octotrophe-wall has been found.
      while ((getline line < file) > 0) {
         # If the line is just a wall of comments, or is an empty comment, then
         # skip to the next line.
         if ( line ~ /^\s*#*\s*$/ ) { continue };

         # If the given line is not a valid directive, then skip ahead.
         if ( line !~ /^\s*#+\s*((LOCAL)?VAR|RESPOND|LOCALISE)/ ) { continue }

         # Turn all tabs in the line into single spaces:
         gsub(/\t/," ",line);

         # Remove the # and all whitespace preceding the name of the directive.
         gsub(/^\s*#+\s*/,"",line);

         # If no more spaces appear, just skip ahead to looking at the next line.
         if (index(line," ")==0) {continue;}

         # Retrieve the name of the directive, then remove it from the line
         # also (just like with gsub):
         directive=substr(line,1,index(line," ")-1);
         gsub(/^[^ ]+\s+/,"",line);

         # Split the contents of the directive into '_contents':
         split(line,_contents);

         # Take the appropriate action depending on the given directive:
         switch (directive) {
            case "VAR":
               # Add an entry to arglist for the given variable.
               for (i in _contents) {
                  arglist=arglist "-v '" sanitise_squote(_contents[i]) "'='" sanitise_squote(_global[_contents[i]]) "' "
               } break;
            case "LOCALVAR":
               # Add an entry to arglist for the given variable.
               for (i in _contents) {
                  arglist=arglist "-v '" sanitise_squote(_contents[i]) "'='" sanitise_squote(_global["_plugins"][plugin][_contents[i]]) "' "
               }
               break;
            case "RESPOND":
               # If the line contains any weird characters, complain:
               if ( line ~ /[^A-Za-z_0-9 ]/ ) {
                  print "[#] Strange characters in given RESPOND directive for plugin '" plugin "'" >> "/dev/stderr"
                  print "[$] RESPOND: '" line "'" >> "/dev/stderr"
                  break;
               }
               # Ignore _contents. Rather, change all spaces in the line to |s
               # and directly use them as a pattern:
               respondto="-e '$2 !~ /^(" gensub(/\s+/,"|","G",line) ")$/ { print \"\"; fflush() ; next}' "
               break;
            case "LOCALISE":
               # Set the plugin's "LOCALISE" variable to "YES":
               _global["_plugins"][plugin]["LOCALISE"]="YES";   
               break;
         }
      }
      # Neatly close the file now that it is no longer in use.
      close(file);
   }

   # Return an appropriate process string:
   return (arglist " " \
   respondto " " \
   "-e '@include \"" _global["DONE"] "\"; " include_list "' " \
   "-f '" sanitise_squote(file) "' " \
   "-e '{ print\"\";fflush() }' " \
   "-e 'END { print \"\";fflush() }'");
}
################################################################################
# start_proc() is responsible for initiating the process for a plugin. It
# accepts one argument: 'plugin', which must correspond to a table in
# '_global["_plugins"]'. It attempts to generate a string that will then be
# stored in _proc[plugin] so that run_proc() may execute it.
#
# start_proc() also allocates and/or updates an entry in the array _byfile[],
# using the full path to a file used by a process as the key, and a
# space-delimited list of plugins that execute using this file as the value.
# This makes it so that in the future, when a plugin file is updated or
# altered, the processes for each and every plugin may be closed and
# reopened without having to iterate over each plugin.
################################################################################
function start_proc(plugin)
{
   # Beforehand, check to make sure that this plugin exists:
   if ( !(plugin in _global["_plugins"]) ) {
      print "[#] Attempt to start process for nonexistent plugin: '" plugin "'" >> "/dev/stderr";
      return;
   # Also make sure a 'file' field was specified:
   } else if ( !("file" in _global["_plugins"][plugin]) ) {
      print "[#] Plugin '" plugin "' has no file specified." >> "/dev/stderr";
      return;
   # If the process already exists, just skip:
   } if ( (plugin in _proc) ) {
      print "[@] Plugin '" plugin "' already has a process. Skipping.";
      return;
   # Else, store a shortcut:
   } else { file=_global["_plugins"][plugin]["file"] }

   # Make sure the file exists:
   if ( (getline _ < file)<1 ) {
      # If it doesn't, complain:
      print "[#] Plugin '" plugin "' specifies a nonexistent file: '" file "'" >> "/dev/stderr";
      return;
   } close(file);

   # Assign a process:
   _proc[plugin]=(_global["GAWK_PATH"] " " plugin_header(plugin) )

   # Retrieve the actual path to the plugin file using 'realpath':
   REAL=("realpath '" sanitise_squote(file) "' 2>/dev/null");
   REAL | getline realpath; close(REAL);
   # If an entry already exists in _byfile, then just append this plugin:
   if ( realpath in _byfile ) {
      _byfile[realpath]=_byfile[realpath] plugin " "
      print "[@] Created process for '" plugin "', and updated _byfile register accordingly.";
   # Else, allocate a new entry:
   } else {
      _byfile[realpath]=plugin " "
      print "[@] Created process for '" plugin "', and allocated a new entry in _byfile.";
   }
}
################################################################################
# run_proc() takes two arguments: 'plugin' and 'input'. It essentially keeps
# executing the appropriate process until it receives an empty string. It
# takes the appropriate action depending on the output of the process as
# stated above.
################################################################################
function run_proc(plugin,input)
{
   # If the given plugin does not have a process, complain:
   if ( !(plugin in _proc) ) {
      print "[#] No process for plugin '" plugin "'" >> "/dev/stderr";
      return;
   }

   #############################################################################
   # Feed the input to the given plugin:
   print input |& _proc[plugin];

   # Retrieve output:
   _proc[plugin] |& getline out;

   # Keep parsing as long as no empty string has been outputted.
   while ( out != "" ) {
      # If the output is a single '/', switch modes:
      if ( out=="/" ) {
         if (mode==0) {mode=1} else {mode=0}; 
         _proc[plugin] |& getline out; continue;
      }

      # Take a specific action depending on the given mode:
      switch (mode) {
         case 0: send(out); break;
         case 1: parse_configline(out); break;
      }

      # Retrieve the next line of output:
      _proc[plugin] |& getline out;
   }

   # Reset variables:
   mode=0;out="";
   # Reset these variables in case of sloppy plugins:
   current_declaration="";declaration_name="";
}
################################################################################
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
################################################################################
# Mohawkrc - The Config File
################################################################################
# First, a handy function for parsing escape sequences: is_escaped. This
# function essentially takes a string (string) and an indice (indice).
# It returns a '1' if the character is escaped.
# It returns a '0' if the character is not escaped.
# It performs two checks to decide whether to return a 0 or a 1:
# If the character preceding the one 'indice' refers to is a '\', AND this
# '\' is not escaped, then return a 1. Else, return a 0.
# is_escaped does make a call to itself to reach a conclusion.
################################################################################
function is_escaped (string,indice) {
   if ((substr(string,indice-1,1) == "\\") && !(is_escaped(string,indice-1)))
   { return 1 } else { return 0 }
}
################################################################################
# Checking Configuration Presence.
################################################################################
# Throw an error if no config files have been specified (ARGC<2)
#
# Luckily, -v does not cause ARGC to increment.
#
# This is to prevent Gawk trying to read from stdin, essentially halting the
# program prematurely. This is also why you can not supply config files using
# the < operator (as this does not increment ARGC).
#
# We also set IGNORECASE since case sensitivity hinders us more than it helps us.
BEGIN {
   # Don't fuss about case...
   IGNORECASE = 1

   # If no config files have been specified, complain:
   if ( ARGC < 2 ) {
      print "[!] No configuration files have been specified. Exiting..." > "/dev/stderr"
      fatal=1; exit;
   }
}

################################################################################
# Diagnosing The System
################################################################################
# We declare a function, which(). which() takes two arguments, "binary", and
# "prefix". which() attempts to deduce the path to "binary" on the system.
# It then adds this path to _global[toupper(binary)"_PATH"] for future use.
#
# If the specified binary was not found, an error will be printed, and 'fatal'
# will be set to '2'.
function which (binary,prefix)
{
   if ( !("which " prefix binary " 2>/dev/null" | getline _global[toupper(binary) "_PATH"]) ) {
      print "[!] Could not find " prefix binary " on this system!" > "/dev/stderr"; fatal=2
   }; close("which " prefix binary " 2>/dev/null");
   if ( _global[toupper(binary) "_PATH"] != "" ) {
      print "[@] Found " binary ": " _global[toupper(binary) "_PATH"]
   }
}

################################################################################
# diagnose() makes numerous calls to the earlier declared which() function in
# order to deduce the paths to several binaries on the system. If
# USE_GCOREUTILS is set, "g" will be supplied as "prefix" to which(). This
# is only really useful for FreeBSD installations, where GNU coreutils
# binaries will start with a "g" (e.g. "gcat", "gstdbuf", "ggrep", etc.)
#
# Mohawk will run fine with POSIX sed, HOWEVER, some plugins might try to
# use sed in a so-called "sandbox mode" (by supplying the --sandbox) flag.
# "sandbox mode" is a function exclusive to GNU/sed 4.3 or higher. Refer to
# the _global["SED_SANDBOX"] variable to check whether the currently used
# sed binary supports sandboxing (this variable contains either 'no', or
# 'yes').
function diagnose ()
{
   # Get system hostname.
   ("uname -sr" | getline HOST_SYS) ; close("uname -sr")

   # Print some useful data.
   print "[@] Running on " HOST_SYS

   # If USE_GCOREUTILS is set, then use 'gsed', 'gcat' and 'gecho'
   if ( "USE_GCOREUTILS" in _global ) {
      print "[@] USE_GCOREUTILS is set. Using GNU Coreutils."
      lookfor = "g"
   }

   # If these variables aren't set, attempt to guess.
   # Each of the lines down here do practically the same: it calls which in
   # order to look for the specified binary and assign it to
   # _global["PROGRAM_PATH"]. If it doesn't find anything, it throws an
   # error.
   if ( !("STDBUF_PATH" in _global) )	{ which("stdbuf",lookfor) }
   if ( !("SED_PATH" in _global) )	{ which("sed",lookfor) }
   if ( !("GAWK_PATH" in _global) )	{ which("gawk") }
   if ( !("CAT_PATH" in _global) )	{ which("cat",lookfor) }
   if ( !("GREP_PATH" in _global) )	{ which("grep",lookfor) }
   if ( !("TR_PATH" in _global) )	{ which("tr",lookfor) }
   if ( !("CUT_PATH" in _global) )	{ which("cut",lookfor) }

   # Echo works a bit differently.
   if ( (!("ECHO_PATH" in _global)) && ("USE_GCOREUTILS" in _global) ) { if ( !("which " lookfor "echo 2>/dev/null" | getline _global["ECHO_PATH"] ) ) {
      print "[!] Could not find " lookfor "echo on this system!" > "/dev/stderr"; fatal=2 } }
   else { _global["ECHO_PATH"]="/bin/echo" ; echo_found = 1 }

   # Close all the echo process:
   close("which " lookfor "echo 2>/dev/null")

   # If an error has ocurred, exit:
   if ( fatal ) { return }

   # If no error happened for echo, print a success message.
   print "[@] Found echo: " _global["ECHO_PATH"]

   # See if the sed version currently being used supports sandboxes:
   _global["ECHO_PATH"] " 'yes' |" _global["SED_PATH"] " --sandbox -n 'p' 2>/dev/null || echo 'no'" | getline _global["SED_SANDBOX"]
   close(_global["ECHO_PATH"] " 'yes' |" _global["SED_PATH"] " --sandbox -n 'p' 2>/dev/null || echo 'no'")

   if ( _global["SED_SANDBOX"] == "yes" ) {
      print "[@] This version of sed supports sandboxes."
   } else { 
      print "[#] This version of sed does not support sandboxes!"
      print "[#] Some plugins that rely on this functionality might not work!"
   }

   # Set the default "DONE" variable if none was specified in the configuration:
   !("DONE" in _global) && _global["DONE"]="src/done.awk";

}

################################################################################
# Parsing The Configuration
################################################################################
function parse_configline(line) {
################################################################################
# The following few blocks are going to be "part of a function"
# parse_configline. It operates only on $0.
################################################################################
# If the 'line' argument is specified, $0 will be temporarily replaced with it.
# It will be restored at the end of the function.
   if ( line != "" ) { old_0=$0;$0=line;$0; }
################################################################################
# Reset essential variables to this function.
################################################################################
   head=""; value=""; end=""; n_end=""; first=""; variable="";
################################################################################
# Several variables are used to keep track of the configuration parsing
# (they are reset at the start of the END block);
# These variables are:
# current_declaration - either "_channels", "_plugins", or ""; the former two
# refer to one of the arrays existent _global[]; It is used to keep track in
# which kind of declaration we are (declaring global variables, plugin
# variables, or channel variables).
# declaration_name - the name of the channel or plugin we are declaring
# variables for.
#
# Thus, the config statement:
# `channel "#main"`
# Sets current_declaration to "channels", and declaration_name to "#main"
################################################################################
# Before that- skip this line if it is completely empty OR starts with a #:
   if (($0 ~ /^\s*$/) || ($0 ~ /^\s*#/)) { return 0; }

################################################################################
# We begin the parsing of every configuration statement the same way: by
# splitting the current line into two separate parts: the 'head' and 'body'.
# The 'head' is a sequence of alphanumerical characters (including
# underscores) delimited only by whitespace.
# The 'body' is everything following the head up until the final non-escaped
# newline.
################################################################################
# PARSING THE HEAD
################################################################################
   # First, remove all the whitespace preceding the head; this allows for
   # users writing the config to use indentation in any way they want.
   gsub(/^\s*/,"");

   # We take the head, which is the first field in the input record. We wipe
   # it from the input record afterwards:
   head=$1; $1="";

   # If the head contains any illegal characters (anything not a-z, A-Z, 0-9,
   # an underscore, or a hyphen) then complain about a syntax error:
   if ( head ~ /[^A-Za-z0-9_\-]/ ) {
      print "[!] Illegal character in identifier near line " FNR "." > "/dev/stderr";
      print "[$] Identifier: `" head "`" > "/dev/stderr"; return 4;
   }

   # We finish by removing all leading spaces in the input record:
   gsub(/^\s*/,"");
################################################################################
# Parsing The Body
################################################################################
# We parse the remainder of the input record, the body.
# The body consists out of a sequence of:
# interpolating strings - sequences of alphanumerical characters delimited
# by non-escaped double quotes ("). All escape sequences occurring within
# these strings are automatically interpolated.
#
# literal strings - sequences of alphanumerical characters delimited by
# non-escaped single quotes ('). All escape sequences occurring within these
# strings are copied as-is, and not interpolated.
#
# global identifiers - sequences of alphanumerical characters not delimited
# quotes, that refer to the values of other (formerly specified) configuration
# variables.
################################################################################
# We focus on turning the body into a full-fledged string variable by
# interpolating it. At any time, $0 holds the current part of the body that
# is being parsed. "value" is, at all times, the final result.
#
# Parsing goes as follows: the very first character is compared:
# If it's a ", we start parsing an interpolating string, continuing onwards
# until a non-escaped " is encountered.
# If it's a ', we start parsing a literal string, continuing onwards until a
# ' is encountered.
# If it's the name of an identifier (alphanumericals, underscores) then
# attempt to parse the full name of it and dereference it, continuing
# onwards until whitespace is encountered.
# If anything else appears, throw an error.
#
# Once the very first character has been identified, the "look_for" variable
# shall be set appropriately. "look_for" 
#
# We traverse through the entire body as follows (where 'eat' refers to
# "destroying this part of the input record):
# 1. Eat any leading whitespace, discarding it.
# 2. Detect what the current first character is (", ', or else), and take
# appropriate action (dereference identifiers, parse the string, etc.)
# 3. Eat the appropriate parts, moving them over to 'value'.
# 4. Repeat from step 1 until the string contains nothing but whitespace.
#
# First, append a single whitecharacter space to prevent dodginess with index()
# not recognising the end of a string:
   $0=($0 " ");

   # Skip this entire process if there is no body (everything after the head is whitespace)
   if ($0 !~ /^\s*$/) {
      do {
         # First, append a single whitecharacter space to prevent dodginess with index()
         # not recognising the end of a string:
         $0=($0 " ")

         # Eat leading whitespace:
         gsub(/^\s*/,"");

         # Keep the first character safe:
         first=substr($0,1,1);

         # Remove it from $0:
         $0=substr($0,2); $0;

         # Handle parsing a regular, interpolating string:
         if (first == "\"") {
            # Retrieve the first findable quotation mark:
            end=index($0,"\"");
            # If end == 0 (meaning no quotation mark was found), throw an error:
            if ( end == 0 ) {
               print "[!] Unfinished double-quoted string near line " FNR "." > "/dev/stderr";
               return 5;
            }
            
            # If it is escaped:
            if ( is_escaped($0,end) ) {
               # Keep repeating until we get an unescaped quotation mark.
               do {
                  # Look for the first next possible instance of look_for:
                  n_end=(end+index(substr($0,end+1),"\""));
                  # If no next instance has been found, throw an error:
                  if ( n_end == end ) {
                     print "[!] Unfinished double-quoted string near line " FNR "." > "/dev/stderr";
                     return 6;
                  } else { end = n_end }
               } while (is_escaped($0,end) && (end < length($0)))
            }
            # Append the now-parsed string to the final value:
            value = value substr($0,1,end-1)
         # Handle parsing a single quoted (literal) string:
         } else if (first=="'") {
            # Retrieve the first findable quotation mark:
            end=index($0,"'");
            # If end == 0 (meaning no quotation mark was found), throw an error:
            if ( end == 0 ) {
               print "[!] Unfinished single-quoted string near line " FNR "." > "/dev/stderr";
               return 7;
            }
            # No need to handle "escaped strings" with single quotes.
            # Append the string to the value:
            value = value substr($0,1,end-1);
         # Else, it must be a value that needs be dereferenced:
         } else if ( first ~ /[A-Za-z0-9_\-]/ ) {
            # Retrieve the first findable character not in this set, and use
            # this as the end:
            end=index($0, gensub(/^[A-Za-z0-9_\-]+(.)/,"\\1","g",$0));
            # Construct a variable name:
            variable=(first substr($0,1,end-1));

            # We now have a variable name. Check if it has anything allocated
            # to it. If not, give a warning.
            if ( !(variable in _global) ) {
               print "[#] No such variable: '" variable "'."
            }
            # Dereference and apply the variable to 'value':
            value = value _global[variable]
         # Else, if it's a '\' preceding the end of the string:
         } else if ( first == "\\" ) {
            # If this isn't the last non-whitespace character on the string, complain:
            if ( $0 !~ /^\s*$/ ) {
               print "[!] Invalid character near line " FNR "." > "/dev/stderr";
               return 8;
            # Else, skip to the next line.
            } else { getline }
         # Else, if it's a # (meaning a comment follows), stop parsing:
         } else if ( first == "#" ) {
            break;
         # Else, it's an illegal character! Throw an error:
         } else {
            print "[!] Invalid character near line " FNR "." > "/dev/stderr";
            return 9
         }

         # Now, cut away the part we managed to dereference:
         $0=substr($0,end+1);

         # Reset these variables:
         end=0;n_end=0;variable="";

         # Repeat the above block as long as there's still stuff to
         # dereference/parse:
      } while ( $0 !~ /^\s*$/ )
   }
################################################################################
# Parsing The Full Statement
################################################################################
# Now that we have both a head (identifier) and body (value), we figure out
# what to do with them. Either one of four things may occur:
# If the head is...
# 'plugin', then the body (which should be a string) refers to the name of a
# plugin. A declaration for the specified plugin begins.
# 'channel', then the body (which should be a string) refers to the name of
# an IRC channel. A declaration for the specified channel begins.
# 'end', then the current channel OR plugin declaration finishes. All
# following variables are allocated to the global namespace.
# Something else: as long as 'body' is not empty,
################################################################################
   # Take appropriate action:
   switch (head) {
      case "channel":
         # If we're already in a declaration, complain:
         if ( current_declaration != "" ) { print "[!] Cannot nest declarations near " FNR > "/dev/stderr"; return 10; }
         # If the value contains a space, complain:
         if ( value ~ /\s/ ) { print "[!] Channel name may not contain whitespace near " FNR > "/dev/stderr"; return 12 }
         # Set the appropriate variables:
         current_declaration="_channels"; declaration_name=value; 
         # Force the appropriate array and then delete it. This makes it so
         # that if the same channel/plugin is specified in the
         # configuration, the latter overwrites the former entirely.
         _global[current_declaration][declaration_name][0];
         delete _global[current_declaration][declaration_name];

         break;
      case "plugin":
         # If we're already in a declaration, complain:
         if ( current_declaration != "" ) { print "[!] Cannot nest declarations near " FNR > "/dev/stderr"; return 10; }
         # If the value contains a space, complain:
         if ( value ~ /\s/ ) { print "[!] Plugin name may not contain whitespace near " FNR > "/dev/stderr"; return 12 }
         # Set the appropriate variables:
         current_declaration="_plugins"; declaration_name=value; break;
         # Force the appropriate array and then delete it. This makes it so
         # that if the same channel/plugin is specified in the
         # configuration, the latter overwrites the former entirely.
         _global[current_declaration][declaration_name][0];
         delete _global[current_declaration][declaration_name];

         break;
      case "end":
         # If we're not yet in a declaration, complain:
         if ( current_declaration == "" ) { print "[!] Invalid keyword: 'end': not in a declaration near " FNR > "/dev/stderr"; return 11; }
         current_declaration=""; break;
      case /[A-Za-z_\-0-9]/:
         # This must be a declaration:
         # If we're in a declaration, then allocate the variable to the appropriate declaration:
         if ( current_declaration != "" ) {
            _global[current_declaration][declaration_name][head]=value;
         } else {
            _global[head]=value;
         } break;
      default:
         # Else... throw an error:
         print "[!] Syntax error near " FNR > "/dev/stderr";
         return 12
   }

   # Reassign old_0 to $0 if needed:
   if ( old_0 != "" ) { $0=old_0;old_0="";$0; }

   # No errors have happened:
   return 0;
}
# Function parse_configline ends here.
################################################################################
# This is the only piece of code that is run outside of the BEGIN and/or END
# blocks: it simply subjects every input record to parse_configline. It also
# 'exit's and sets 'fatal' if the return value is nonzero.
################################################################################
{
   code=parse_configline()
   if ( code > 0 ) {fatal=code;exit;}
}
################################################################################
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
################################################################################
# The Internet Relay Chat Protocol
################################################################################
# Functional Pre-work
################################################################################
# 'send' function: does nothing but append a carriage return/line feed to the
# message, and then send it to the socket. This is to largely clean up later
# code. Please use send() over manually sending to IRC_SOCK
function send ( body )
{
   # Append trailing CR-LF:
   print body "\r\n" |& IRC_SOCK
   # Also print our message to stdout. Y'know, for convenience.
   print "[>] " body
}

################################################################################
# Handling Channels
################################################################################
# A channel is a collection of variables that dictates how Mohawk should
# behave in the specified channel. A channel may be in either one of two
# states: on, and off. Channels can be turned on or off by utilising the
# following two functions: power_on(), and power_off(). Both of these
# functions accept a sole argument: 'channel'. This must be a string
# corresponding to one of the fields in _global["_channels"]. If it does not
# appear in this array, then the contents of _global["_channels"]["*"] will
# be used. If the given message is a private message sent to Mohawk, then
# the channel name ($3) will be altered to the nick of the user who sent the
# message. The contents of _global["_channels"]["@"] will be used to
# determine what to do.
#
# The former prepares a channel for usage- it starts processes for all the
# appropriate plugins and logging facilities, parses the configuration for
# the given channel (located in _global["_channels"]) and such.
#
# power_on() is more often than not called by the JOIN handler.
#
# The latter, closes a channel down- it quits all processes, flushes the
# logfiles, and then wipes the channels' memory.
#
# power_off() is more often than not called by the PART, KICK, and QUIT
# handlers.
#
# power_on() does the following:
# 1.) It parses the space-separated list of plugins in
# _global["_channels"][channel]["plugins"], and places them in:
# _proclist[channel]
# 2.) It goes over the contents of _plugins, taking the value of each
# entry (the plugin name), and then assigning it as a key in
# _proc[], while also creating a process for it to run. It then updates the
# appropriate plugins' _byproc[] entry by appending the current channels'
# name to it. This is so that in the future, power_off() can keep track of
# when to close a plugins' process.
# 3.) If required, it creates an appropriate logging process that stores all
# lines given to the appropriate output file. This process will be stored
# in: _log[channel]
################################################################################
function power_on (channel)
{
   # Uncapitalise the channel name before using it. This is done everywhere
   # in the program to avoid any sort of capitalisation-based ambiguity.
   channel=tolower(channel)

   # A rather important distinction is made here:
   # 'channel' is the name of the channel Mohawk has joined, and the string
   # that will be used as a key in the _proc and _log tables.
   # 'use_contents' is the name of the array in _global["_channels"] Mohawk
   # will read the configuration from.
   # use_contents will be set to '*' if 'channel' does not appear in
   # _global["_channels"] (effectively making '*' a "default channel" or
   # something similar.) The default channel- '*' does not allow for
   # logging.
   if ( !(channel in _global["_channels"]) ) { use_contents="*" }
   else { use_contents=channel }

   # Force the relevant _proclist entry into an array:
   _proclist[channel][1];

   # Split the contents of the plugin list into an array.
   split(_global["_channels"][use_contents]["plugins"],_proclist[channel])

   # Iterate over all the plugins specified in the list:
   for ( plugin in _proclist[channel] ) {
      # Create a shortcut variable.
      plugin_name=_proclist[channel][plugin]

      # If the specified plugin does not appear in the global plugins list,
      # complain:
      if ( !(plugin_name in _global["_plugins"]) ) {
         print "[#] Plugin '" plugin_name "' is specified in the configuration for '" use_contents "', but no such plugin exists." >> "/dev/stderr"
         continue;
      }

      # Else, create a process for this plugin:
      start_proc(plugin_name);

      # Update _byproc[]. If an entry already exists, then update it. If
      # not, create a new one:
      if ( plugin_name in _byproc ) {
         _byproc[plugin_name]=_byproc[plugin_name] channel " "
      } else {
         _byproc[plugin_name]=channel " "
      }
   }

   # Reset appropriate variables:
   use_contents="";
}
################################################################################
# power_off() does the following:
# 1.) It goes over each of the specified channels' plugins, and removes the
# channel name from the appropriate _byproc[] entries. If the resulting
# _byproc[] entry is empty, then the plugins' process in _proc[] will be
# closed.
# 2.) It closes the log output file by subjecting it to close(). Then, it
# deletes the entry in _log[channel]
################################################################################
function power_off (channel)
{
   # Uncapitalise the channels' name to avoid confusion:
   channel=tolower(channel);

   # If there's no process list... just quit now:
   if ( !isarray(_proclist[channel]) ) { return }

   # Iterate over each specified plugin:
   for ( plugin in _proclist[channel] ) {
      # Delete this channels' name from the appropriate _byproc[] entry:
      gsub(sanitise_regex(channel " "),"",_byproc[_proclist[channel][plugin]]);
      # If the _byproc[] entry is empty, close this plugins' process and delete it:
      if (_byproc[_proclist[channel][plugin]] ~ /^\s*@?\s*$/) {
         close(_proc[_proclist[channel][plugin]]);
         delete _proc[_proclist[channel][plugin]];
      }
   }

   # Delete this channels' _proclist entry:
   delete _proclist[channel];
}

################################################################################
# The Inhabitants File
################################################################################
# The inhabitants file is a physical disk file that is used to keep track of
# the inhabitants of a given IRC channel. Each line denotes a channel,
# followed by a space-separated list of users. The inhabitants() function is
# used to manipulate and read from this file in an easy and concise manner
# (so that the handlers below needn't repeat themselves.)
#
# It accepts two arguments: 'operation', and 'argument'. The former dictates
# which operation should be performed on the inhabitants file. The latter
# supplements the first.
# ===[OPERATION]=========[ARGUMENT]==================[DESCRIPTION]=============
# | read          | Channel name        | Retrieve the inhabitants list.      |
# | join          | "#channel user"     | Add a user(s) to the list.          |
# | part          | "#channel user"     | Remove a user from the list.        |
# | part_all      | "#channel"          | Remove all users from the list.     |
# | quit          | "user"              | Removes user from all channels.     |
# | nick          | "old_nick new_nick" | Update all instances of old_nick.   |
# | mode          | "#channel nick new" | Update the nick's mode (qoahv).     |
# | cmode         | "#channel new       | Update the channels' mode.          |
# | create        | Channel name        | Add a new channel to the file.      |
# | destroy       | Channel name        | Remove a channel from the file.     |
# =============================================================================
################################################################################
function inhabitants( operation, argument )
{
   # Reset variables:
   result="";delete _words;code=0;

   # Seperate each individual word:
   split(argument,_words);

   # Granted "channel" is always _words[1] when it is required, we call
   # 'grep' to give us two things: the line containing this channels' entry
   # from the inhabitants file, and the response code from the grep call. If
   # the response code is '0', then this means that no channel entry was
   # found. Else, it has been found.
   PROC=(_global["GREP_PATH"] " -iE '^" sanitise_squote(_words[1]) " ' 'cache/inhabitants'")
   code=(PROC | getline result); close(PROC)

   # Use a switch statement to go over each possible operation:
   switch(operation) {
      # "read" returns the userlist for a given channel.
      case "read":
         # If no entry exists, complain and return the channels' name
         # without a userlist; as if it were empty.
         if ( code==0 ) {
            print "[#] No entry for '" _words[1] "' in the inhabitants file." >> "/dev/stderr";
            return _words[1];
         # If the entry does exist, then just return the line 'grep'
         # retrieved earlier.
         } else { return result }
      # "join" adds the given username to the specified channel.
      case "join":
         # If no entry exists, complain and move on like nothing happened.
         if ( code==0 ) {
            print "[#] No entry for '" _words[1] "' in the inhabitants file." >> "/dev/stderr";
         } else {
            # Else, construct a sed statement that appends the given
            # username to the userlist. We use anything past the first space
            # rather than _words[2] as a name list. This would permit
            # certain handlers to add entries in bulk, saving I/O
            # tomfuckery.
            channel_safe=sanitise(_words[1]); name_safe=sanitise(substr(argument,index(argument," ")+1));
            PROC=_global["SED_PATH"] " -i'' -Ee '/^" channel_safe " /I s/ $/ " gensub(/&/,"\\\\&","G",name_safe) " /' 'cache/inhabitants'";
         } break;
      # "part" does the inverse of "join", removing a username from the
      # specified channel.
      case "part":
         # If no entry exists, complain and move on like nothing happened.
         if ( code==0 ) {
            print "[#] No entry for '" _words[1] "' in the inhabitants file." >> "/dev/stderr";
         } else {
            # Else, construct a sed statement that removes the username AND
            # their privilege mode (qoahv) from the list.
            channel_safe=sanitise(_words[1]); name_safe=sanitise(_words[2]);
            PROC=_global["SED_PATH"] " -i'' -Ee '/^" channel_safe " /I s/ [" privilege_symbols "]*" name_safe " / /' 'cache/inhabitants'";
         } break;
      # "part_all", usually only utilised by the 353 handler, removes all
      # users from a channel list (preserving the channel mode.)
      case "part_all":
         # If no entry exists, complain and move on like nothing happened:
         if ( code==0 ) {
            print "[#] No entry for '" _words[1] "' in the inhabitants file." >> "/dev/stderr";
         } else {
            # Else, construct a sed statement that removes everything PAST
            # the channel mode:
            channel_safe=sanitise(_words[1]);
            PROC=_global["SED_PATH"] " -i'' -Ee '/^" channel_safe " /I s/^([^ ]+) ([^ ]+) .+/\\1 \\2 /' 'cache/inhabitants'";
         } break;
      # "quit" removes every single instance of a nick from the entire inhabitants file.
      case "quit":
         # Else, construct a sed statement that removes the username AND
         # their privilege mode (qoahv) from the list.
         name_safe=sanitise(_words[1]);
         PROC=_global["SED_PATH"] " -i'' -Ee 's/ [" privilege_symbols "]*" name_safe " / /' 'cache/inhabitants'";
         break;
      # "nick" changes every instance of a given username to something else,
      # while preserving the privilege mode (qoahv). This of course does not
      # apply for any specific channel, since nick changes are server-wide
      # events.
      case "nick":
         # Sanitise the name, and then replace it in every entry.
         name_safe=sanitise(_words[1]);
         PROC=_global["SED_PATH"] " -i'' -Ee 's/ ([" privilege_symbols "]*)" name_safe " / \\1" _words[2] " /I' 'cache/inhabitants'"
         break;
      # "mode", which is often called by the literal MODE handler down
      # below, edits the privilege levels for the given user (_words[2]) for
      # the given channel (_words[1]).
      #
      # _words[3] must be a sequence of characters of exactly two
      # characters in length. _words[3] is parsed character by character,
      # left to right. What "mode" will do with each character depends on
      # the current 'mode operation'.
      #
      # If the mode operation is 'add', then all alphabetically represented
      # privilege modes (e.g. 'o' and 'v') will be translated to symbolic
      # privilege modes (e.g. '@' and '+') and will subsequently be ADDED to
      # the list.
      #
      # If the mode operation is 'del', then all symbolic counterparts (e.g.
      # '@' and '+') of the given alphabetical privilege modes (e.g. 'o' and
      # 'v') will subsequently be REMOVED from the list.
      #
      # If the first character is "+", then the 'add' mode operation shall
      # be used. Else, the 'del' mode operation shall be used.
      #
      # The symbolic counterpart of the alphabetically represented privilege
      # modes are deduced by using the _global["PREFIX"] variable (which
      # should have either been sent BY the server in a 005 reply, OR which
      # should have been set in the configuration). The PREFIX variable
      # takes the form of a parentheses-enclosed list of alphabetically
      # represented privilege mode in descending order of power, followed by
      # a list of symbolically represented privilige modes in descending
      # order of power. From left to right, both of these lists have a
      # one-to-one correspondence. One common value for PREFIX is:
      # (qaohv)~&@%+   
      #                   L=5
      #                    |
      #        -------------------------
      #        |                       |
      #  1     2     3     4     5     6     7     8     9    1 0   1 1   1 2
      # [(]   [q]   [a]   [o]   [h]   [v]   [)]   [~]   [&]   [@]   [%]   [+]
      #        |                                   |
      #        -------------------------------------
      #                          |
      #                         D=6
      # As you might notice, the difference between a given alphabetic
      # representation and the corresponding symbolic representation (D) is
      # equal to the amount of privilege modes present (L), plus one (to
      # compensate for the parentheses present). Note that 'L' is also
      # always equal to the full length of PREFIX divided by two.
      case "mode":
         # If no entry for the given channel exists, complain and exit:
         if ( code==0 ) {
            print "[#] No entry for '" _words[1] "' in the inhabitants file." >> "/dev/stderr";
            return "";
         # Else, we get to work.
         } else {
            # Deduce the character and mode:
            character=substr(_words[3],2);
            sign=substr(_words[3],1,1);
            # If this curious mode operation does not appear in PREFIX, then
            # stop right now.
            if ( index(_global["PREFIX"],character) == 0) { break; }
            # Else, if it was found, deduce its symbolic counterpart:
            symbolic=substr(_global["PREFIX"],(length(_global["PREFIX"]) / 2 + index(_global["PREFIX"],character)),1) #/ This is just my editor being weird. Apologies.

            # Create some nicely sanitised variables:
            channel_safe=sanitise(_words[1]);
            name_safe=sanitise(_words[2]);

            # Compose a process that makes a new entry for the user:
            PROC=\
            _global["GREP_PATH"] " -iE '^" channel_safe " ' 'cache/inhabitants' | " \
            _global["GREP_PATH"] " -oiE ' [" privilege_symbols "]*" name_safe "' | "


            # If the mode operation is '+', then add the symbol to the entry.
            if ( sign=="+" ) {
               PROC=PROC _global["SED_PATH"] " -Ee 's/^ /\\" symbolic "/'"
            # Else, if it's '-', remove the symbol from the entry:
            } else {
               PROC=PROC _global["SED_PATH"] " -Ee 's/\\" symbolic "//g'"
            }
            # Run this new process, getting a new entry:
            PROC | getline new_entry; close(PROC);

            # Uh.. remove all spaces.
            gsub(/ /,"",new_entry);

            # Now, construct another sed command that inserts the new mode into the file:
            PROC=\
            _global["SED_PATH"] " -i'' -Ee '/^" channel_safe " / s/ [" privilege_symbols "]*" name_safe " / " gensub(/&/,"\\\\\\&","G",new_entry) " /' 'cache/inhabitants'"
            system(PROC); close(PROC);

            # Reset variables:
            PROC=""; name_safe=""; new_entry=""; symbolic=""; channel_safe=""; sign=""; character="";
         } break;
      # "cmode" operates similarily to "mode": it parses 
      case "cmode":
         # If no entry for the given channel exists, complain and exit:
         if ( code==0 ) {
            print "[#] No entry for '" _words[1] "' in the inhabitants file." >> "/dev/stderr";
            return "";
         # Else, we get to work.
         } else {
            # First, divide every single character in _words[3]:
            patsplit(_words[2],_characters,/./);

            # Set the mode_operation to '+':
            mode_operation="+";

            # And go over each individual character:
            for ( char in _characters ) {
               # If it's a + or -, set a new mode_operation and continue the loop:
               if (_characters[char] ~ /^(\+|\-)$/) { mode_operation=_characters[char]; continue; }
               # If the mode operation is 'add', then add the symbolic mode to
               # the list of modes to grant the user.
               if ( mode_operation == "+" ) { add_modes=(add_modes _characters[char]);}
               # Else, if the mode operation is 'del', then add the symbolic
               # mode to the list of modes to take away from the user.
               else {rem_modes=(rem_modes _characters[char]);}
            }

            # Finally, we construct a sed/grep command that removes and adds all
            # of the appropriate modes:
            channel_safe=sanitise(_words[1]);

            PROC=\
            _global["GREP_PATH"] " -ioE '^" channel_safe " [^ ]+' 'cache/inhabitants' | " \
            _global["CUT_PATH"] " -d ' ' -f 2 | " \
            _global["SED_PATH"] " -Ee 's/[" rem_modes " ]//g' -e 's/^\\*/*" add_modes "/'"
            PROC | getline new_entry; close(PROC);

            # Now, construct another set command that inserts the new mode into the file:
            PROC=\
            _global["SED_PATH"] " -i'' -Ee 's/^(" channel_safe ") [^ ]+ /\\1 " new_entry " /I' 'cache/inhabitants'"
            system(PROC); close(PROC);

            # Reset variables:
            rem_modes=""; add_modes=""; delete _characters;
         } break;
      # "create" adds a new channel entry to the inhabitants file. This is
      # often called when Mohawk successfully joins a channel.
      case "create":
         # If an entry for this channel already exists, complain and return.
         if ( code==1 ) {
            print "[#] An entry for '" _words[1] "' already exists." >> "/dev/stderr";
            return "";
         } else {
            # Else, add a new entry, close the file, and return.
            print tolower(_words[1]) " * " >> "cache/inhabitants";
            close("cache/inhabitants"); return "";
         } break;
      # "destroy" does the inverse of "create": it removes a channel and its
      # userlist from the inhabitants file.
      case "destroy":      
          # If no such entry exists, complain and return.
         if ( code==0 ) {
            print "[#] An entry for '" _words[1] "' does not exist." >> "/dev/stderr";
            return "";
         } else {
            # Else, sanitise the channelname and write a sed command to
            # remove this entry.
            channel_safe=sanitise(_words[1]);
            PROC=_global["SED_PATH"] " -i'' -Ee '/" channel_safe " /I d' 'cache/inhabitants'"
            break;
         } break;
      # If the operation is none of the above, complain and return:
      default:
         print "[#] inhabitants(): no such operation '" operation "'" > "/dev/stderr"
         return;
   }

   # Run PROC, and we're done here.
   system(PROC); close(PROC);

   # Reset essential variables:
   channel_safe=""; name_safe="";
}

################################################################################
# Internet Relay Chat Protocol
################################################################################
# This is where the real deal 'begins'. This, is where the bot utilises all of
# the previously declared functions and clauses 
################################################################################
END {
   # Start diagnosing:
   diagnose();

   # If a fatal error has occurred, then exit immediately.
   if ( fatal ) {
      print "[!] One or more fatal errors occurred. Exiting." > "/dev/stderr";
      exit fatal;
   }

   # Force _plugins and _channels to become arrays just in case:
   _global["_channels"][0]; delete _global["_channels"][0];
   _global["_plugins"][0]; delete _global["_plugins"][0];
   
   # Verify that necessary arguments have been supplied:
   if ( !(_global["server"] && _global["nick"]) ) {
      print "[!] Must at least specify 'server' and 'nick' fields!" > "/dev/stderr";
      exit 7;
   }; if ( !_global["user"] ) {
      _global["user"] = _global["nick"]
   }; if ( !_global["realname"] ) {
      _global["realname"] = _global["nick"]
   }; if ( !("@" in _global["_channels"] ) ) {
      print "[!] No entry allocated for channel '@' (messages sent in private)." > "/dev/stderr";
      exit 8;
   }; if ( !(_global["_channels"]["@"]["IDLE"]) ) {
      print "[#] No value set for '@'s IDLE timer. Defaulting to '5'";
      _global["_channels"]["@"]["IDLE"]=5;
   } else {
      _global["_channels"]["@"]["IDLE"]=strtonum(_global["_channels"]["@"]["IDLE"]);
   }
   
   # Let the port default to 6667
   if ( !_global["port"] ) { _global["port"] = "6667" }

   # Wipe the inhabitants file:
   print "" > "./cache/inhabitants"; close("./cache/inhabitants");

   # Initialise our socket:
   IRC_SOCK = "/inet/tcp/0/" _global["server"] "/" _global["port"]

   # Send our NICK and USER messages:
   send("NICK " _global["nick"]);
   send("USER " _global["user"] " 0 * :" _global["realname"]);

   # Start our read-loop, the real 'program' starts here.
   while ((IRC_SOCK |& getline) > 0) {
      print "[<] " $0
      # Cut out CRLF
      gsub( /[\r\n]/ , "" );

      # Handle pings accordingly; if the first (and only) word is PING, then:
      if ($0 ~ /^PING/) {
         # Reply accordingly, reusing $2.
         send("PONG " $2);

         # If there's an entry for '@' in the process list:
         if ("@" in _proclist) {
            # Increment the @ channels' idletimer. If it exceeds the max, turn "@" off.
            if ( ++idle_priv > _global["_channels"]["@"]["IDLE"] ) {
               power_off("@");
               print "[@] Idle timer reached desired value. Powering off '@'...";
            }
         }

         # No need to handle anything after this.
         continue;
      }

      # Set a 'who' variable containing the nick of the user/server who
      # executed the command. This is everything following the leading colon
      # (:) to either the first piece of whitespace, or the first
      # exclamation mark (!):
      who=gensub(/^:([^! ]+)[! ].+/,"\\1","G");

      #########################################################################
      # Now, we iterate over and handle all possible kinds of messages like
      # JOIN, PRIVMSG, etc. using a switch statement.
      #
      # Every handler does its own required administration. They may also
      # set a singular, pivotal variable: relevant_channel. relevant_channel
      # is a comma-separated list of channels that the given message
      # affects.
      #
      # After this switch statement, there is a block of code that supplies
      # $0 to all of the plugin processes these channels have.
      switch ($2) {
            ###################################################################
            # Handle PRIVMSG - Private Messages.
            ###################################################################
            case "PRIVMSG":
               # If the recieves message was set in private, substit
               if ( tolower($3) == tolower(_global["nick"]) ) {
                  relevant_channel="@";
                  $3=who;
                  # If there's no _proclist entry for '@', then power it on:
                  if ( !("@" in _proclist) ) {
                     print "[@] Private message- powerif on '@'...";
                     power_on("@");
                     # Reset the idle counter:
                     idle_priv=0;
                  }
               } else {
                  relevant_channel=$3;
               }
               break;
            ###################################################################
            # Handle NOTICE - Notices.
            ###################################################################
            case "NOTICE":
               relevant_channel=$3;
               break;
            ###################################################################
            # Handle JOIN - Joining a channel.
            ###################################################################
            case "JOIN":
               relevant_channel=substr($3,2);
               # Verify which user in question joined the channel.
               # If it was Mohawk, then call power_on(), and add an entry
               # for the channel in the inhabitants file. Also send a query
               # to the server to retrieve this channels' set modes:
               if ( tolower(who) == tolower(_global["nick"]) ) {
                  power_on(relevant_channel);
                  inhabitants("create",relevant_channel);
                  send("MODE " relevant_channel);
               # If it was another user, then appropriately edit the
               # inhabitants file:
               } else {
                  inhabitants("join",relevant_channel " " who);
               }

               break;
            ####################################################################
            # Handle PART - Departing from a channel.
            ####################################################################
            case "PART":
               relevant_channel=$3;
               # Verify which user in question left the channel. If it was us,
               # call power_off(), and destroy this channels' entry in the
               # inhabitants file.
               if ( tolower(who) == tolower(_global["nick"]) ) {
                  power_off(relevant_channel);
                  inhabitants("destroy",relevant_channel);
               # If it was another user, then appropriately edit the
               # inhabitants file by removing them from this channel:
               } else {
                  inhabitants("part",relevant_channel " " who);
               }

               break;
            ####################################################################
            # Handle KICK - Being kicked from a channel.
            ####################################################################
            case "KICK":
               relevant_channel=$3;
               # Verify which user in question got kicked. If it was us, call
               # power_off(), and destroy this channels' entry in the
               # inhabitants file.
               if ( tolower($4) == tolower(_global["nick"]) ) {
                  power_off(relevant_channel);
                  inhabitants("destroy",relevant_channel);
               # If it was another user, then appropriately edit the
               # inhabitants file by removing them from the channel.
               } else {
                  inhabitants("part",relevant_channel " " who);
               }

               break;
            ####################################################################
            # Handle INVITE - Being invited to a channel.
            ####################################################################
            case "INVITE":
               relevant_channel=substr(tolower($4),2);
               # If the relevant channel is not in any explicit
               # configuration block, then use the contents of *:
               if ( !(relevant_channel in _global["_channels"]) ) {use_contents="*";}
               else {use_contents=relevant_channel;}
               # Verify which user in question got invited. If it is us,
               # check this channel's invite policy:
               if ( tolower($3) == tolower(_global["nick"]) ) {
                  switch(substr(_global["_channels"][use_contents]["INVITE"],1,1)) {
                     case "2":
                        # See if the inviter is in the list of allowed people:
                        if ( substr(_global["_channels"][use_contents]["INVITE"],3) ~ ("(^| )" sanitise_regex(who) "($| )")) {
                           send("JOIN :" relevant_channel);
                           send("NOTICE " who " :Joining " relevant_channel "...");
                        } else {
                           send("NOTICE " who " :You are not listed in the invite policy for this channel.");
                        } break;
                     case "1": 
                        send("JOIN :" relevant_channel);
                        send("NOTICE " who " :Joining " relevant_channel "...");
                        break;
                     default:
                        send("NOTICE " who " :Invite policy for this channel is deny-all.");
                        break;
                  }
               }
               break;
            ####################################################################
            # NICK - Handle nick changes
            ####################################################################
            case "NICK":
               # If it was us who changed our nick, update the _global["nick"]
               # variable.
               if ( tolower(who) == _global["nick"] ) {
                  _global["nick"]=$3
               }
               # In any case, compile a list of relevant channels to send the
               # nick change message to.
               PROC=\
               _global["GREP_PATH"] " -iE ' [" privilege_symbols "]*" who " ' 'cache/inhabitants' | " \
               _global["CUT_PATH"] " -d ' ' -f 1 | " _global["TR_PATH"] " '\\n' ','"
               PROC | getline relevant_channel; close(PROC);

               # Regardless of what happened, update the inhabitants file:
               inhabitants("nick",who " " substr($3,2));

               break;
            ####################################################################
            # QUIT - Handle people leaving.
            ####################################################################
            case "QUIT":
               # In any case, compile a list of relevant channels to send the
               # QUIT message to.
               PROC=\
               _global["GREP_PATH"] " -iE ' [" privilege_symbols "]*" who " ' 'cache/inhabitants' | " \
               _global["CUT_PATH"] " -d ' ' -f 1 | " _global["TR_PATH"] " '\\n' ','"
               PROC | getline relevant_channel; close(PROC);

               # Regardless of what happened, update the inhabitants file:
               inhabitants("quit",who);

               break;
            ####################################################################
            # 001 - RPL_WELCOME - Let's Roll
            ####################################################################
            case "001":
               # Join all appropriate channels:
               send("JOIN :" gensub(/\s+/,",","G",_global["join"]));

               # If nickserv is enabled, identify:
               if (_global["nspass"] != "") {
                  send("PRIVMSG nickserv :identify " _global["nspass"]);
               }

               break;
            ####################################################################
            # 005 - """RPL_BOUNCE""" (Really just server capabilities).
            ####################################################################
            # At the beginning of every connection, a list of server
            # capabilities are echoed using 005. These contain a
            # space-separated list of: IDENT(=VALUE)?
            # These are matched and then stored in _global[IDENT]=VALUE
            # ('VALUE' defaulting to '1' if it is mising.)
            #
            # This handler will NOT overwrite existing variables. If it
            # encounters a variable with the same name as the IDENT, it will
            # simply move on. This way, one may overrule the capabilities
            # sent by 005 in the config if so desired.
            case "005":
               # Take everything from the fourth input record up to the
               # message, take every string of characters separated by
               # whitespace, parse the ident and value, then assign them to
               # _global appropriately.
               caplist=gensub(/^:[^ ]+ 005 [^ ]+ (.+) :are supported by this server$/,"\\1","G",$0);
               split(caplist,_caplist);
               
               for ( cap_pair in _caplist ) {
                  # Take the ident and value:
                  ident=gensub(/^([^=]+).*$/,"\\1","G",_caplist[cap_pair]);
                  if ( index(_caplist[cap_pair],"=") != 0 ) {
                     value=gensub(/^[^=]+=(.+)$/,"\\1","G",_caplist[cap_pair]);
                  # If no value appears in the cap, assign '1':
                  } else {value=1}

                  # Assign the value:
                  if ( !(ident in _global) ) {_global[ident]=value}

                  # If the identifier happens to be the STATUSMS, cache a list
                  # of symbols that both the inhabitants() function and NICK
                  # handler will utilise.
                  if (ident=="STATUSMSG") {
                     privilege_symbols=gensub(/./,"\\\\&","G",_global["STATUSMSG"])
                  }
               }

               # And, reset the variables:
               caplist=""; delete _caplist;

               break;
            ####################################################################
            # 324 - RPL_CHANNELMODEIS - Channel Mode Declaration
            ####################################################################
            case "324":
               # Returned after Mohawk calls `MODE #CHANNEL`. Do nothing but
               # forward $5 (a list of channel modes) into channel $4 by
               # calling the "cmode" functionality in the inhabitants()
               # function.
               inhabitants("cmode",tolower($4) " " $5);
               
               break;
            ####################################################################
            # 353 - RPL_NAMREPLY - Update Username Registers
            ####################################################################
            case "353":
               # In response to a NAMES or JOIN query, the IRCd may send
               # multiple 353 replies in quick succession (often because the
               # 512 character limitation is not enough to describe all of
               # the channels' inhabitants). However, only the FIRST 353
               # reply in a sequence must wipe the inhabitants list for this
               # channel. Thus, we must keep track of whether the current
               # 353 message is the first in a sequence or not. We do this
               # by altering and reading a single numerical variable: if the
               # variable is '0', then the current 353 message is not the
               # new one in a series. If the variable is '1', then the
               # current 353 message is the new one in a series, and the
               # inhabitants list must be wiped. Once the inhabitants list
               # is wiped, this variable is temporarily set to '0' until a
               # 366 (RPL_ENDOFNAMES) arrives. When a 366 reply arrives
               # (meaning no more 353 replies are inbound), the variable is
               # set back to '1'.
               #
               # To prevent problems arising when it comes to interlaced
               # NAME replies (e.g. querying NAMES for two channels in quick
               # succession), each channel will get an individual instance
               # of the aforementioned binary variable. These will be stored
               # in _new_353[channel_name]. Some IRCds might be smart and
               # only send 353 replies in a set order, but I refuse to take
               # any chances- better be safe than sorry.
               #
               # $5 is the channel name, $6 and onwards are all the names of
               # individual inhabitants (note that $6 contains a colon
               # still.)
               #
               # Temporarily save the channel name, then wipe the rest of
               # the input record:
               relevant_channel=tolower($5);
               $1="";$2="";$3="";$4="";$5="";
               # Clear leading whitespace and colon, then recalculate the
               # input record.
               gsub(/^\s*:/,"",$0); $0;

               # If this is the first 353 entry in a series, call
               # inhabitants with part_all for the given channel, and
               # temporarily set the variable to '0'.
               if ( _new_353[relevant_channel]!=0 ) {
                  inhabitants("part_all",relevant_channel);
                  _new_353[relevant_channel]=0;
               }
               # Add the full list of inhabitants to the channel entry. Due
               # the way in which inhabitants() handles "join" operations,
               # we may simply supply what is left as the input record as
               # the "user" list:
               inhabitants("join",relevant_channel " " $0);

               break;
            ####################################################################
            # 366 - RPL_ENDOFNAMES - End Username Registry Update
            ####################################################################
            case "366":
               # As stated above, the 366 handler just sets the appropriate
               # binary variable back to '1' (so when the next stream of 353
               # replies for this channel arrives, the name list gets reset
               # appropriately).
               relevant_channel=tolower($4);
               _new_353[relevant_channel]=1;

               break;
            ####################################################################
            # MODE - Handle either umode or chmode changes - Welcome To Hell.
            ####################################################################
            case "MODE":
               #################################################################
               # If the given MODE is +r or something similar (meaning services
               # set us to registered), JOIN all channels again (in case of
               # channels that are +R)
               if ( $0 ~ ("^:[^ ]+ MODE " _global["nick"] " :.*\\+[^\\-]*r")) {
                  # Join all our channels once again:
                  send("JOIN :" gensub(/\s+/,",","G",_global["join"]));
               # Else, it must be a... channel mode of some sort.
               } else {
                  # Set the relevant channel:
                  relevant_channel=$3;
                  ##############################################################
                  # We parse MODE messages from left to right.
                  # $4 is a list of alphabetical channelmode characters such
                  # as +b, +m, +v, etc.
                  #
                  # Everything following $4 ($5, $6, $7 etc.) are parameters
                  # for the MODE command (which mask to ban, which user to 
                  # voice, etc.) Since all MODE characters that require a
                  # parameter always appear AFTER all characters that need
                  # no parameter, we can safely assume that (length($4)-NF-4)
                  # adequately represents the amount of modes without a
                  # parameter.
                  non_parameter=(length(gensub(/[\-\+]/,"","G",$4)) - (NF-4))

                  # Split and iterate over all characters:
                  patsplit($4,_characters,/./);
                  for ( character in _characters ) {
                     # Temporarily store this variable for easy access.
                     c_char=_characters[character]
                     # If it's a + or -, set the handle mode accordingly.
                     if (c_char == "+") {mode="+"}
                     else if (c_char=="-") {mode="-"}
                     # Else, add the mode character either to a list of
                     # usermodes that need be altered, or a banlist that
                     # needs be altered:
                     else  {
                        charcount++
                        if (charcount<=non_parameter) { cmodes=(cmodes mode c_char) }
                        else {
                           inhabitants("mode",$3 " " $(4+(charcount-non_parameter)) " " (mode c_char))
                        }
                     }
                  }
                  inhabitants("cmode",$3 " " cmodes);
                  charcount=0;c_char="";delete _characters;cmodes="";mode="";
               }
               break;
            ####################################################################
            # End handling of IRC Messages.
            ####################################################################
      }

      # Split relevant_channel into an array and iterate over it.
      split(relevant_channel,_channels,",");
      for ( channel in _channels ) {
         # Turn the variable lowercase and temporarily store it in
         # relevant_channel.
         relevant_channel=tolower(_channels[channel]);

         # If this channel has processes:
         if ( relevant_channel in _proclist ) {
            # Execute all of them.
            for ( proc in _proclist[relevant_channel] ) {
               #################################################################
               # LOCALISATION HOOK - Used to differentiate NICK and QUIT.  
               #################################################################
               # Adds the channel name (relevant_channel) after the QUIT/NICK
               # message. Remove this if you're gutting Mohawk for parts or
               # something.
               #################################################################
               if ( _global["_plugins"][_proclist[relevant_channel][proc]]["LOCALISE"]=="YES" ) {
                  if ($2 ~ /NICK/) {$2="NICK " relevant_channel}
                  else if ($2 ~ /QUIT/) {$2="QUIT " relevant_channel}
               }
               run_proc(_proclist[relevant_channel][proc],$0);
               #################################################################
               # And turn $2 back into one word:
               $2=gensub(/^([^ ]+) .*/,"\\1","G",$2);
            }
         }
      }
      # Reset the relevant_channel variable:
      relevant_channel="";
   }

   # Neatly close our connection.
   close(IRC_SOCK)

   # We have been disconnected from the server. Power off each individual channel:
   for ( channel in _global["_channels"] ) { power_off(channel); }

   # And show a proper disconnection message:
   print "[@] Mohawk has cleanly disconnected from the server.";
}