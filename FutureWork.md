# Work Items #

## Search ##

Mojo already has support for searching.  The underlying HTTP server can accept a search request and respond with the appropriate XML response.  In addition, it supports various advanced search techniques as documented in the HTTP URL syntax.  However, the user interface is not completed.  The interface has been started and is well on its way to being completed.  It can be found in the 4.0 branch.

## Core Data ##

The following need to be moved out of memory and into Core Data:

  * Roster:  This includes the bonjour services and XMPP roster
  * My iTunes library:  Currently Mojo constantly reads and process the XML file.  It would be very handy if Mojo could store that data into a database and create a background task that updates the database appropriately when the iTunes Music Library.xml file changes.  This would result in faster uploads, searching, and graying out of songs.  It would also give Mojo improved memory efficiency with large music libraries.

## User Privacy Management ##

Mojo currently has simplistic control over shared materials, currently limited to items in iTunes.  Moving forward Mojo needs to have more sophisticated privacy controls to allow for greater flexibility.  The privacy controls should extend down to the user level.  For example, the user can share different/specific content with their family rather than their co-workers.  Also, there will be a single separate sharing list for the local network.

## Improved Support for Movie Streaming ##

Mojo currently supports downloading and streaming of movie files (just like any other files in the iTunes library).  However, many movie files place the meta information at the end of the file.  What this means is, the movie can’t be streamed and can’t	start playing until the entire movie has been downloaded.  Mojo should automatically detect this problem and move the meta information to the beginning of the file, allowing streaming automatically regardless of how the file is stored on disk.  There is an existing opensource C project that does this, called QTFastStart.  A new asynchronous HTTP response class should be created to handle this.

## TLS Connection Support ##

Many users will likely want “secure” connections.  The standard for doing this is with SSL/TLS.  However, to achieve such a connection the client is required to have a valid x509 certificate signed by a certificate authority.  This will rarely if ever be the case.  Mojo can automatically generate a self-signed certificate that can then be used.  This will require UI changes and application tweaks to implement this well.

## Mojo Extensions ##

The strength of Mojo is it provides a roster of users and a way to create direct peer-to-peer connections with those users.  It also provides a basis for file transfer once the connection is made.  Mojo does not and should not be limited to the current music sharing features that are currently implemented.  Mojo has the potential to be so much more.  Some areas that Mojo would easily extend to are photos, movies, and generic files.  Moving in this direction will require separating the file lists into individual xml files (i.e. music.xml, photos.xml, movies.xml).

## Windows ##

Windows is not the favorite operating system of the Mojo founders, therefore the Windows version needs some motivated passionate Windows developers to show it the love it deserves.