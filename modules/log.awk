################################################################################
# Mohawk - Logging
################################################################################
# LOCALVAR log_map log_dir form_dir
# VAR SED_PATH STDBUF_PATH PREFIX
# LOCALISE YES
# RESPOND PRIVMSG NOTICE JOIN PART KICK TOPIC MODE QUIT NICK
################################################################################
# Implements logging facilities for Mohawk. It maintains and logs the
# activity of one or more IRC channels. The manner in which this plugin is
# implemented makes it so that only one instance of this plugin needs to be
# running: one instance can manage as many channels as possibly required.
#
# This plugin requires only one variable: log_map. log_map is a
# space-separated list of strings in the following format:
# channel,logfile,logformat,timestamp
# Where: `channel` is the name of the channel to be logged. `logfile` is the
# name of the file located in log_dir where the logs should be saved to.
# `logformat` points to a log format file. `timestamp` will be supplied to
# strftime for use as the timestamp.
#
# 'logformat' may either be a full path to a format file, or the name (sans
# extension) to a .sed file located in log_form.
################################################################################
BEGIN {
    # Don't fuss about case.
    IGNORECASE=1;

    # Set the defaults for log_dir:
    log_form || (log_form="modules/logformats/")
    log_dir || (log_dir="log/")

    # Secure both log_form and log_dir:
    gsub(/'/,"'\\''",log_form);
    gsub(/'/,"'\\''",log_dir);

    # Begin by parsing the log_map variable.
    # Split it into lines:
    split(log_map,map_entries," ");

    # For each line, split every entry and allocate it them in log_tree
    # accordingly:
    for ( line in map_entries ) {
        split(map_entries[line],line_parts,",");
        channel=tolower(line_parts[1]);
        log_tree[channel]["logfile"]=gensub(/'/,"'\\''","G",line_parts[2]); #"
        log_tree[channel]["logformat"]=gensub(/'/,"'\\''","G",line_parts[3]); #"
        log_tree[channel]["timestamp"]=gensub(/'/,"'\\''","G",line_parts[4]); #"
    }

    # Clear up certain variables.
    delete map_entries; channel=""; 

    # Verify all logformats exist. If they don't, throw an error, and refuse
    # to log for the given channel.
    for ( channel in log_tree ) {
        # Save two temporary variables so that we may easily call close() later.
        full=(log_tree[channel]["logformat"])
        form=(log_form log_tree[channel]["logformat"] ".sed")
        # Treat the contents of 'logformat' as the name of a file in
        # log_form. See if such a file exists:
        if ( (getline _ < form ) >= 0 ) {
            log_tree[channel]["logformat"]=form;
            print "[@] Found log format file '" form "' for channel " channel >> "/dev/stderr";        
        } else if (getline _ < full ) {
            log_tree[channel]["logformat"]=full;
            print "[@] Found log format file '" full "' for channel " channel >> "/dev/stderr";
        } else {
            print "[!] Failed to found log format '" full "'. Not logging for " channel >> "/dev/stderr";
            delete log_tree[channel];
        }; close(full); close(form);

        # Generate a continues process that takes all input, prepends a timestamp,
        # and then appends it to the appropriate log file:
        log_tree[channel]["proc"]=\
        SED_PATH " -unrf '" log_tree[channel]["logformat"] "' " \
        "-re 's/^/'$(date '+" log_tree[channel]["timestamp"] "')'/p' " \
        ">> '" log_dir log_tree[channel]["logfile"] "'"

        # Show a success message:
        print "[@] Channel '" channel "' now logs to '" log_tree[channel]["logfile"] "' using '" log_tree[channel]["logformat"] "'" >> "/dev/stderr"
    }
}

################################################################################
# Temporarily assign the channel, raise an error if it doesn't exist.
{
    channel=gensub(/^:/,"","G",tolower($3));
    if ( !(channel in log_tree) ) {
        print "[!] No log entry exists for channel '" channel "'" >> "/dev/stderr";
        done();
    }
}

################################################################################
# Actual Logging
################################################################################
# Here, every message is handled appropriately. These first few are rather
# straightforward.
$2 ~ /PRIVMSG/ { print $0 | log_tree[channel]["proc"]; done(); }
$2 ~ /NOTICE/ { print $0 | log_tree[channel]["proc"]; done(); }
$2 ~ /JOIN/ { print $0 | log_tree[channel]["proc"]; done(); }
$2 ~ /PART/ { print $0 | log_tree[channel]["proc"]; done(); }
$2 ~ /KICK/ { print $0 | log_tree[channel]["proc"]; done(); }
$2 ~ /TOPIC/ { print $0 | log_tree[channel]["proc"]; done(); }
$2 ~ /MODE/ { print $0 | log_tree[channel]["proc"]; done(); }
################################################################################
# Note: this plugin has the LOCALISE directive set. As such, they have $3 set
# to the channel.
$2 ~ /QUIT/ { print $0 | log_tree[channel]["proc"]; done(); }
$2 ~ /NICK/ { print $0 | log_tree[channel]["proc"]; done(); }

################################################################################
# Cleanup Procedure
################################################################################
# When closing up, the logging plugin does nothing but close all previously
# opened processes.
END {
    for ( channel in log_tree ) { close(log_tree[channel]["proc"]) }
}