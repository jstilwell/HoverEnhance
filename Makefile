APP_NAME  := HoverEnhance
BUNDLE_ID := com.jessestilwell.HoverEnhance
CONFIG    ?= debug
APP       ?= build/$(APP_NAME).app
# Xcode's toolchain: a swiftly-installed one earlier on PATH may not match the current SDK.
SWIFT     := xcrun swift
# Extra `swift build` flags, such as the architectures of a universal build.
BUILD_FLAGS ?=
# A stable signing identity keeps the Accessibility grant valid across rebuilds; ad-hoc (-) doesn't.
SIGN_ID   ?= $(shell security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ { print $$2; exit }')
SIGN_FLAGS ?=

# Releases are universal, signed with Developer ID and the hardened runtime, and notarized.
RELEASE_APP    := build/release/$(APP_NAME).app
VERSION        := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
RELEASE_ZIP    := build/release/$(APP_NAME)-$(VERSION).zip
DEVELOPER_ID   ?= $(shell security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $$2; exit }')
# Notary credentials in the keychain, saved once with `xcrun notarytool store-credentials HoverEnhance`.
NOTARY_PROFILE ?= HoverEnhance

.PHONY: build app run stop test log clean release-app release

build:
	$(SWIFT) build -c $(CONFIG) $(BUILD_FLAGS)

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$$($(SWIFT) build -c $(CONFIG) $(BUILD_FLAGS) --show-bin-path)/$(APP_NAME)" "$(APP)/Contents/MacOS/"
	cp Resources/Info.plist "$(APP)/Contents/"
	if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(APP)/Contents/Resources/"; fi
	codesign --force $(SIGN_FLAGS) --sign "$(or $(SIGN_ID),-)" "$(APP)"

run: app stop
	open "$(APP)"

test:
	$(SWIFT) test

stop:
	@pkill -x $(APP_NAME) && sleep 0.5 || true

log:
	log stream --level info --predicate 'subsystem == "$(BUNDLE_ID)"'

# The release app, signed for distribution but not yet notarized.
release-app:
	@test -n "$(DEVELOPER_ID)" || { echo "No Developer ID Application certificate in the keychain."; exit 1; }
	$(MAKE) app CONFIG=release APP="$(RELEASE_APP)" BUILD_FLAGS="--arch arm64 --arch x86_64" \
		SIGN_ID="$(DEVELOPER_ID)" SIGN_FLAGS="--options runtime --timestamp"
	codesign --verify --strict --verbose=2 "$(RELEASE_APP)"

# Notarizes and staples the release app, then zips it for download.
release: release-app
	rm -f "$(RELEASE_ZIP)"
	ditto -c -k --keepParent "$(RELEASE_APP)" "$(RELEASE_ZIP)"
	xcrun notarytool submit "$(RELEASE_ZIP)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(RELEASE_APP)"
	rm "$(RELEASE_ZIP)"
	ditto -c -k --keepParent "$(RELEASE_APP)" "$(RELEASE_ZIP)"
	@echo "Ready: $(RELEASE_ZIP)"

clean:
	rm -rf .build build
