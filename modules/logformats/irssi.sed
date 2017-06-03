# Irssi Log Formatting for Mohawk. Accepts raw IRC input strings, and outputs irssi-formatted strings.
s/:([^!]+)![^ ]+ +PRIVMSG +[^ ]+ +:ACTION (.+)$/ * \1 \2/ ; t done
s/:([^!]+)![^ ]+ +PRIVMSG +[^ ]+ +:/ <\1> / ; t done
s/:([^!]+)![^ ]+ +NICK +[^ ]+ :?(.+)$/ -!- \1 is now known as \2/ ; t done
s/:([^!]+)!([^ ]+) +JOIN +(.+)$/ -!- \1 [\2] has joined \3/ ; t done
s/:([^!]+)!([^ ]+) +PART +([^ ]+)( *):?(.*)$/ -!- \1 [\2] has left \5\4[\3]/ ; t done
s/:([^!]+)![^ ]+ +KICK +([^ ]+) +([^ ]+) *:?(.*)$/ -!- \3 was kicked from \2 by \1 [\4]/ ; t done
s/:([^!]+)!([^ ]+) +QUIT +[^ ]+ *:?(.*)$/ -!- \1 [\2] has quit [\3]/ ; t done
s/:([^!]+)![^ ]+ +MODE +([^ ]+) +([^ ]+)(.*)$/ -!- mode\/\2 [\3\4] by \1/ ; t done
s/:([^!]+)![^ ]+ +TOPIC +([^ ]+) :(.+)$/ -!- \1 changed the topic of \2 to: \3/ ; t done

# Done label- if appropriate transformations've been done, the branches can just skip to here to prevent too many checks.
:done
