# translation-server-cli
CLI for managing zotero-translation-server
```
./zts.sh <action>
Available actions:
      usage   This text

      init    Ensure the zotero-translation-server is set up

      start   Run the zotero-translation-server
      stop    Stop the zotero-translation-server
      restart Restart the zotero-translation-server
      force-start     Run the zotero-translation-server, even if one seems to be running
      force-stop      Stop the zotero-translation-server or delete PID file
      force-restart   Restart the zotero-translation-server (force-start/force-stop)
      auto-restart    Restart the zotero-translation-server when code is changed (implies force-restart)
      status  Check whether zotero-translation-server is running

      translate <URI> Scrape <URI> for bibliographic data
```
