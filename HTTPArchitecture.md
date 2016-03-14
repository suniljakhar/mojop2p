# Introduction #

Mojo uses the CocoaHTTPServer as the basis for it’s embedded HTTP server.  Using this opensource server allows Mojo to support digest access authentication, SSL/TLS, and POST uploads.


## URL Syntax ##

There are 4 types of requests in Mojo.

  1. **Path = “/”**
    * Request for Mojo service information.  The response will be the txt record data.  Only used in direct URL connection (not really used).

  1. **Path = “/xml” or “/xml.zlib” or “/xml.gzip”**
    * Request for the music library xml file

  1. **Path = “/search?”**
    * There are two supported parameters
      1. “num” – The maximum number of results to return.  If num is not specified, the default is 100
      1. “q” – The query. Queries are case insensitive.  The following fields are searched:
        * Artist Name
        * Album Name
        * Song Name
        * Genre
        * Composer
    * Mojo uses a syntax similar to Google.  Examples:
      * query (John Mayer)
      * query (”John Mayer” wonderland)
      * query (artist:john -mayer)
      * query (+john -mayer)
      * query (artist:+”john mayer” artist:-trio)

  1. **Path = “/{Track ID}/{Persistent Track ID}”**
    * Mojo doesn’t really want to send requests over the network for straight files because it poses a security risk.  For example, someone could send a simple HTTP GET command for /Users/eric/Documents/DeepDarkSecrets.txt.  If the HTTP server just served up any file that was requested, this would actually work.  What Mojo could do to get around this problem would be to make sure the requested file is in the iTunes library.  But this would require looping through every song in the library and performing a string compare until the file is found.  In addition to being slow, there is another problem.  File paths change. So if the user slightly changes the song name, track number, album, artist name, etc... the file path will change.  A better solution is to send the persistent track ID. Then Mojo can lookup the current path in the iTunes library.  There's one small annoyance about this solution too. The iTunes Music Library XML file is contains a hash table of all the tracks keyed on the Track ID.  So, Mojo can't directly lookup the track from the persistent track ID.  We need the track ID to directly lookup the track.  So the final solution is to pass both the track ID and the persistent track ID of the song Mojo is looking for.  Mojo can use both to get the file path for the correct song, and 99.9% of the time the lookup can be done in 1 step.