function arg3 ( allowed )
{
    ###########################################################################
    # SPECIALISED ARGUMENT PARSER v3 - Most likely ripped from src/arg3.awk
    ###########################################################################
    # You may also load this program into your plugin using @include
    ###########################################################################
    # Starts from the start of the current input record, and iterates over
    # all fields. If the field starts with a '-' or a '--', then the
    # characters following it will be treated as flags. Short options may
    # appear consecutively without extra dashes (e.g. -aeo = -a -e -o).
    # Flags may be terminated with a ' ' or a '='. If the latter is used,
    # then any characters following it will be used as an argument,
    # terminated by a non-escaped ' '. If the character following the '=' is
    # a '"', then another non-escaped '"' will be treated as the sentinel.
    # --option
    # --option=argument
    # --option=arguments\ here
    # --option="arguments \"go\" here"
    # These will be stored in array 'flags'. This array looks like:
    # flags["option"] = arguments "go" here
    # You know the drill.
    ###########################################################################
    # ALLOWED STRING
    ###########################################################################
    # arg3() requires argument: allowed. This is a special string that
    # dictates which flags are allowed, and which aren't. Flags are
    # specified in bunches, separated by spaces. A bunch is a
    # space-delimited list of ASCII characters enclosed by square brackets.
    #
    # A bunch must be preceded by an identifier, optionally followed by a
    # colon for readability. identifier can be used to retrieve the results or
    # presence of a flag.
    #
    # A bunch may look like:
    # do_debug:[d debug gdb]
    # This bunch describes flags "debug", "d", and "gdb". This means that
    # they will be treated synonymously- all of them share the same
    # properties. If any flags from this bunch have been specified, they
    # will be assigned to the identifier:
    # --debug="yes" => flags["do_debug"] = "yes"
    # -d => flags["do_debug"] = ""
    # --gdb => flags["do_debug"] = ""
    # --debug => flags["debug"] = void
    # This allows the overarching program to check for the presence of any
    # flag in this bunch.
    #
    # Bunches may be succeeded by a number:
    # do_debug:[d debug gdb]2
    # This number indicates in which group the bunch falls into. If two flags
    # from two different bunches in the same group are specified, an error
    # will be raised.
    #
    # Bunches may also be followed by a slash-delimited pattern:
    # do_debug:[d debug gdb]2/^([Yy][Ee][Ss]|[Nn][Oo])$/
    # This can be a regular awk pattern. If it is supplied, then the
    # argument handed to any flag in the bunch will be matched against this
    # pattern. If it doesn't match, then an error will be thrown. To make a
    # flag optional, one must ensure that the pattern given must also match
    # an empty string (""). To prohibit usage of a flag, one can simply
    # supply the following pattern:
    # no_debug:[D no-debug debug_no]2/^$/
    # If one wants a literal '/' to appear in the pattern, it must be
    # escaped.
    #
    # No errors will be thrown for unpaired braces, they will be ignored.
    # Beware!
    #
    # Sub-bunches are bunches that may only be used in conjunction with
    # their "head-bunch". A sub-bunch is specified as:
    # head_bunch->sub_bunch:[flags]group/pattern/
    # Take for example:
    # sync:[S Sync]1
    # sync->install[i install]2
    # sync->upgrade[u upgrade]2
    # Now, the '-u' and '-i' flags may only be used in conjunction with the
    # -S flag, and may not be used together: -Si is valid, so is -Su.
    # A sub-bunch may have multiple head bunches: the head bunches must be
    # separated by commas:
    # sync,dummysync->install[i install]2
    # Now if either sync or dummysync has been supplied, install can be
    # used.
    #
    # Optionally, following the group number, preceved by an 'm', a so-called 
    # "intensity cap" may be specified. The "intensity cap" is the maximum
    # number of times flags from a bunch may be specified. e.g. let's say
    # the intensity cap for '-v' is 5:
    # verbosity:[v verbose]1m5
    # VALID                                  INVALID
    # -vv                                    -vvvvvv
    # -vvvvv                                 --verbose --verbose -vvvv
    # --verbose --verbose -v                 --verbose --verbose -vvvvvvvvvvv
    # The intensity cap is '1' by default.
    #
    # If the argument pattern is followed by a string delimited with {}s,
    # then if this bunch is specified, this string will be placed into the
    # flags[-3] array:
    # taiko[t]1{&m=1}
    # standard[s]1{&m=0}
    # -s => flags[-3]["1"] = "&m=0"
    # -t => flags[-3]["1"] = "&m=1"
    # If the } is followed by an exclamation mark (!) then this string will
    # be used if none of the flags from this group have been specified.
    #
    # Tip: if one wants to have a default that can only be activated by not
    # specifying flags belonging to any of the bunches in the group, one can
    # simply create a new bunch with an empty flag list in that group:
    # DEFAULT_MODE[]1{}!
    ###########################################################################
    # The 'allowed' argument is REQUIRED- if one wants to match whatever
    # flags, use src/arg.awk.
    ###########################################################################
    # Allowedstrings are parsed and cached in bunches[allowed_string] so that
    # they may be quickly re-used later once turned into an array.
    ###########################################################################
    # If the flags given do not conform to the allowedstring, then arg3() will
    # return a '1' and flags[0] will contain an error message. arg3() will
    # return a '0' if no problems've been encountered.
    ###########################################################################
    # With arg3(), flags[-1] will be an array of which flag from which group
    # has been specified. e.g.:
    # --debug
    # => flags[-1]["2"] = "do_debug"
    # BEGIN ARGUMENT PARSING HERE
    ###########################################################################
    # Like with groups- intensity levels for each flag are stored in
    # flags[-2]. e.g. -vvvvv
    # flags[-2]["verbosity"] = 5
    ###########################################################################
    # First, we turn all escaped spaces into ASCII 000s, and all escaped
    # quotes into ASCII 001s. This is to prevent us from having to mess
    # around with escaping these within RegExes.
    gsub(/\\ /,"\000");
    gsub(/\\\\/,"\001");
    gsub(/\\"/,"\002");

    # Nuke important variables:
    delete flags; value=""; flag="";
    flags[-1][""] ; flags[-2][""] ; flags[-3][""]

    # If the allowed string isn't cached yet:
    if ( !( allowed in bunches ) ) {
        # Substitute out the double backslashes and escaped square brackets for ASCII 000s, 001s, and 002s
        parse_allowed=gensub(/\\\\/,"\000","G",allowed)
        parse_allowed=gensub(/\\\[/,"\001","G",parse_allowed)
        parse_allowed=gensub(/\\\]/,"\002","G",parse_allowed)
        parse_allowed=gensub(/\\\}/,"\003","G",parse_allowed)
        # Now, we attempt to separate each bunch.
        patsplit( parse_allowed , bunchlist , /[^:\[]*:?\[[^\[\]]*\][^\/ {]*(\/[^\/]*\/)?({[^}]*}!?)?\s*/ )

        # Now, iterate over each bunch, parsing each bunch:
        # If argstring is:
        # do_debug:[gdb d debug]2/^(y(es)?|no?)$/ dont_debug:[no-debug D DontDebug]2/^$/
        # do_debug->debug_mode:[mode m]3/^(safe|extreme)$/
        # verbosity:[v verbose]4m5{-v}!
        # Then bunches[] looks like:
        # bunches[argstring]  = {
        #	["flags"] = {
        #		["d"] = "do_debug";
        #		["debug"] = "do_debug";
        #		["gdb"] = "do_debug";
        #		["no-debug"] = "dont_debug";
        #		["D"] = "dont_debug";
        #		["DontDebug"] = "dont_debug";
        #	}
        #	["arguments"] = {
        #		["do_debug"] = "^(yes|no)$"
        #		["dont_debug"] = "^$"
        #	}
        #	["groups"] = {
        #		["do_debug"] = 2
        #		["dont_debug"] = 2
        #	}
        #	["depends"] = {
        #		["debug_mode"] = "do_debug"
        #	}
        #	["icap"] = {
        #		["verbosity"] = 5
        #	}
        #	["default"] = {
        #		["verbosity"] = "-v"
        #	}
        #	["gdefault"] = {
        #		["4"] = "-v"
        #	}
        # }
        # You're smart- you'll figure it out.
        # Prevent "scalar context" errors:
        bunches[allowed]["flags"][""]
        bunches[allowed]["arguments"][""]
        bunches[allowed]["groups"][""]
        bunches[allowed]["depends"][""]
        bunches[allowed]["icap"][""]
        bunches[allowed]["default"][""]
        bunches[allowed]["gdefault"][""]
        # Start parsing.
        for ( i in bunchlist ) {
            # Match the bunch so that:
            # parts[1] = head_bunch, parts[2] = identifier, parts[3] = flags, 
            # parts[4] = group, parts[5] = intensity cap,
            # parts[6] = pattern, parts[7] = pattern sans slashes,
            # parts[8] = defaultstring , parts[9] = defaultstring sans braces.
            # parts[10] = exclamation_mark
            match( bunchlist[i] , /(.+->)?([^:\[]*):?\[([^\[\]]*)\]([^\/ m{]*)(m[^\/ {]*)?(\/([^\/]*)\/)?({([^}]*)}(!?))?/ , parts );

            # If parts[1] is non-empty, remove the -> and put all head bunches in an array 'heads':
            if ( parts[1] !~ /^$/ ) {
                parts[1]=substr(parts[1],1,length(parts[1])-2)
                split(parts[1],heads,",")
            }
            # Same for parts[5] and 'm':
            if ( parts[5] !~ /^$/ ) { parts[5]=substr(parts[5],2) }

            # If parts[2] is empty, complain:
            if ( parts[2] ~ /^\s*$/ ) {
                print "[#] Missing identifier in allowedstring: " bunchlist[i] >> "/dev/stderr" ; return
            # Else, if parts[1] is specified, see if the head bunches exist:
            } else if ( parts[1] !~ /^\s*$/ ) {
                for ( head in heads ) {
                    # If it doesn't, complain:
                    if ( !( heads[head] in bunches[allowed]["groups"] ) ) {
                        print "[#] No such head bunch '" parts[1] "'" >> "/dev/stderr" ; return
                    }
                }
            # Else, if parts[4] is missing or not a number, complain:
            } else if ( parts[4] !~ /^[0-9]+$/ ) {
                print "[#] Malformed or missing group number for bunch " parts[2] " '" parts[4] "'" >> "/dev/stderr" ; return
            # Else, if parts[5] is neither empty or not a number, complain:
            } else if ( parts[5] !~ /^[0-9]*$/) {
                print "[#] Malformed or intensity cap for bunch " parts[2] " '" parts[5] "'" >> "/dev/stderr"
            # Else, if parts[9] is present (and a '!'), check whether this is the first default"
            } else if ( (parts[10] == "!") && (parts[4] in bunches[allowed]["gdefault"]) ) {
                print "[#] Multiple defaults for group " parts[4] >> "/dev/stderr" ; return
            }

            # Turn the escaped double slashes and escaped square brackets back for each part:
            gsub(/\000/,"\\",parts[2])
            gsub(/\000/,"\\",parts[3])
            gsub(/\000/,"\\",parts[7])
            gsub(/\002/,"\\",parts[9])
            gsub(/\001/,"[",parts[2])
            gsub(/\001/,"[",parts[3])
            gsub(/\001/,"[",parts[7])
            gsub(/\001/,"[",parts[9])
            gsub(/\002/,"]",parts[2])
            gsub(/\002/,"]",parts[3])
            gsub(/\002/,"]",parts[7])
            gsub(/\002/,"]",parts[9])
            gsub(/\003/,"}",parts[2])
            gsub(/\003/,"}",parts[3])
            gsub(/\003/,"}",parts[7])
            gsub(/\003/,"}",parts[9])
            # Take each separate flag in parts[3]:
            split( parts[3] , pieces );

            # Iterate over them:
            for ( flag in pieces ) {
                bunches[allowed]["flags"][pieces[flag]]=parts[2]
           }

            # Assign the appropriate group:
            bunches[allowed]["groups"][parts[2]]=parts[4]

            # And assign the pattern regex:
            bunches[allowed]["arguments"][parts[2]]=parts[7]


            # Assign the head bunch if specified:
            if ( parts[1] !~ /^\s*$/ ) {
                # Iterate over each bunch and assign them as the key:
                for ( head in heads ) {
                    bunches[allowed]["depends"][parts[2]][heads[head]]=1
                }
            }

            # Assign the intensity cap if specified:
            if ( parts[5] !~ /^\s*$/ ) {
                bunches[allowed]["icap"][parts[2]]=strtonum(parts[5])
            } else {
                # Else, let it default to 1:
                bunches[allowed]["icap"][parts[2]]=1
            }

            # Assign the defaultstring:
            bunches[allowed]["default"][parts[2]]=parts[9]

            # If parts[10] is present, assign this defaultstring as the group default:
            if ( parts[10] == "!" ) {
                bunches[allowed]["gdefault"][parts[4]]=parts[9]
            }

            # Delete parts for the next iteration:
            delete parts; delete pieces; delete heads;
        }
    }

    # Put all individual strings into an array 'strs'
    patsplit($0,strs,/"[^"]+"/)
    # Iterate over them.
    for ( i in strs ) {
        # The first gensub statement escapes all RegEx operators in the current string, and then uses it
        # as the first argument to gsub. The latter gensub argument turns
        # all spaces into ASCII 000s. The net result is that in the input
        # record, all spaces occurring between two quotes are now turned
        # into NULLs.
        gsub(gensub(/[\.\^\$\\\[\]\|\(\)\*\+\?\{\}]/,"\\\\&","G",strs[i]),gensub(/ /,"\000","G",strs[i]))
    }

    # Now we iterate over our input records.
    for ( i=1 ; i<=NF ; i++ ) {
        # If the current input record starts with two flags, it must be a long option.
        if ( $i ~ /^--/ ) {
            # This gensub statement retrieves the flag name.
            flag=gensub(/^--([^= ]+)([= ].+|\s*$)/,"\\1","G",$i)
            # Verify the flag is allowed to begin with:
            if ( !(flag in bunches[allowed]["flags"]) ) {
                # If not, throw an error:
                flags[0] = "Invalid flag: '" flag "'" ; return 1
            }

            # If the flag belongs to a sub-bunch, check if a flag in its head bunch has been specified:
            if ( bunches[allowed]["flags"][flag] in bunches[allowed]["depends"] ) {
                # Iterate over all heads:
                if ( isarray(bunches[allowed]["depends"][bunches[allowed]["flags"][flag]]) ) {
                    for ( head in bunches[allowed]["depends"][bunches[allowed]["flags"][flag]] ) {
                        # If it exists, break from the loop and set success to '1':
                        if ( head in flags ) {
                            success=1;break
                        }
                    }
                    # If success is still 0, complain:
                    if ( !success ) {
                        # Create a string to print for the error:
                        for ( head in bunches[allowed]["depends"][bunches[allowed]["flags"][flag]] ) {
                            required_heads=required_heads ", " head
                        }
                        # Throw an error:
                        flags[0] = "Flags from group '" bunches[allowed]["flags"][flag] "' may only be used in conjunction with flags from groups '" gensub(/^\s*/,"","G",gensub(/,([^,]*)$/," or\\1","G",substr(required_heads,2))) "'"
                        return 1;
                    }
                }
                success=0;
            }

            # Verify that the flags' intensity is under the cap:
            if ( flags[-2][bunches[allowed]["flags"][flag]] >= bunches[allowed]["icap"][bunches[allowed]["flags"][flag]] ) {
                # Throw an error:
                flags[0] = "Flags from group '" bunches[allowed]["flags"][flag] "' may only occur a maximum of " bunches[allowed]["icap"][bunches[allowed]["flags"][flag]] " times."; return 1
            # Else, increase the intensity:
            } else {
                flags[-2][bunches[allowed]["flags"][flag]] += 1
            }
            # If the another flag from another bunch in the same group has already been
            # specified:
            if ( (bunches[allowed]["groups"][bunches[allowed]["flags"][flag]] in flags[-1]) && (flags[-1][bunches[allowed]["groups"][bunches[allowed]["flags"][flag]]] != bunches[allowed]["flags"][flag]) ) {
                flags[0] = "Conflicting flags from groups '" bunches[allowed]["flags"][flag] "' and '" flags[-1][bunches[allowed]["groups"][bunches[allowed]["flags"][flag]]] "'" ; return 1
            # If not, set this group to occupied:
            } else {
                flags[-1][bunches[allowed]["groups"][bunches[allowed]["flags"][flag]]] = bunches[allowed]["flags"][flag]
                # And assign this flag's defaultstring to this group:
                flags[-3][bunches[allowed]["groups"][bunches[allowed]["flags"][flag]]] = bunches[allowed]["default"][bunches[allowed]["flags"][flag]]
            }

            # This uh... retrieves any given value.
            value=gensub( /\001/ , "\\\\" , "G" , gensub( /\002/ , "\"", "G" , gensub( /"([^"]+)"/ , "\\1" , "G" , gensub( /\000/," ","G", substr( gensub(/^--[^=]+(=.+)?$/,"\\1","G",$i) , 2 ) ) ) ) )

            # Check whether the given value conforms to the pattern in the allowedstring:
            # (Note: if no pattern in the allowedstring was supplied, this will always pass, since anything ~ "" => true)
            if ( value !~ bunches[allowed]["arguments"][bunches[allowed]["flags"][flag]] ) {
                # If it doesn't, throw an error:
                flags[0] = "Invalid argument for flag '" flag "': '" value "'" ; return 1
            }

            # Set the identifier:
            flags[ bunches[allowed]["flags"][flag] ] = value

            # Reset the flag and value.
            flag="";value=""
        } else if ( $i ~ /^-/ ) {
        # If it's a singular option:
            # Put each character into an array:
            delete strs;
            patsplit(substr($i,2),strs,/./);
            # And then iterate over it, inserting them as keys into flags[].
            for ( flag in strs ) {
                # Look ahead- if the next flag, flag+1 is an '=', then an argument must follow it:
                if ( strs[flag+1] == "=" ) {
                    # Catch this value:
                    value = gensub( /\001/ , "\\\\" , "G" , gensub( /\002/ , "\"", "G" , gensub( /"([^"]+)"/ , "\\1" , "G" , gensub( /\000/," ","G", substr( gensub(/^-[^=]+(=.+)?$/,"\\1","G",$i) , 2 ) ) ) ) )
                    # Set do_break so this loop stops soon:
                    do_break=1
                # If the next flag is a number, then it must be an argument:
                }

                # Verify the flag is allowed to begin with:
                if ( !(strs[flag] in bunches[allowed]["flags"]) ) {
                    # If not, throw an error:
                    flags[0] = "Invalid flag: '" strs[flag] "'" ; return 1
                }

                # If the flag belongs to a sub-bunch, check if a flag in its head bunch has been specified:
                if ( bunches[allowed]["flags"][flag] in bunches[allowed]["depends"] ) {
                    # Iterate over all heads:
                    if ( isarray(bunches[allowed]["depends"][bunches[allowed]["flags"][flag]]) ) {
                        for ( head in bunches[allowed]["depends"][bunches[allowed]["flags"][flag]] ) {
                            # If it exists, break from the loop and set success to '1':
                            if ( head in flags ) {
                                success=1;break
                            }
                        }
                        # If success is still 0, complain:
                        if ( !success ) {
                            # Create a string to print for the error:
                            for ( head in bunches[allowed]["depends"][bunches[allowed]["flags"][flag]] ) {
                                required_heads=required_heads ", " head
                            }
                            # Throw an error:
                            flags[0] = "Flags from group '" bunches[allowed]["flags"][flag] "' may only be used in conjunction with flags from groups '" gensub(/^\s*/,"","G",gensub(/,([^,]*)$/," or\\1","G",substr(required_heads,2))) "'"
                            success=0;
                            return 1;
                        }
                    }
                    success=0;
                }

                # Verify that the flags' intensity is under the cap:
                if ( flags[-2][bunches[allowed]["flags"][strs[flag]]] >= bunches[allowed]["icap"][bunches[allowed]["flags"][strs[flag]]] ) {
                    # Throw an error:
                    flags[0] = "Flags from group '" bunches[allowed]["flags"][strs[flag]] "' may only occur a maximum of " bunches[allowed]["icap"][bunches[allowed]["flags"][strs[flag]]] " times."; return 1
                # Else, increase the intensity:
                } else {
                    flags[-2][bunches[allowed]["flags"][strs[flag]]] += 1
                }
                # If the another flag from another bunch in the same group has already been
                # specified:
                if ( (bunches[allowed]["groups"][bunches[allowed]["flags"][strs[flag]]] in flags[-1]) && (flags[-1][bunches[allowed]["groups"][bunches[allowed]["flags"][strs[flag]]]] != bunches[allowed]["flags"][strs[flag]]) ) {
                    flags[0] = "Conflicting flags from groups '" bunches[allowed]["flags"][strs[flag]] "' and '" flags[-1][bunches[allowed]["groups"][bunches[allowed]["flags"][strs[flag]]]] "'" ; return 1
                # If not, set this group to occupied:
                } else {
                    flags[-1][bunches[allowed]["groups"][bunches[allowed]["flags"][strs[flag]]]] = bunches[allowed]["flags"][strs[flag]]
                    # And assign this flag's defaultstring to this group:
                    flags[-3][bunches[allowed]["groups"][bunches[allowed]["flags"][strs[flag]]]] = bunches[allowed]["default"][bunches[allowed]["flags"][strs[flag]]]
                }

                # Check whether the given value conforms to the pattern in the allowedstring:
                # (Note: if no pattern in the allowedstring was supplied, this will always pass, since anything ~ "" => true)
                if ( value !~ bunches[allowed]["arguments"][bunches[allowed]["flags"][strs[flag]]] ) {
                    # If it doesn't, throw an error:
                    flags[0] = "Invalid argument for flag '" strs[flag] "': '" value "'" ; return 1
                }

                # Set the identifier:
                flags[ bunches[allowed]["flags"][strs[flag]] ] = value

                # Reset the value
                value=""
                
                # If do_break is set to one, reset it and break:
                if ( do_break == 1 ) { do_break=0 ; break }
            }
        # Else, if a non-flag string has been encountered, stop parsing flags altogether:
        } else if ( $i != "" ) {
            # Remove heading escape:
            gsub(/^\\-/,"-",$i);
            break;
        }
        # Nuke the current field:
        $i = ""
    }
    
    # Iterate over each group default:
    for ( i in bunches[allowed]["gdefault"] ) {
        # If there's nothing set for this group yet:
        if ( !( i in flags[-3] ) ) {
            # Then set this default!
            flags[-3][i] = bunches[allowed]["gdefault"][i]
        }
    }

    # Remove the leading spaces left over:
    sub(/^\s*/,"")
    # Turn all NULLs in the input record back:
    gsub(/\000/," ")
    ###########################################################################
    # END ARGUMENT PARSING HERE
    ###########################################################################
    # Your 'flags' array should now be full of options and arguments. You're
    # welcome.
    ###########################################################################
}
