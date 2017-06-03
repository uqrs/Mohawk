# SCP SHORTCUT
(tolower($0) ~ /!scp-[0-9]+/) || (tolower($4) ~ /^:scp-[0-9]+/) {
    match(tolower($0),/!?(scp\-[0-9]+)/,arr);
    $4 = ":g"
    engine="scp"
    for ( i=6;i<=NF;i++ ) {
        $i="";
    }
    $5 = arr[1]; trigger_command=1;
}