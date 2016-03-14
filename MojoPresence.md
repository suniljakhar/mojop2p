# Introduction #

Mojo presence uses key-value pairs to provide information to other Mojo users about a number of different things.  The values are all strings.  The key value pairs are listed below:

  * **txtvers**
    * The standard TXT Record versioning attribute
  * **zlib**
    * Signifies whether or not the Mojo user supports zlib compression of the XML files over HTTP.  For example, if supported the connecting Mojo user can request zlib compressed versions of the XML files for improved transfer performance.  0 means zlib is not supported.  Non 0 means zlib IS supported.
  * **gzip**
    * gzip works the same as zlib (used for compression on Windows)
  * **passwd**
    * Signifies whether or not the Mojo users library is password protected.  0 means NOT password protected.  Non 0 means the library IS password protected.
  * **LibraryPersistentID**
    * A UUID that identifies the iTunes music library of the Mojo user.  It identifies the iTunes library that is currently being shared.  This UUID is also used to detect a duplicate service over the Internet (XMPP protocol).  For example, if a user is on your local network and an available user in your XMPP roster, the LibraryPersistentID is used to detect the duplicate and Mojo can then display the users presence correctly (available over the local network rather than the Internet).
  * **ShareName**
    * The user specified friendly name for their Mojo share (i.e. “Eric’s Music”).  The broadcasted bonjour name is generally the name of the computer, therefore a friendly name was more desirable for display purposed.  Plus this allows the friendly name to be longer and allows special characters.
  * **NumberOfSongs**
    * The number of songs being shared.  Used for display in the roster window.
  * **stunt**
    * TCP NAT Traversal support, currently at 1.1.  It is used in STUNT signaling.
  * **stun**
    * UDP NAT Traversal support, currently at 1.0.  It is used in STUN signaling.
  * **search**
    * A version number that signifies the Mojo search capabilities, currently at version 1.0.

## Mojo Presence - Bonjour ##

Mojo uses the bonjour protocol to discover other Mojo users and broadcast it’s own service over the local network.  The bonjour service name is “_maestro._tcp.”.  Mojo was originally named Maestro, hence the bonjour service name.  The txt record is a key-value (string-string) pair list.
## Mojo Presence - XMPP ##

Mojo uses the XMPP protocol to manager a roster of other Mojo users for use over the Internet.  The Mojo presence key-value pair information is transferred within an XMPP presence element.  Mojo uses the recommended X namespace for it’s content.
```
	<presence type=”available”>
		<x xmlns=”mojo:x:txtrecord”>
			<txtvers>2</txtvers>
			<zlib>1</zlib>
			<gzip>1</gzip>
			<passwd>1</passwd>
			<LibraryPersistentID>AB658749B9854235</LibraryPersistentID>
			<ShareName>Eric’s Music</ShareName>
			<NumberOfSongs>12154</NumberOfSongs>
			<stunt>1.1</stunt>
			<stun>1.0</stun>
			<search>1.0</search>
		</x>
	</presence>
```