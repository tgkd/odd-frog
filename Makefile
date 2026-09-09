SIGN     ?= -
APP      := OddFrog
BUILD    := build
BUNDLE   := $(BUILD)/$(APP).app
CONTENTS := $(BUNDLE)/Contents
BIN      := .build/release/$(APP)

.PHONY: build bundle calendar-plugin reminders-plugin run install test clean

build:
	swift build -c release

calendar-plugin:
	swift build -c release --product OddFrogCalendar
	mkdir -p $(BUILD)/plugins/calendar
	cp Plugins/Calendar/plugin.toml $(BUILD)/plugins/calendar/
	cp .build/release/OddFrogCalendar $(BUILD)/plugins/calendar/
	codesign --force --sign "$(SIGN)" $(BUILD)/plugins/calendar/OddFrogCalendar

reminders-plugin:
	swift build -c release --product OddFrogReminders
	mkdir -p $(BUILD)/plugins/reminders
	cp Plugins/Reminders/plugin.toml $(BUILD)/plugins/reminders/
	cp .build/release/OddFrogReminders $(BUILD)/plugins/reminders/
	codesign --force --sign "$(SIGN)" $(BUILD)/plugins/reminders/OddFrogReminders

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(BIN) $(CONTENTS)/MacOS/$(APP)
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	cp Resources/config.example.toml $(CONTENTS)/Resources/
	cp Resources/AppIcon.icns $(CONTENTS)/Resources/
	mkdir -p $(CONTENTS)/Resources/Plugins/calendar
	cp Plugins/Calendar/plugin.toml $(CONTENTS)/Resources/Plugins/calendar/
	cp .build/release/OddFrogCalendar $(CONTENTS)/Resources/Plugins/calendar/
	codesign --force --sign "$(SIGN)" $(CONTENTS)/Resources/Plugins/calendar/OddFrogCalendar
	mkdir -p $(CONTENTS)/Resources/Plugins/reminders
	cp Plugins/Reminders/plugin.toml $(CONTENTS)/Resources/Plugins/reminders/
	cp .build/release/OddFrogReminders $(CONTENTS)/Resources/Plugins/reminders/
	codesign --force --sign "$(SIGN)" $(CONTENTS)/Resources/Plugins/reminders/OddFrogReminders
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
