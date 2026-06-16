APP_NAME := NotiShift
BUNDLE_ID := com.fthux.NotiShift
BUILD_DIR := build
MODULE_CACHE_DIR := $(BUILD_DIR)/ModuleCache
DIST_DIR := dist
APP_DIR := $(DIST_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
SWIFT_SOURCES := $(shell find NotiShift -name '*.swift' | sort)
SDK_TARGET := arm64-apple-macos11.0

.PHONY: all build package clean run verify

all: build package

build:
	mkdir -p $(BUILD_DIR) $(MODULE_CACHE_DIR) $(MACOS_DIR) $(RESOURCES_DIR)
	cp NotiShift/Resources/Info.plist $(CONTENTS_DIR)/Info.plist
	swiftc $(SWIFT_SOURCES) \
		-o $(MACOS_DIR)/$(APP_NAME) \
		-O \
		-parse-as-library \
		-target $(SDK_TARGET) \
		-module-cache-path $(MODULE_CACHE_DIR) \
		-Xcc -fmodules-cache-path=$(MODULE_CACHE_DIR) \
		-framework AppKit \
		-framework ApplicationServices \
		-framework ServiceManagement \
		-framework UserNotifications
	codesign --force --deep --sign - --entitlements NotiShift/Resources/NotiShift.entitlements $(APP_DIR)

package: build
	cd $(DIST_DIR) && tar -czf $(APP_NAME).app.tar.gz $(APP_NAME).app
	shasum -a 256 $(DIST_DIR)/$(APP_NAME).app.tar.gz

verify:
	codesign -dv --verbose=4 $(APP_DIR)
	spctl -a -vv $(APP_DIR) || true

run: build
	open $(APP_DIR)

clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR)
