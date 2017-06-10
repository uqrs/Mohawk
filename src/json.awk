################################################################################
# Mohawk JSON Tools
################################################################################
# Bullshit JSON deserialisation tools- expect lots of weird timey-wimey
# witchcraft. Lots of it.
#
# One function gets "borrowed" from the main source to aid us in deserialising
# escaped characters and such- is_escaped(). This function simply returns
# either a '1' or a '0' based on whether the character is in position
# 'indice' of 'string' is escaped or not. This function acts recursively- if
# the backslash preceding the given character is also escaped, and the one
# before that isn't, then a '0' will be returned, etc.
################################################################################
function is_escaped (string,indice) {
   if ((substr(string,indice-1,1) == "\\") && !(is_escaped(string,indice-1)))
   { return 1 } else { return 0 }
}
################################################################################
# Unlike other convoluted-as-heck JSON toolboxes, Mohawk's has only one
# significant, usable function: json(). This function accepts a single input
# string, parses it, and stores the result in an array.
#
# Since GNU/awk cannot "assign" arrays (or create references to them, for
# that matter) by default, we must make json() recursive, as passing arrays
# as formal arguments is the one way I know of to do this. Fuck you, awk.
#
# 'root' is the array that the parsed JSON will be deserialised into.
# Top-level callers will want to make this the array they want to store
# anything into. json() will call itself to properly deal with nested JSON
# objects/arrays.
################################################################################
function json ( input , root , recursing ) {
   # Current_pos is used to track our position through the string. Once it's
   # bigger than "end", we're done parsing. CUR_T tracks our current
   # object/array.
   if ( !recursing ) {
      current_pos=1; end=length(input); current_dec="{"; key="";
      stacklevel=0; current_char="";
      # What to do with this string/number/bool very much depends whether we
      # are: In an object, or an array. If, in an object, we're dealing with a
      # key or value.
      #
      # Not to mention- with declaration of a key/valua, certain
      # expectations must be met. If in an object, and this is a key,
      # we expect the next non-whitespace character to be a ':'. If it
      # is not, we must complain. If in an object and this is a value,
      # the next non-whitespace character must be either a ',' or a
      # '}'. If in an array, the next non-whitespace character must
      # always be a ',' or a ']'. To deal with this (appropriately), I
      # propose a 'expect' variable-- a pattern that input will be
      # matched against, with the premise of it throwing an error if
      # it does not match (which would imply faulty JSON).
      #       Context            Expect
      # Object, whatever=key   => /[\s:]/
      # Object, whatever=value => /[\s,}]/
      # Array                  => /[\s,\]]/
      # At the very beginning, we expect the opening object.
      expect="[ {]";
      # To deduct whether a given object is a valey or a key, after any and
      # all objects, "otype" is incremented by one.
      #
      # IF "otype" is ODD (otype%2==1) then the current string/number is a
      # KEY. If "otype" is EVEN (otype%2==0) then the current
      # string/number/object is a VALUE.
      otype=0;
   }

   # Keep looping until we reach the end of the string:
   do {
      # Our current character will dictate what in the world we'll do:
      current_char=substr(input,current_pos,1);

      # Is it anything we expect?
      if ( current_char !~ expect ) {
         print "[!] Faulty JSON near #" current_pos ". Expected " expect ", got " current_char ". Bailing out.";
         return 2;
      }

      # What do we do?
      switch(current_char) {
         #######################################################################
         # '{' - Generate a new object.
         #######################################################################
         case "{":
            # Force into an array:
            if ( current_dec == "{" ) { root[key][1]; split("",root[key]); }
            else { root[length(root)+1][1]; split("",root[length(root)]); }
            # Go to next position:
            current_pos++;

            # If we're at stacklevel 0 (meaning we're dealing with a global
            # object), silently skip. Next expectation: a string, or the end
            # of this object(?).
            if ( stacklevel++ == 0 ) { stack[stacklevel]="{"; expect="[\" }]" }
            # Else, set the current declaration to an object, and start assigning stuff to this key.
            else {
               # Whenever dealing with objects, set otype back to 0:
               otype=0;
               # Save the current declaration. Increase the stack level.
               stack[stacklevel-1]=current_dec;
               # Set the new declaration.
               current_dec="{";
               # Expect: immediate close object, whitespace, or a string.
               expect="[ \"}]";
               # Call self, passing whichever is appropriate:
               if ( stack[stacklevel-1] == "{" ) { json( input , root[key] , 1 ) }
               else { json( input , root[length(root)] , 1 ) }
               # Restore our declaration.
               current_dec=stack[--stacklevel]
            } break;
         #######################################################################
         # '[' - Generate a new array.
         #######################################################################
         case "[":
            # Force into an array:
            if ( current_dec == "{" ) { root[key][1]; split("",root[key]); }
            else { root[length(root)+1][1]; split("",root[length(root)]); }
            # Go to next position:
            current_pos++;

            # If we're at stacklevel 0 (meaning we're dealing with a global object), silently skip...
            if ( stacklevel++ == 0 ) { stack[stacklevel]="[" ; current_pos++ ; expect="[\" \\]]" }
            # Else, set the current declaration to an array and start assigning stuff to this key.
            else {
               # Save the current declaration. Increase the stack level.
               stack[stacklevel-1]=current_dec;
               # Set our new declaration.
               current_dec="[";
               # Expect: new object, new array, strings, numbers, anything-
               expect="[ 0-9eE\\-\\.\\+tfn\"\\[\\]{}]";
               # Call self, supplying whatever's appropriate.
               if ( stack[stacklevel-1] == "{" ) { json( input , root[key] , 1 ) }
               else { json( input , root[length(root)] , 1 ) }
               # Restore our declaration.
               current_dec=stack[--stacklevel]
            } break;
         #######################################################################
         # '"' - Parse either a key or a value string.
         #######################################################################
         case "\"":
            # If we're dealing with a string:
            # Keep looking for closing quotes:
            len=current_pos+1;
            do {
               oldlen=len;
               len+=index(substr(input,len+1),"\"");
               # If the no unescaped double quote has been found, complain:
               if ( len==oldlen ) { return 1; }
               # If one has been found, quit:
            } while ( is_escaped(substr(input,look_after),len) )

            # What're we declaring?
            if ( current_dec=="{" ) {
               # If it's an object, fuss about keys/values:
               # If this a key, or a value?
               if ( (++otype%2)==1 ) {
                  # It's a key. Assign it and offset our position.
                  key=substr(input,current_pos+1,len-current_pos-1);
                  current_pos+=length(key)+2
                  # Next expectation: whitespace, or colons.
                  expect="[ \\:]";
               } else {
                  # It's a value. Assign it and offset our position.
                  root[key]=substr(input,current_pos+1,len-current_pos-1);
                  current_pos+=length(root[key])+2
                  # Next expectation: a comma, or an object end:
                  expect="[ ,}]";
               }
            } else {
               # If it's an array, use standard numerical indices.
               root[length(root)+1]=substr(input,current_pos+1,len-current_pos-1);
               current_pos+=length(root[length(root)])+2
               # Next expectation: a comma, or an array end:
               expect="[ ,\\]]";
            } break;
         #######################################################################
         # Some sort of number, true, false, or null.
         #######################################################################
         case /[0-9\-\+Ee\.tfn]/:
            # Assign! What're we declaring?
            if ( current_dec=="{" ) {
               # Is it a key, or a value?
               if ( (++otype%2)==1 ) {
                  # It's a key. We can't possibly have that.
                  print "[!] Faulty JSON near #" current_pos ": attempt to use number as a key. Bailing.";
                  return 3;
               } else {
                  # If it's a value, like it should be, assign it:
                  root[key]=gensub(/^([0-9\-\+Ee\.]+|true|false|null).+$/,"\\1","G",substr(input,current_pos));
                  # Skip ahead:
                  current_pos+=length(root[key]);
                  # Next expectation: comma or object end:
                  expect="[ ,}]";
               }
            # Else, if we're in an array:
            } else {
               # If it's an array, use standard numerical indices:
               root[length(root)+1]=gensub(/^([0-9\-\+Ee\.]+|true|false|null).+$/,"\\1","G",substr(input,current_pos));
               current_pos+=length(root[length(root)]);
               # Next expectation: comma or array end:
               expect="[ ,\\]]";
            } break;
         #######################################################################
         # Whitespace- skip ahead.
         #######################################################################
         case " ": current_pos++; break;
         #######################################################################
         # Colons and commas- set new expectations.
         #######################################################################
         case ":": expect="[ \"0-9tfn\\[{]"; current_pos++; break;
         case ",": expect="[ \"0-9tfn\\[{]"; current_pos++; break;
         case "}": expect="[ ,}\\]]"; current_pos++; otype=0; return 0; break;
         case "]": expect="[ ,}\\]]"; current_pos++; otype=0; return 0; break;
         default:  current_pos++; break;
      }
   } while ( current_pos <= end )
}