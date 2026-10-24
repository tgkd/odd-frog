SIGN     ?= -
APP      := OddFrog
BUILD    := build
BUNDLE   := $(BUILD)/$(APP).app
CONTENTS := $(BUNDLE)/Contents
BIN      := .build/release/$(APP)

.PHONY: build bundle plugins fff run install test clean
build:
	swift build -c release

plugins: build
	.build/release/OddFrogPackage Plugins .build/release $(BUILD)/plugins
	find $(BUILD)/plugins -type f -perm +111 -exec codesign --force --sign "$(SIGN)" {} \;

fff:
	scripts/fetch-fff.sh

bundle: plugins fff
	rm -rf $(BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources $(CONTENTS)/Frameworks
	cp $(BIN) $(CONTENTS)/MacOS/$(APP)
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	cp Resources/config.example.toml Resources/AppIcon.icns $(CONTENTS)/Resources/
	cp -R $(BUILD)/plugins $(CONTENTS)/Resources/Plugins
	cp vendor/fff/libfff_c.dylib $(CONTENTS)/Frameworks/
	printf 'APPL????' > $(CONTENTS)/PkgInfo
	codesign --force --sign "$(SIGN)" --deep $(BUNDLE)
run: bundle
	pkill -x $(APP) || true
	open $(BUNDLE)
install: bundle
	mkdir -p $(HOME)/Applications
	rsync -a --delete $(BUNDLE)/ $(HOME)/Applications/$(APP).app/
test:
	swift test
clean:
	rm -rf .build $(BUILD)
