###############################################################################
# YOUTUBE VIDEO SEARCH
###############################################################################
# VAR command
# LOCALVAR googleapikey cachedir dformat C_youtube
# RESPOND PRIVMSG
###############################################################################
# Retrieves YouTube videos specified by search queries. Requires an API key.
# @googleapikey must be the API key to use in requests.
# @cachedir is the directory files will be cached in (usually ./cache/)
# @default_format is a default format to be used.
# YouTube accepts several options:
# --video , -v (default)
#	retrieve information for an individual video
# --list , -l
#	return a list of results rather than info on an individual result
# --ID , -I
#	search for video ID rather than title
# -p=N --page=N
#	show only the Nth page or Nth result.
# -f=N --format="FORMAT"
#	set a different format to be used for the output.
#
# Invalid flags will be ignored.
#
# The format is a string that will be displayed as the output. This string
# may contain several escape sequences, each corresponding with a different
# attribute:
# \t - Video title
# \c - Video uploader
# \C - Amount of comments
# \l - Video length
# \r - Upvote count
# \R - Downvote count
# \v - View count
# \d - Upload date
# \D - Video description
# \u - Video ID (for in URLs)
# Invalid escape sequences are quietly discarded.
#
# Whenever a search is done, the search term is stored to ./cache/yt-search,
# and the results are stored on the second line.
# If the search term is a single '-', or the same string as the last video, the
# last results will be reused instead. This is to prevent consecutive video
# searches using up the API quota.
#
# Requires curl.
#
# Also chimes in and yells which youtube video a link points to.
###############################################################################
# Include the specialised argparse module and uri encoder.
@include "./src/arg3.awk" # Supplies the arg3() function.
@include "./src/uri_encode.awk" # Supplies the uri_encode() function.
###############################################################################
# Create the allowed string:
BEGIN {
    YT_FLAGS= \
    "look_video:[v video]1/^$/ " \
    "get_list:[l list]1/^$/ " \
    "video_id:[I ID]2/^$/ " \
    "page:[p page]3/^[0-9]+$/ " \
    "format:[format f]4/^.+$/ "

    # Set some defaults:
    cachedir || (cachedir="./cache/")
    dformat || (dformat="\002\\t\004 by \002\\c\004 - [\002\\l\004] \002\\r\004↑\002\\R\004↓ \002\\v\004 views, uploaded on \002\\d\004 - http://youtube.com/watch?v=\\u")
    C_youtube || (C_youtube="(yt?|youtube)")
}

################################################################################
# If url[5] is present (i.e. someone posted a link, causing the above block to
# trigger) also run.
$4 ~ ( "^:[" command "]" C_youtube "$" ) {trigger_command=1}

