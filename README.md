# Mohawk IRC Bot
Mohawk is an IRC bot written in GNU/awk. It supports supports modular
plugin functionality, primitive permission management,
semi-IRCd-agnosticism, custom configuration syntax, runtime configuration
editing and auto-rehashing functionality.

### Dependencies
To run Mohawk, your system must have:
* GNU/awk, any version.
* sed - either FreeBSD sed, or GNU/sed. Some external plugins might require GNU/sed 4.3 or higher (which boasts a 'sandbox mode').
* Any working, reasonable shell (bash, zsh, tcsh, etc.)
* Naturally- coreutils. Stuff such as tr, cut, echo, etc. Tested with both FreeBSD coreutils and GNU coreutils.

### Quickstart
Create an empty configuration file. For example, `mohawkrc`.
Comments can be written using an octotrophe (`#`)
Key-value combinations can be specified as follows:
`identifier value`. An identifier may be a combination of alphanumeric
characters and underscores. The value may be a continuous sequence of single
or double quoted strings, spaces, and identifiers. If an identifier is
placed somewhere in the value declaration, then the contents of that
identifier will be substituted in.
```
name "Paul"
greeting "Hello, " name "! How are you today?"
```
Now, `'name'` would hold `"Paul"`, and `'greeting'` would hold `"Hello, Paul! How
are you today?"`

Mohawk's configuration has three keywords: `channel`, `plugin`, and `end`.
The former two declare a _block_. `end` _closes_ a block. A block is usually
a single, enclosed, isolated collection of variables.
```
channel "#channel_name"
	# Y'know, more values go here.
end

plugin "plugin_name"
	# And values specifying what the plugin should do go here.
end
```
A `'plugin'` is nothing but a GNU/awk process that continually executes a
single file, supplying IRC messages to it. A `'channel'` block usually
contains nothing but a list of plugins that every message this channel
receives should be sent to. For example:
```
plugin "logging"
	# The 'file' variable in plugin blocks indicates the source file.
	file "./modules/logging.awk"
end

channel "#channel_name"
	plugins "logging"
end
```
Now, whenever a message is sent to `#channel_name`, it will be forwarded to
the `'logging'` plugin, which forwards the message to
`./modules/logging.awk`. Note that multiple channels may share the same
plugin block, and know that multiple plugin blocks may use the same file
(yet have two different processes and variables).

For Mohawk to run, at least one channel must be specified- '@'. This
'channel' governs Mohawk's behaviour during private correspondence.

Another special channel exists- '*'. This 'channel's' plugin list will be
used for any channel that doesn't have a block.

Another variable a channel block may have is an "invite policy variable"--
INVITE. The value of this variable dictates if and who may invite Mohawk to
the specified channel (note that specifying this variable for the '*'
channel specifies a "default invite policy").

If set to "0", then nobody may invite Mohawk to this channel- Mohawk must
send a JOIN request.
If set to "1", then anyone may invite Mohawk to this channel with an INVITE.
If set to "2", followed by a list of privileged users, then anyone whose
nick is in this list may invite Mohawk to this channel.

Several variables must be set before Mohawk can run:
```
nick "Mohawk" # The bot's nickname.
user "Tomatohawk" # The bot's username.
server "irc.freenode.net" # The server to connect to.
port "6667" # The port to connect with.
nspass "nickserv_password" # Optional- if set, Mohawk identifies via NickServ with this password.
join "#channel,#list" # Comma-delimited list of channels to join upon connection. Optional.
command "!." # Optional, though many external plugins use it- a list of characters that may be used as command identifiers.
```

Mohawk may now be executed with: `./mohawk.awk mohawkrc`