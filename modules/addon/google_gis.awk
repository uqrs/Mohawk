################################################################################
# GOOGLE IMAGE SEARCH ADDON
################################################################################
# LOCALVAR C_gis
################################################################################
BEGIN {C_gis || (C_gis="(gis|image)")}
################################################################################
# Adds but a shortcut for google image search.
$4 ~ ( ":[" command "]" C_gis "$" ) {
    # Make our command look like a regular search command.
    $4 = ":g"
    # Set the search type to image:
    searchtype="&searchType=image"
    # Trigger a command:
    trigger_command=1;
}