(trigger_command == 1) {
    trigger_command = 0;
    # Reset essential variables:
    results = "";info="";last_term="";search_result="";success=0
    delete fields;delete flags

    # Assign '$3' to 'channel' so that we can use it later.
    channel = $3
    $1 = "" ; $2 = "" ; $3 = "" ; $4 = ""

    # Parse our arguments:
    success=arg3(YT_FLAGS)

    # If it's invalid, complain:
    if ( success == 1 ) {
        print "PRIVMSG " channel " :" flags[0];
        done();
    }

    # If no page has been specified, default to 1:
    if ( !("page" in flags) ) { flags["page"] = 1 }

    # Retrieve the first line from the cache, which is the search term used
    # last.
    getline last_term < (cachedir "/yt-search")

    # If 0 is a single hyphen, OR isn't specified, OR exactly matches the last
    # search term (last-term), use the cache.
    if ( ($0 ~ /^\-$/) || !($0) || ( last_term == $0 ) ) {
        # In the cache file itself, the first line is the search term which we
        # retrieved above. This getline statement retrieves the last JSON
        # result, which is on the second line.
        getline search_result < (cachedir "/yt-search")
        # Neatly close the file.
        close(cachedir "/yt-search")
    # If neither -I or --ID have been specified:
    } else if ( !("video_id" in flags) ) {
        # Now cache the search string:
        print > (cachedir "/yt-search")
        # Else, do not use the cache, but rather retrieve a new list from online.
        # Before we do that, remove all reserved characters from the search string:
        gsub( /[^A-Za-z0-9\-\._~ ]/ , "" )
        # Turn the spaces into %20s.
        gsub( /\s+/ , "%20" )
        # curl the search results from google API, and turn all newlines into
        # NULLs. Then store the result in the cache file.
        GET_SEARCHRESULTS="curl 'https://www.googleapis.com/youtube/v3/search?key=" googleapikey "&part=snippet&q=" uri_encode($0) "&type=video&maxResults=10' 2>/dev/null | " \
        "tr '\\n' ' ' >> " cachedir "/yt-search"

        # Get the search results.
        GET_SEARCHRESULTS | getline search_result

        # Close the search process:
        close(GET_SEARCHRESULTS)
        # Close the file.
        close(cachedir "/yt-search")
    }

    if ( search_result ~ /"totalResults": 0,/ ) {
        # If no results've been found:
        print "PRIVMSG " channel " :No results.";
        done();
    }

    # If the a --video or -v flag or neither has been given, then show a single video rather than a list.
    if ( !("1" in flags[-1]) || (flags[-1]["1"] == "look_video")  ) {
        # We assign a template either from flags["format"], use default_format, or use another default.
        (( "format" in flags) && results = flags["format"]) ||
        (( dformat ) && results = dformat)

        # Next we substitute the escaped letters in our template with the name of the appropriate field:
        gsub( /\\c/ , "\001channelTitle\001" , results )
        gsub( /\\C/ , "\001commentCount\001" , results )
        gsub( /\\D/ , "\001Description\001" , results )
        gsub( /\\R/ , "\001dislikeCount\001" , results )
        gsub( /\\l/ , "\001duration\001" , results )
        gsub( /\\u/ , "\001id\001" , results )
        gsub( /\\r/ , "\001likeCount\001" , results )
        gsub( /\\d/ , "\001publishedAt\001" , results )
        gsub( /\\t/ , "\001title\001" , results )
        gsub( /\\v/ , "\001viewCount\001" , results )
        gsub( /\\./ , " " , results )
        # Each number corresponds to a JSON key in the response:
        # e.g. \t => title => Video title
        # <=== DECLARATION OF PROCESS GET_VIDEO ===>
        # == DECLARATION OF VARIABLE $VIDEO_ID ==
        # =? IF THE --ID FLAG IS NOT SUPPLIED ?=
        # > "VIDEO_ID=$( sed -n '2p' < cache/yt-search | grep -Eo '\"videoId\": \"[^\"]+\"' | " \
        # This command takes the second line from the cache file, and then greps all videoId entries from it.
        #
        # > "sed -Ene '" flags["page"] " s/^\"videoId\": \"(.+)\"$/\1/p' ) ; " \
        # This sed command takes the list of video ids, takes the desired entry (flags["page"]), and extracts only the Video ID from it.
        # =? IF THE --ID FLAG IS SUPPLIED ?=
        # > "VIDEO_ID='" $1 "' ; "
        # Set the video ID to the ID specified.
        # == END DECLARATION OF VARIABLE $VIDEO_ID ==
        # == START RETRIEVING VIDEO INFO ==
        # > "curl 'https://www.googleapis.com/youtube/v3/videos\?key\=" googleapikey "\&part=snippet,statistics,contentDetails\&id\='$VIDEO_ID 2>/dev/null | " \
        # Retrieves the desired video's information from the API.
        #
        # > "sed -Ene 's/^ *\"(id|title|description|channelTitle|viewCount|likeCount|dislikeCount|commentCount|duration|publishedAt)\": \"(.+)\",?$/\1 \2/p' | " \
        # Take the info, and extract the desired fields. Then put them 'field value'.
        #
        # > "sort | uniq | rev | " \
        # Sort the fields, remove duplicates, then reverse all the strings:
        #
        # > "sed -Ee 's/([0-9]{3})/\\1,/g ; s/([0-9]+), /\\1 /' -e '/tAdehsilbup$/ { s/,//g ; y/TZ/  / ; s/000\\.// ; }' -e '/noitarud$/ { s/TP// ; y/HMS/hms/ ; }'" \
        # In the reversed string, put a comma after every third number, remove the commas from publishedAt entries and prettify the duration string.
        #
        # > "rev | tr '\\n' '\\000'"
        # Re-reverse everything, and put every field on one line, delimited by NULLs.
        # <=== END DECLARATION OF PROCESS GET_VIDEO ===>
        ( !("video_id" in flags) ) && (GET_VIDEO_ID="VIDEO_ID=$( sed -n '2p' < cache/yt-search | grep -Eo '\"videoId\": \"[^\"]+\"' | " \
        "sed -Ene '" flags["page"] " s/^\"videoId\": \"(.+)\"$/\\1/p' ) ; ") || (GET_VIDEO_ID="VIDEO_ID='" $1 "' ; ")
        GET_VIDEO=GET_VIDEO_ID "curl 'https://www.googleapis.com/youtube/v3/videos?key=" googleapikey "&part=snippet,statistics,contentDetails&id='$VIDEO_ID 2>/dev/null | " \
        "sed -Ene 's/^ *\"(id|title|description|channelTitle|viewCount|likeCount|dislikeCount|commentCount|duration|publishedAt)\": \"(.*)\",?$/\\1 \\2/p' | " \
        "sort | uniq | rev | sed -Ee '/(tAdehsilbup|eltit|di|eltiTlennahc)$/ !s/([0-9]{3})/\\1,/g ; /tAdehsilbup/ s/^\\s*[0-9]{3}\\.// ; s/([0-9]+), /\\1 /' -e '/tAdehsilbup$/ { s/,//g ; y/TZ/  / ; }' -e '/noitarud$/ { s/TP// ; y/HMS/hms/ ; } ; /eltit$/ s/\\\\(.)/\\1/g' | rev | tr '\\n' '\\000'"

        # Retrieve the fields by running GET_VIDEO.
        GET_VIDEO | getline info
        close(GET_VIDEO)

        # If info is empty- it means no results've been found:
        if ( info ~ /^$/ ) {
            print "PRIVMSG " channel " :No results found.";
            done();
        }
        
        # Next, put each separate field into array 'fields':
        split( info , fields , /\000/ )

        # Now, iterate over the array, and substitute each \001NUMBER with the
        # field itself. Note that everything is offset by 1 so we don't have to
        # deal with double digits.
        for ( field in fields ) {
            gsub("\001" substr(fields[field],1,index(fields[field]," ")-1) "\001" , substr(fields[field],index(fields[field]," ")+1) , results )
        }

        # Next, replace all \004s with \015s.
        gsub( /\004/ , "\x0F" , results )

        # Remove all fields left over:
        gsub( /\001[^\001]+\001/ , "" , results )

    # Else, if the mode is 'L', then generate a list (will ignore template).
    } else if ( flags[-1]["1"] == "get_list" ) {
        # <=== DECLARATION OF PROCESS GET_LIST ===>
        # == DECLARATION OF VARIABLE $RESULT ==
        # > "RESULT=$( sed -n '2p' < " cachedir "/yt-search | gawk '{ gsub( /\\\\\"/ , \"\\001\" ) ; print }' | " \
        # Store the result in $RESULT. The initial sed command retrieves only
        # the second line from the cache file. The first gawk command turns
        # every escaped " into a SOH (ASCII 001)
        #
        # > "grep -Eao '\"title\": \"[^\"]+\",' | gawk '{ " \
        # The grep command retrieves all video titles. Start a new gawk
        # command.
        #
        # gawk> "gsub( /^\"title\": \"/ , sprintf(\" %c\",31) ); " \ 
        # Turn all '"title": "' strings into ASCII 031, which is an mIRC
        # formatting code for underlining strings.
        #
        # gawk> "gsub( /\",$/ , sprintf(\"%c\",15) ); " \
        # Turn the '",' at the end of each line into an ASCII 015, which is an
        # mIRC formatting code for resetting formatting.
        #
        # gawk> "gsub( /\\001/ , \"\\\"\" ); " \
        # Turn all SOHs back into double quotes.
        #
        # gawk> "print; } ); " \
        # Print the result and end our gawk statement.
        # == END DECLARATION OF VARIABLE $RESULT ==
        #
        # == START DECLARATION OF VARIABLE $LINES ==
        # > "LINES=`expr \\( 1 + \\( \\( " flags["page"] " - 1 \\) \\* 5 \\) \\)`,`expr \\( " flags["page"] " \\* 5 \\)`p ;" \
        # Like in date.awk, we divide our results into groups of five called
        # "pages". i.e. page 1 is results 1 to 5. page 2 is results 6 to 10,
        # etc.
        # The lower bound is calculated: (1+((flags["page"]-1)*5))
        # The upper bound is calculated: (flags["page"]*5)
        # The output will look a bit like: 1,5p or 6,10p, which is a sed
        # command saying only these lines need be printed.
        #
        # > "echo -n 'Page [" flags["page"] "/2] ' ; " \
        # This command prints 'Page [pagenumber/totalpages]' onto stdout, which
        # precedes the results.
        #
        # > "echo \"$RESULT\" | sed -n $LINES | tr '\\n' ';'"
        # Here, we take only the desired lines using sed, turn newlines into
        # ';' and then print it.
        # == END DECLARATION OF VARIABLE $LINES ==
        # <=== END DECLARATION OF PROCESS GET_LIST ===>
        GET_LIST="RESULT=$( sed -n '2p' < " cachedir "/yt-search | gawk '{ gsub( /\\\\\"/ , \"\\001\" ) ; print }' | " \
        "grep -Eao '\"title\": \"[^\"]+\",' | gawk '{ " \
            "gsub( /^\"title\": \"/ , sprintf(\" %c\",31) ); " \
            "gsub( /\",$/ , sprintf(\"%c\",15) ); " \
            "gsub( /\\001/ , \"\\\"\" ); " \
            "print; " \
        "}' ); " \
        "LINES=`expr \\( 1 + \\( \\( " flags["page"] " - 1 \\) \\* 5 \\) \\)`,`expr \\( " flags["page"] " \\* 5 \\)`p ;" \
        "echo -n 'Page [" flags["page"] "/2] ' ; " \
        "echo $LINECOUNT >> /dev/stderr ;" \
        "echo \"$RESULT\" | sed -n $LINES | tr '\\n' ';'"

        # Get our result.
        GET_LIST | getline results

        # Close our process
        close(GET_LIST)
    }

    # Print our result.
    print "PRIVMSG " channel " :" results;

    # Reset trigger_command:
    trigger_command=0;

    # Aaand we're done.
    done();
}
