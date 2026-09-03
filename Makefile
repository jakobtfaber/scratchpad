APP_NAME = Scratchpad
BUNDLE_NAME = $(APP_NAME).app
CONTENTS = $(BUNDLE_NAME)/Contents
MACOS = $(CONTENTS)/MacOS
RESOURCES = $(CONTENTS)/Resources
APPLICATIONS_DIR ?= /Applications
PLIST_NAME = com.jakobtfaber.scratchpad.plist
LAUNCH_AGENTS_DIR = $(HOME)/Library/LaunchAgents

.PHONY: all app install run stop status test clean install-login uninstall-login

all: app

app:
	@mkdir -p $(MACOS) $(RESOURCES)
	swiftc -O -framework Cocoa main.swift -o $(MACOS)/$(APP_NAME)
	@cp Info.plist $(CONTENTS)/Info.plist
	@if [ -f AppIcon.icns ]; then cp AppIcon.icns $(RESOURCES)/AppIcon.icns; fi
	@echo "Built $(BUNDLE_NAME) successfully."

install: app
	@rm -rf $(APPLICATIONS_DIR)/$(BUNDLE_NAME)
	@cp -R $(BUNDLE_NAME) $(APPLICATIONS_DIR)/
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $(APPLICATIONS_DIR)/$(BUNDLE_NAME) 2>/dev/null || true
	@echo "Installed $(BUNDLE_NAME) to $(APPLICATIONS_DIR)/$(BUNDLE_NAME)."

run: install
	@pkill -x $(APP_NAME) 2>/dev/null || pkill -x DesktopNotepad 2>/dev/null || true
	@open $(APPLICATIONS_DIR)/$(BUNDLE_NAME)
	@echo "Launched $(APPLICATIONS_DIR)/$(BUNDLE_NAME)."

stop:
	@pkill -x $(APP_NAME) 2>/dev/null || pkill -x DesktopNotepad 2>/dev/null && echo "Stopped $(APP_NAME)." || echo "$(APP_NAME) is not running."

status:
	@pgrep -l $(APP_NAME) && echo "Status: Running ($(APP_NAME))" || (pgrep -l DesktopNotepad && echo "Status: Running (DesktopNotepad)" || echo "Status: Stopped")

test:
	swift test_suite.swift

clean:
	rm -rf $(BUNDLE_NAME) $(APP_NAME) DesktopNotepad

install-login: install
	@mkdir -p $(LAUNCH_AGENTS_DIR)
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '<plist version="1.0">' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '<dict>' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '    <key>Label</key>' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '    <string>com.jakobtfaber.scratchpad</string>' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '    <key>ProgramArguments</key>' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '    <array>' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '        <string>$(APPLICATIONS_DIR)/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME)</string>' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '    </array>' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '    <key>RunAtLoad</key>' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '    <true/>' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '    <key>KeepAlive</key>' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '    <true/>' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '    <key>StandardErrorPath</key>' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '    <string>/tmp/scratchpad.err</string>' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '</dict>' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo '</plist>' >> $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	launchctl load -w $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo "Installed LaunchAgent at $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)"

uninstall-login:
	@launchctl unload -w $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME) 2>/dev/null || true
	@rm -f $(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)
	@echo "Uninstalled LaunchAgent."
