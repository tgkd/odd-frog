SIGN     ?= -
APP      := OddFrog
BUILD    := build
BUNDLE   := $(BUILD)/$(APP).app
CONTENTS := $(BUNDLE)/Contents
BIN      := .build/release/$(APP)

.PHONY: build bundle run install test clean

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(BIN) $(CONTENTS)/MacOS/$(APP)
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	cp Resources/config.example.toml $(CONTENTS)/Resources/
	cp Resources/AppIcon.icns $(CONTENTS)/Resources/
	printf 'APPL????' > $(CONTENTS)/PkgInfo
	codesign --force --sign "$(SIGN)" --deep $(BUNDLE)

run: bundle
	pkill -x $(APP) || true
	while pgrep -x $(APP) >/dev/null; do sleep 0.1; done
	open $(BUNDLE)

install: bundle
	mkdir -p $(HOME)/Applications
	rsync -a --delete $(BUNDLE)/ $(HOME)/Applications/$(APP).app/

test:
	swift test

clean:
	rm -rf .build $(BUILD)
