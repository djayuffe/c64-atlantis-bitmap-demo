ACME ?= acme
VICE ?= x64sc

SOURCE := src/atlantis_bitmap_demo.s
BUILD_DIR := build
PROGRAM := $(BUILD_DIR)/atlantis-bitmap-demo.prg
AUDIT_PROGRAM := $(BUILD_DIR)/atlantis-bitmap-demo.audit.prg
VERSION ?= 1.0.0
DIST_DIR := dist
RELEASE_ARCHIVE := $(DIST_DIR)/atlantis-bitmap-demo-v$(VERSION).zip

.PHONY: build audit release run clean

build:
	mkdir -p $(BUILD_DIR)
	$(ACME) -f cbm --strict-segments -o $(PROGRAM) $(SOURCE)

audit: build
	$(ACME) -f cbm --strict-segments -o $(AUDIT_PROGRAM) $(SOURCE)
	cmp $(PROGRAM) $(AUDIT_PROGRAM)

release: build
	mkdir -p $(DIST_DIR)
	zip -j -FS $(RELEASE_ARCHIVE) $(PROGRAM) RELEASE_NOTES.md

run: build
	$(VICE) -autostartprgmode 1 -autostart $(PROGRAM)

clean:
	rm -rf $(BUILD_DIR)
