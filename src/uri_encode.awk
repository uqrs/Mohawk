function uri_encode ( input ) {
    ############################################################################
    # Encodes a URI by substituting reserved characters
    ############################################################################
    gsub(/ /,"%20",input);
    gsub(/!/,"%21",input);
    gsub(/#/,"%23",input);
    gsub(/\$/,"%24",input);
    gsub(/&/,"%26",input);
    gsub(/'/,"%27",input);
    gsub(/\(/,"%28",input);
    gsub(/\)/,"%29",input);
    gsub(/\*/,"%2A",input);
    gsub(/\+/,"%2B",input);
    gsub(/,/,"%2C",input);
    gsub(/\//,"%2F",input);
    gsub(/:/,"%3A",input);
    gsub(/;/,"%3B",input);
    gsub(/=/,"%3D",input);
    gsub(/\?/,"%3F",input);
    gsub(/@/,"%40",input);
    gsub(/\[/,"%5B",input);
    gsub(/\]/,"%5D",input);

    return input;
}