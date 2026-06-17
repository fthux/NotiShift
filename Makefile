APP_DISPLAY_NAME := Noti Shift
EXECUTABLE_NAME := NotiShift
BUNDLE_ID := com.fthux.NotiShift
BUILD_DIR := build
MODULE_CACHE_DIR := $(BUILD_DIR)/ModuleCache
DIST_DIR := dist
APP_DIR := $(DIST_DIR)/$(APP_DISPLAY_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
SWIFT_SOURCES := $(shell find NotiShift -name '*.swift' | sort)
DEPLOYMENT_TARGET := 11.0
ARCHS := arm64 x86_64

.PHONY: all build package clean run verify

all: build package

build:
	rm -rf "$(APP_DIR)"
	mkdir -p "$(BUILD_DIR)" "$(MODULE_CACHE_DIR)" "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	cp NotiShift/Resources/Info.plist "$(CONTENTS_DIR)/Info.plist"
	cp NotiShift/Resources/NotiShift.icns "$(RESOURCES_DIR)/"
	cp -R NotiShift/Resources/*.lproj "$(RESOURCES_DIR)/"
	$(foreach arch,$(ARCHS), \
		mkdir -p "$(BUILD_DIR)/$(arch)" "$(MODULE_CACHE_DIR)/$(arch)"; \
		swiftc $(SWIFT_SOURCES) \
			-o "$(BUILD_DIR)/$(arch)/$(EXECUTABLE_NAME)" \
			-O \
			-parse-as-library \
			-target $(arch)-apple-macos$(DEPLOYMENT_TARGET) \
			-module-cache-path "$(MODULE_CACHE_DIR)/$(arch)" \
			-Xcc -fmodules-cache-path="$(MODULE_CACHE_DIR)/$(arch)" \
			-framework AppKit \
			-framework ApplicationServices \
			-framework ServiceManagement \
			-framework UserNotifications; \
	)
	lipo -create $(foreach arch,$(ARCHS),"$(BUILD_DIR)/$(arch)/$(EXECUTABLE_NAME)") -output "$(MACOS_DIR)/$(EXECUTABLE_NAME)"
	codesign --force --deep --sign - --entitlements NotiShift/Resources/NotiShift.entitlements "$(APP_DIR)"

package: build
	cd "$(DIST_DIR)" && tar -czf "$(APP_DISPLAY_NAME).app.tar.gz" "$(APP_DISPLAY_NAME).app"
	shasum -a 256 "$(DIST_DIR)/$(APP_DISPLAY_NAME).app.tar.gz"

verify:
	lipo -archs "$(MACOS_DIR)/$(EXECUTABLE_NAME)"
	codesign -dv --verbose=4 "$(APP_DIR)"
	spctl -a -vv "$(APP_DIR)" || true

run: build
	open "$(APP_DIR)"

clean:
	rm -rf "$(BUILD_DIR)" "$(DIST_DIR)"
