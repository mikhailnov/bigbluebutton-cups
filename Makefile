install:
	mkdir -p $(DESTDIR)/usr/lib/cups/backends
	install -m0700 cups-backend-copy-raw.sh /usr/lib/cups/backends/bbb-copy-raw
