install:
	mkdir -p $(DESTDIR)/usr/lib/cups/backends
	install -m0700 cups-backend-copy-raw.sh /usr/lib/cups/backends/bbb-copy-raw

	mkdir -p $(DESTDIR)/usr/local/bigbluebutton/core/scripts/post_archive
	install -m0755 post-archive_cups-bbb-copy-raw.rb $(DESTDIR)/usr/local/bigbluebutton/core/scripts/post_archive/20-cups-bbb-copy-raw.rb
