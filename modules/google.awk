################################################################################
# Google Search API
################################################################################
# VAR command
# LOCALVAR C_google google_api cxl cxd default_safety cxl_map
# RESPOND PRIVMSG
################################################################################
# Queries Google for a specific query and returns these based on relevancy.
# @cxl is a list of search engines in the format: name=ID name=ID name=ID etc.
# @cxd is the name of the search engine to be used by default.
# @google_api is the Google API key to be used.
# @safety is the default search safety level to be used.
# @cxl_map is a list of search engines mappted to commands in the format:
# command=engine command=engine command=engine.
#
# Syntax:
# !g --flags search query
# =USABLE FLAGS=
# --filter, -f=filter_name:filter_value,n:v,n:v etc.
# 	Allows users to specify filters that the search results will be
# 	subjected to. Only search results that conform to the conditions
# 	specified in each filter will be displayed.
#
#	Filters are name-value combinations in the format: name:value
#	NO filter names will contain a colon. Several name-value pairs may
#	be specified in conjunction with one another by delimiting these
#	with a comma:
#	name1:value1,name2:value2,name3:value3 etc.
#
#	A comma may be escaped with a single backslash: \
#	
#	Valid filters:
#	type:image - type:url
#		Return either only images or pages type:url will be assumed the default.
#	domain:domain_name
#		Return only results that belong to the domain specified for
#		this filter. The wildcards '*' and '?' may be used, which
#		mean "any character, greedy" and "any character, one
#		occurence". This is completely similar to the wildcards used
#		in IRC masks.
#	safety:high - safety:medium - safety:off
#		Adjust the safe search filter to high, medium, or off. If
#		this filter is absent, @safety is used. If that is absent,
#		'high' will be used.
#	ctype:color - ctype:gray/grey - ctype:mono
#		Returns coloured, greyscale, or monochrome images only.
#	cdom:c
#		Returns images where the dominant colour is c. c may be one of:
#		black, blue, brown, gray/grey, green, pink, purple, teal,
#		white, or yellow.
#	isize:s
#		Returns only images with the given size 's'. s may be one of:
#		huge, icon, large, medium, small, xlarge/xl, or xxlarge/xxl.
#	itype:t
#		Returns only images corresponding with the given type 't'. t
#		may be one of: clipart, face, lineart, news, or photo
#	rights:r
#		Returns only images or results registered under one of the
#		following licenses, where r is one of: cc_publicdomain,
#		cc_attribute, cc_sharealike, cc_noncommercial, or
#		cc_nonderived. For convenience, the leading 'cc_' may be
#		omitted from all of these.
#	mime:m
#		Returns only images whose mime type matches the one given.
# == SHORTHANDS ==
# The following flags are all acceptable shorthand for a filter. If both one
# of these flags and their corresponding filter are present, then these ones
# will be used:
# ===== LONG ===== SHORT === FILTER ===
# | --type=n     | -t=n	 | type:n     |
# | --domain=n   | -d=n	 | domain:n   |
# | --safety=n   | -s=s	 | safety:s   |
# | --ctype=c    | -c=c	 | ctype:c    |
# | --cdom=c     | -C=c	 | cdom:d     |
# | --isize	 | -i=s  | isize:s    |
# | --itype	 | -I=t  | itype:t    |
# | --rights	 | -R=r  | rights:r   |
# | --mime	 | -m=m  | mime:m     |
# | --image      | -p=p  | type:image |
# =====================================
# == MISCELLANEOUS ==
# --engine, -e=name
#	Specify a specific search engine to use for this search specified in @cxl
#	for this search. If none are specified, then a list of search
#	engines available are echoed.
# --result, -r=result
#	Return only the 'result'th result.
# --format, -F=format
#	Specify the output format. The output format is a string where the
#	relevant information is substituted in afterwards via escape codes:
#	\t = title
#	\u = url
#	\d = snippet/description
#	\m = mime type (or 'no mime')
################################################################################
# Load our flag parser and uri encoder:
@include "./src/arg3.awk"       # Supplies arg3()
@include "./src/uri_encode.awk" # Supplies uri_encode()
################################################################################
BEGIN {
    # Set our argument parsing flags:
    GOOGLE_FLAGS=\
    "filter[f filter]1 " \
    "type[t type]2/^.+$/ " \
    "domain[d domain]3 " \
    "image[image p]4/^$/ " \
    "safety[s safety]5/^.+$/ " \
    "ctype[c ctype]6/^.+$/ " \
    "cdom[C cdom]7/^.+$/ " \
    "isize[i isize]8/^.+$/ " \
    "itype[I itype]9/^.+$/ " \
    "rights[R rights]10/^.+$/ " \
    "mime[m mime]11/^.+$/ " \
    "engine[e engine]12/^[a-zA-Z_0-9]*$/ " \
    "result[r result]13/^([1-9]|10)$/" \
    "format[format F]14/^.+$/ "

    GOOGLE_URI="https://www.googleapis.com/customsearch/v1?"

    # First, split and put all search engine ids in @cxl into array 'cx' in
    # the format 'cx[name] = ID'.
    patsplit(cxl,pairs,/[^ ]+/);
    # Iterate over each pair:
    for ( pair in pairs ) {
        # Split the name=pair into kv[1] and kv[2], then store them
        # appropriately.
        split( pairs[pair] , kv , "=" );
        cx[kv[1]]=kv[2]
        delete kv;
    }
    delete pairs;

    # Set some defaults:
    C_google || (C_google="g(oogle)?")
    command || (command="!")
    print "CGoogle: " C_google >> "/dev/stderr"
}

