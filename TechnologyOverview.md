## Roster and user management ##

Mojo allows sharing over the local network and the Internet.  Bonjour is used to discover other Mojo users on the local network.  XMPP is used to create and manage a roster of approved Mojo users.  These two protocols together provide the architecture for Mojo’s roster and presence updates.

(Links)

## Connectivity ##

Direct TCP connections are made between Mojo users on the local network.  Mojo uses NAT Traversal to create direct peer-to-peer connections between users over the Internet.

(Links)

## File Transfer ##

Once the connection is made, Mojo uses HTTP to request and receive files from the other user.  It generally starts by requesting a XML file which lists files available from the other user.  For example, the music.xml file would return all the music files available.

(Links)