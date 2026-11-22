SIGN     ?= -
APP      := OddFrog
BUILD    := build
BUNDLE   := $(BUILD)/$(APP).app
CONTENTS := $(BUNDLE)/Contents
BIN      := .build/release/$(APP)
USER_PLUGINS := $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/odd-frog/v2/plugins

.PHONY: build bundle plugins fff run install test clean dev-plugin dev-plugin-remove
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
dev-plugin:
	@test -n "$(ID)" || { echo "Usage: make dev-plugin ID=<bundled plugin id>"; exit 1; }
	@manifest=$$(grep -l '^id = "$(ID)"$$' Plugins/*/plugin.toml | head -n 1); \
	test -n "$$manifest" || { echo "No bundled plugin with id $(ID)."; exit 1; }; \
	swift build --product OddFrogDevProvider && \
	target="$(USER_PLUGINS)/$(ID)" && \
	rm -rf "$$target" && mkdir -p "$$target" && \
	{ echo 'executable = "provider"'; cat "$$manifest"; } > "$$target/plugin.toml" && \
	if [ -d "$$(dirname "$$manifest")/assets" ]; then cp -R "$$(dirname "$$manifest")/assets" "$$target/assets"; fi && \
	cp "$$(swift build --show-bin-path)/OddFrogDevProvider" "$$target/provider" && \
	codesign --force --sign "$(SIGN)" "$$target/provider" && \
	echo "Installed $(ID) to $$target. Enable it in Settings > Plugins, then use Reload Plugins after each rebuild."
dev-plugin-remove:
	@test -n "$(ID)" || { echo "Usage: make dev-plugin-remove ID=<bundled plugin id>"; exit 1; }
	rm -rf "$(USER_PLUGINS)/$(ID)"