# Start our google command!
$4 ~ ( "^:[" command "]" C_google "$" ) {trigger_command=1}

(trigger_command == 1) {
    # Assign '$3' to 'channel' so that we can use it later.
    channel = $3;
    $1 = "" ; $2 = "" ; $3 = "" ; $4 = "";

    # Parse our arguments:
    success=arg3(GOOGLE_FLAGS)

    # If it's invalid, complain:
    if ( success == 1 ) {
        print "PRIVMSG " channel " :" flags[0];
        done();
    }

    # If no search terms've been supplied:
    if ( !$0 && !("engine" in flags) ) {
        print "PRIVMSG " channel " :Usage: !g [-p] [-e=engine] [-f filters] search term";
        done();
    }

    # If the 'engine' flag was specified:
    if ( "engine" in flags ) {
        # If the engine flag is empty:
        if ( flags["engine"] ~ /^\s*$/ ) {
            # Print a list of valid engines:
            for ( engine in cx ) {
                engine_list=engine_list engine " "
            }
            print "PRIVMSG " channel " :Valid search engines: " engine_list
            engine_list=""; engine=""; done();
        # If the engine doesn't exist, complain:
        } else if ( !(flags["engine"] in cx) ) {
            print "PRIVMSG " channel " :No such search engine '" flags["engine"] "'. Call '" cmd_plain "g -e' for a list." ; done();
        }
        engine=flags["engine"]
    } else if ( !engine ) {
        engine=cxd
    }

    # If no result number was specified, use '1'
    if ( !("result" in flags) ) { flags["result"]=1 }

    # Iterate over the flags specified:
    for ( flag in flags ) {
        switch (flag) {
            case /^(t|type)$/    : flags["filter"]=(flags["filter"] ",type:" flags["type"])         ; break
            case /^(d|domain)$/  : flags["filter"]=(flags["filter"] ",domain:" flags["domain"])     ; break
            case /^(s|safety)$/  : flags["filter"]=(flags["filter"] ",safety:" flags["safety"])     ; break
            case /^(c|ctype)$/   : flags["filter"]=(flags["filter"] ",ctype:" flags["ctype"]) 	    ; break
            case /^(C|cdom)$/    : flags["filter"]=(flags["filter"] ",cdom:" flags["cdom"])         ; break
            case /^(i|isize)$/   : flags["filter"]=(flags["filter"] ",isize:" flags["isize"])       ; break
            case /^(I|itype)$/   : flags["filter"]=(flags["filter"] ",itype:" flags["itype"])       ; break
            case /^(r|rights)$/  : flags["filter"]=(flags["filter"] ",rights:" flags["rights"])     ; break
            case /^(p|image)$/   : flags["filter"]=(flags["filter"] ",type:image")                  ; break
            case /^(m|mime)$/    : flags["filter"]=(flags["filter"] ",mime:" flags["mime"])         ; break
        }
    }

    # Put all individual patterns into an array 'strs'
    patsplit(flags["filter"],strs,/\/[^\/]+\//)
    # Iterate over the patterns:
    for ( i in strs ) {
        # The first gensub statement escapes all RegEx operators in the current string, and then uses it
        # as the first argument to gsub. The latter gensub argument turns
        # all spaces into ASCII 000s. The net result is that in the filter
        # string, all commas occurring between two slashes are now turned
        # into NULLs.
        gsub(gensub(/[\.\^\$\\\[\]\|\(\)\*\+\?\{\}]/,"\\\\&","G",strs[i]),gensub(/,/,"\000","G",strs[i]),flags["filter"])
    }

    # Now, we parse the actual filter:
    # Turn all escaped commas into ASCII 001s:
    gsub(/\\,/,"\001",flags["filter"]);
    # Remove all trailing and leading commas:
    gsub(/^,/,"",flags["filter"]);
    gsub(/,$/,"",flags["filter"]);
    # Put each filter entry into an array 'filters':
    split(flags["filter"],filters,",");
    # Iterate over each filter:
    for ( filter in filters ) {
        # Turn each ASCII 000 back into a comma:
        gsub("\000",",",filters[filter])
        # Split the filter name and value into keyval[1] and keyval[2] respectively.
        split(filters[filter],keyval,":");
        # Iterate over each of our filters and take appropriate action.
        switch (keyval[1]) {
            case "type": 
                # Check if the filter argument is 'image' or 'url'. If neither, complain.
                switch(keyval[2]) {
                    case "image": searchtype="&searchType=image"; break
                    case "url":   searchtype=""; break
                    default: print "PRIVMSG " channel " :Invalid filter argument for 'type': '" keyval[2] "' (must be 'image' or 'url')"; done();
                } break;
            # Turn the domain's wildcards (? and *) into RegEx patterns.
            case "domain":  gsub(/[\*\?]/,".&",keyval[2]) ; domain=keyval[2] ; break
            case "safety":
                # If the safety is anything other than 'high', 'medium', or 'off', complain:
                if ( keyval[2] !~ /^(high|medium|off)$/ ) {
                    print "PRIVMSG " channel " :Invalid safety setting '" keyval[2] "'. May only be one of 'high', 'medium', or 'off'."; done();
                } safety="&safe=" keyval[2] ; break;
            case "ctype":
                # If the colour type is anything other than 'color', 'gray', 'grey', or 'mono', complain:
                if ( keyval[2] !~ /^(color|grey|gray|mono)$/ ) {
                    print "PRIVMSG " channel " :Invalid colour type setting '" keyval[2] "'. May only be one of 'color', 'gray', 'grey', or 'mono'."; done();
                # Automatically interpolate 'grey' to 'gray'
                } else if ( keyval[2] == "grey" ) { keyval[2]="gray" }
                ctype="&imgColorType=" keyval[2] ; break
            case "cdom":
                # If the colour type is invalid, complain:
                if ( keyval[2] !~ /^(black|blue|brown|gray|grey|green|pink|purple|teal|white|yellow)$/ ) {
                    print "PRIVMSG " channel " :Invalid dominant colour setting '" keyval[2] "'. May only be one of 'black', 'blue', 'brown', 'gray', 'grey', 'green', 'pink', 'purple', 'teal', 'white', or 'yellow'."; done();
                # Interpolate 'grey' to 'gray'
                } else if ( keyval[2] == "grey" ) { keyval[2]="gray" }
                cdom="&imgDominantColor=" keyval[2] ; break
            case "isize":
                # If the size is invalid, complain:
                if ( keyval[2] !~ /^(huge|icon|small|large|medium|xl|xxl|xlarge|xxlarge)$/ ) {
                    print "PRIVMSG " channel " :Invalid size setting '" keyval[2] "'. May only be one of 'huge', 'icon', 'small', 'large', 'medium', 'xl', or 'xxl'."; done();
                } else if ( keyval[2] == "xl" ) { keyval[2] = "xlarge" } else if ( keyval[2] == "xxl" ) { keyval[2] = "xxlarge" }
                isize="&imgSize=" keyval[2] ; break
            case "itype":
                # If the type is invalid, complain:
                if ( keyval[2] !~ /^(clipart|face|lineart|news|photo)$/ ) {
                    print "PRIVMSG " channel " :Invalid type setting '" keyval[2] "'. May only be one of 'clipart', 'face', 'lineart', 'news', or 'photo'."; done();
                }
                itype="&imgType=" keyval[2] ; break
            case "rights":
                # If the rights're invalid, compain:
                if ( keyval[2] !~ /^(cc_)?(publicdomain|attribute|sharealike|noncommercial|nonderived)$/ ) {
                    print "PRIVMSG " channel " :Invalid rights setting '" keyval[2] "'. May only be one of 'cc_publicdomain', 'cc_attribute', 'cc_sharealike', 'cc_noncommercial', or 'cc_nonderived'."; done();
                # If the 'cc_' was omitted, prepend it now:
                } else if ( keyval[2] !~ /^cc_/ ) { keyval[2]="cc_" keyval[2] }
                rights="&rights=" keyval[2] ; break
            case "mime": mime=keyval[2] ; break
            default:
                # This is some sort of bogus filter. Complain.
                print "PRIVMSG " channel " :Bogus filter '" keyval[1] "'. See documentation for a list of valid filters."; done();
                break;
        }
        # Reset keyval.
        delete keyval;
    }
    # == BEGIN DECLARATION OF PROCESS GET_RESULTS ==
    # > "curl 'https://www.googleapis.com/customsearch/v1?key=" google_api "&cx=" cx[engine] safety searchtype ctype cdom isize itype rights \
    # > "&q=" uri_encode($0) "&fields=items(title,snippet,link,mime)&prettyPrint=false' 2>/dev/null | " \
    # Construct our url with all the fields specified in the filters, the appropriate engine, etc.
    #
    # > "sed 's/\\\\\"/\001/g' | grep -Eo '\"(title|link|snippet|mime)\":\"([^\"]+)\"' | " \
    # Turn every escaped quote into ASCII 001s, then use grep to only pull out the appropriate fields.
    #
    # > "sed -Ene 's/^\"(title|link|snippet|mime)\": ?\"([^\"]+)\"$/\\1 \\2/p' | tr '\001' '\"' | " \
    # Use sed to remove the JSON noise and then turn all 001s back into quotes.
    #
    # =? IF SEARCHTYPE IS EMPTY ?=
    # > "paste -d \"\001\" - - - | " \
    # Put each result on the same line delimited by 001s.
    # =? IF SEARCHTYPE IS 'IMAGE' ?=
    # > "paste -d \"\001\" - - - - | " \
    # Put each result on the same line delimited by 001s.
    # The fourth paste is to account for the presence of a 'mime' field.
    # =? IF 'DOMAIN' IS SPECIFIED ?=
    # > "grep -E '\001?link [^\001]*" domain "[^\001]*\001?' | "
    # Only take entries with the given domain name in them.
    # =? IF 'MIME' IS SPECIFIED AND SEARCHTYPE IS 'IMAGE' ?=
    # > "grep -E '\001?mime [^\001]*" mime "[^\001]*\001?'"
    # Only take entries whose mime type corresponds with the one specified.
    # =? ELSE, IF 'MIME' ISN'T SPECIFIED OR SEARCHTYPE IS EMPTY ?=
    # > "cat"
    # Append 'cat' as to deal with the trailing pipe.
    GET_RESULTS=\
    "curl 'https://www.googleapis.com/customsearch/v1?key=" google_api "&cx=" cx[engine] safety searchtype ctype cdom isize itype rights \
    "&q=" uri_encode($0) "&fields=items(title,snippet,link,mime)&prettyPrint=false&filter=1' 2>/dev/null | " \
    "sed 's/\\\\\"/\001/g' | grep -Eo '\"(title|link|snippet|mime)\":\"([^\"]+)\"' | " \
    "sed -Ene 's/^\"(title|link|snippet|mime)\": ?\"([^\"]+)\"$/\\1 \\2/p' | tr '\001' '\"' | "
    if ( !searchtype ) { GET_RESULTS=GET_RESULTS "paste -d \"\001\" - - - | " }
    else 	       { GET_RESULTS=GET_RESULTS "paste -d \"\001\" - - - - | " }
    if ( domain )      { GET_RESULTS=GET_RESULTS "grep -Ea '\001?link [^\001]*" domain "[^\001]*\001?' | " }
    if ( mime && searchtype ) { GET_RESULTS=GET_RESULTS "grep -Ea '\001?mime [^\001]*" mime "[^\001]*\001?'" }
    else { GET_RESULTS=GET_RESULTS "cat" }

    GET_RESULTS | getline result
    # If no results have been found, complain.
    if ( !result ) { print "PRIVMSG " channel " :No results found for query '" $0 "'"; done(); }

    # Save the first result for later:
    first_result=result;

    # If no format was specified, go for the default:
    if ( !("format" in flags) ) { flags["format"]="\x2\\t\xF - \\u [\x2\\m\xF] - \\d" }

    # Iterate over all results:
    do {
        # Increase the result number.
        result_num++
        # If this is the result we were looking for:
        if ( result_num == strtonum(flags["result"]) ) {
            # Parse our result.
            split(result,parts,"\001");
            # Start parsing
            for ( part in parts ) {
                # Extract the key and value:
                key=substr(parts[part],1,index(parts[part]," ")-1)
                value=substr(parts[part],index(parts[part]," ")+1)
                # Switch in the appropriate value.
                switch( key ) {
                    case "title"  : gsub(/\\t/,value,flags["format"]); break;
                    case "link"   : gsub(/\\u/,value,flags["format"]); break;
                    case "snippet": gsub(/(\\n|\.\.\.)/,"",value); gsub(/\\d/,value,flags["format"]); break;
                    case "mime"   : gsub(/\\m/,value,flags["format"]); break;
                }
            }
            # If no mime type was added, add 'no mime' in post:
            gsub(/\\m/,"no mime",flags["format"]);
        }
    } while ( (GET_RESULTS | getline result) > 0 )

    # If the given result was higher than the amount returned, just use the first result.
    if ( strtonum(flags["result"]) > result_num ) {
        # Set the result number to '1':
        flags["result"] = 1;

        # Parse our result.
        split(first_result,parts,"\001");
        # Start parsing
        for ( part in parts ) {
            # Extract the key and value:
            key=substr(parts[part],1,index(parts[part]," ")-1)
            value=substr(parts[part],index(parts[part]," ")+1)
            # Switch in the appropriate value.
            switch( key ) {
                case "title"  : gsub(/\\t/,value,flags["format"]); break;
                case "link"   : gsub(/\\u/,value,flags["format"]); break;
                case "snippet": gsub(/(\\n|\.\.\.)/,"",value) ; gsub(/\\d/,value,flags["format"]); break;
                case "mime"   : gsub(/\\m/,value,flags["format"]); break;
            }
        }
        # If no mime type was added, add 'no mime' in post:
        gsub(/\\m/,"no mime",flags["format"]);
    }

    # Neatly close the process:
    close(GET_RESULTS)

    # Print our output, finally:
    print "PRIVMSG " channel " :[" flags["result"] "/" result_num "] " flags["format"];

    # Reset essential variables:
    filter="";engine="";result_num=0;
    safety="";searchtype="";ctype="";cdom="";
    isize="";itype="";rights="";domain="";
    first_result="";result="";mime="";
    delete parts;key="";value="";
    delete filters;delete strs;

    # Reset "trigger_command" too:
    trigger_command=0;
}
