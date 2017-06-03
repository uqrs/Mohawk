tolower($0) ~ ( /(https?:\/\/)?(www\.)?youtu(be(\.[A-Za-z]{2,3}){1,3}\/watch\?v=|\.be\/)[A-Za-z\-_0-9]+/ ) {
    # If the message contains a youtube link, store the ID in url[5]
    match( $0 , /(https?:\/\/)?(www\.)?youtu(be(\.[A-Za-z]{2,3}){1,3}\/watch\?v=|\.be\/)([A-Za-z\-_0-9]+)/ , url )
    # Now kind of like, alter the message so it looks like a genuine youtube
    # command:
    $4 = ":" substr(command,1,1) "yt"
    $5 = "--ID"
    $6 = gensub(/^\s*\-/,"\\\\-","G",url[5])
    delete url;
    # Ssssh, nobody'll know.
    trigger_command=1;
}