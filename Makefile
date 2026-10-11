APP_NAME  := HoverEnhance
BUNDLE_ID := com.jessestilwell.HoverEnhance
CONFIG    ?= debug
APP       := build/$(APP_NAME).app
# Xcode's toolchain: a swiftly-installed one earlier on PATH may not match the current SDK.
SWIFT     := xcrun swift
# A stable signing identity keeps the Accessibility grant valid across rebuilds; ad-hoc (-) doesn't.
SIGN_ID   ?= $(shell security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ { print $$2; exit }')

.PHONY: build app run stop log clean

build:
	$(SWIFT) build -c $(CONFIG)

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp "$$($(SWIFT) build -c $(CONFIG) --show-bin-path)/$(APP_NAME)" "$(APP)/Contents/MacOS/"
	cp Resources/Info.plist "$(APP)/Contents/"
	codesign --force --sign "$(or $(SIGN_ID),-)" "$(APP)"

run: app stop
	open "$(APP)"

stop:
	@pkill -x $(APP_NAME) && sleep 0.5 || true

log:
	log stream --level info --predicate 'subsystem == "$(BUNDLE_ID)"'

clean:
	rm -rf .build build
