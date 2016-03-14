What users know of as Mojo is actually separated into two separate processes.  One process is the normal UI application that is displayed in the dock.  The second process is the “Mojo Helper” which runs independently of the main Mojo UI application and is displayed in the system tray.  The reason Mojo is architecture this way is because users’ affinity to close applications running in the dock.  The real power of Mojo relies on the server continuing to run in the background, making the user’s library available.  This also has the added benefit of keeping a small memory footprint for the Helper application which ideally runs non-stop.