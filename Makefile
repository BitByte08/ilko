VERSION ?= 1.2.0

.PHONY: dmg run build clean

dmg:
	$(MAKE) -C macos dmg VERSION=$(VERSION)

run:
	$(MAKE) -C macos run

build:
	$(MAKE) -C macos build

clean:
	$(MAKE) -C macos clean
