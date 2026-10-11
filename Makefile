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

# Releases are universal and signed with Developer ID and the hardened runtime; bin/build-release.sh
# notarizes them and publishes the update.
RELEASE_APP    := build/release/$(APP_NAME).app
DEVELOPER_ID   ?= $(shell security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $$2; exit }')

.PHONY: build app run stop test log clean release-app release

build:
	$(SWIFT) build -c $(CONFIG) $(BUILD_FLAGS)

SPARKLE := $(APP)/Contents/Frameworks/Sparkle.framework

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources" "$(APP)/Contents/Frameworks"
	BIN="$$($(SWIFT) build -c $(CONFIG) $(BUILD_FLAGS) --show-bin-path)" && \
		cp "$$BIN/$(APP_NAME)" "$(APP)/Contents/MacOS/" && \
		ditto "$$BIN/Sparkle.framework" "$(SPARKLE)"
	# Sparkle's XPC services are only for sandboxed apps.
	rm -rf "$(SPARKLE)/XPCServices" "$(SPARKLE)/Versions/B/XPCServices"
	cp Resources/Info.plist "$(APP)/Contents/"
	find Resources -maxdepth 1 -type f ! -name Info.plist -exec cp {} "$(APP)/Contents/Resources/" \;
	# Inside out, as Sparkle's documentation describes: its helpers, the framework, then the app.
	for code in Versions/B/Autoupdate Versions/B/Updater.app .; do \
		codesign --force $(SIGN_FLAGS) --sign "$(or $(SIGN_ID),-)" "$(SPARKLE)/$$code" || exit 1; \
	done
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

# A notarized DMG and a signed appcast; see bin/build-release.sh, which can also publish them.
release:
	./bin/build-release.sh

clean:
	rm -rf .build build
