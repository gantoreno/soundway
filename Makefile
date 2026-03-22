SWIFT ?= swift
PREFIX ?= /usr/local
BIN_DIR ?= $(PREFIX)/bin
BUILD_DIR ?= .build/release
TARGET ?= soundway
INSTALL ?= install

.PHONY: build test release run devices status install uninstall clean

build:
	$(SWIFT) build

test:
	$(SWIFT) test

release:
	$(SWIFT) build -c release

run:
	$(SWIFT) run $(TARGET)

devices:
	$(SWIFT) run $(TARGET) devices

status:
	$(SWIFT) run $(TARGET) status

install: release
	$(INSTALL) -d "$(BIN_DIR)"
	$(INSTALL) -m 755 "$(BUILD_DIR)/$(TARGET)" "$(BIN_DIR)/$(TARGET)"

uninstall:
	rm -f "$(BIN_DIR)/$(TARGET)"

clean:
	$(SWIFT) package clean
