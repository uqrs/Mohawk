################################################################################
# GOOGLE SEARCH ENGINE MAPPING
################################################################################
# LOCALVAR cxl_map
################################################################################
# Allows mapping google search engines specified in 'cx_list' to commands.
# If the command is mapped to an engine
################################################################################
BEGIN {
    # Split up 'cxl_map' into array '_cxm' where the key is a command, and the
    # value is the search engine's name:
    patsplit(cxl_map,pairs,/[^ ]+/);
    # Iterate over each pair:
    for ( pair in pairs ) {
        # Split the name=pair into kv[1] and kv[2]:
        split( pairs[pair] , kv , "=" );
        cxm[kv[1]]=kv[2]
        # 'cxml' is a list of all added commands:
        cxml=cxml kv[1] "|"
        delete kv;
    }
    # Enclose cxml in parentheses so it looks like a pattern:
    cxml="(" substr(cxml,1,length(cxml)-1) ")(is)?"
    delete pairs;
}
################################################################################
#
################################################################################
$4 ~ ( "^:[" command "]" cxml "$" ) {
    # Remove the leading colon and command operator:
    sub(/^\s*:./,"",$4);
    # If the command ends in 'is', then it's an image search request:
    img=gsub(/is$/,"",$4);
    engine=cxm[$4]
    # Make our command look like a google search command:
    $4 = ":g"
    # If it's an image search request, set the search type to image.
    if ( img ) { searchtype="&searchType=image" }
    # Trigger command too:
    trigger_command=1;
}