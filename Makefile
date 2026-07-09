APP_NAME := RawSend
CONFIGURATION ?= release
APP_VERSION ?= 1.0.1
BUNDLE_ID ?= com.rawsend.app
CODESIGN_IDENTITY ?= -
PKG_SIGN_IDENTITY ?=
NATIVE_ARCH := $(shell uname -m)
ARCH ?= $(NATIVE_ARCH)

BUILD_DIR := .build/$(CONFIGURATION)
BINARY := $(BUILD_DIR)/$(APP_NAME)
APP_BUILD_DIR := .build/app
APP_BUNDLE := $(APP_BUILD_DIR)/$(APP_NAME).app
DIST_DIR := .build/dist
PKG_DIR := .build/packages
ARCH_BUILD_DIR := .build/$(ARCH)-apple-macosx/$(CONFIGURATION)
ARCH_BINARY := $(ARCH_BUILD_DIR)/$(APP_NAME)
ARCH_APP_BUNDLE := $(DIST_DIR)/$(ARCH)/$(APP_NAME).app
CHECK_BUILD_DIR := .build/checks
CODEX_E2E_BINARY := $(CHECK_BUILD_DIR)/RawSendCodexE2E
PERFORMANCE_CHECK_BINARY := $(CHECK_BUILD_DIR)/RawSendPerformanceChecks
CONTENTS_DIR := $(APP_BUNDLE)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
INSTALL_DIR ?= /Applications

.PHONY: build check performance-check codex-check app app-arch package-arch release install run clean

PERFORMANCE_CHECK_SOURCES := \
	Sources/Models/HeaderLine.swift \
	Sources/Models/HTTPRequest.swift \
	Sources/Models/HTTPResponse.swift \
	Sources/Models/HistoryItem.swift \
	Sources/Models/Environment.swift \
	Sources/Core/Localization.swift \
	Sources/Core/PerformanceLogStore.swift \
	Sources/Core/HeaderInspector.swift \
	Sources/Core/DiffEngine.swift \
	Sources/Core/TextLineIndex.swift \
	Sources/Core/HTTPMessageRanges.swift \
	Sources/Core/JSONSyntaxHighlighter.swift \
	Sources/Core/TextHighlightPlan.swift \
	Sources/Core/TextLineRanges.swift \
	Sources/Models/SearchMatch.swift \
	Sources/Models/RiskHighlight.swift \
	Checks/RawSendPerformanceChecks.swift

CODEX_E2E_SOURCES := \
	Sources/Models/HeaderLine.swift \
	Sources/Models/RiskHighlight.swift \
	Sources/Models/CodexRunResult.swift \
	Sources/Models/HTTPRequest.swift \
	Sources/Models/Environment.swift \
	Sources/Core/Localization.swift \
	Sources/Core/HeaderInspector.swift \
	Sources/Core/CodexPrompt.swift \
	Sources/Core/CodexService.swift \
	Checks/RawSendCodexE2E.swift

build:
	swift build -c $(CONFIGURATION)

check:
	swift test
	$(MAKE) performance-check

performance-check:
	mkdir -p "$(CHECK_BUILD_DIR)"
	swiftc $(PERFORMANCE_CHECK_SOURCES) -o "$(PERFORMANCE_CHECK_BINARY)"
	"$(PERFORMANCE_CHECK_BINARY)"

codex-check:
	mkdir -p "$(CHECK_BUILD_DIR)"
	swiftc $(CODEX_E2E_SOURCES) -o "$(CODEX_E2E_BINARY)"
	"$(CODEX_E2E_BINARY)"

app: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	cp "$(BINARY)" "$(MACOS_DIR)/$(APP_NAME)"
	chmod +x "$(MACOS_DIR)/$(APP_NAME)"
	cp "AppIcon.icns" "$(RESOURCES_DIR)/AppIcon.icns"
	{ \
		echo '<?xml version="1.0" encoding="UTF-8"?>'; \
		echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'; \
		echo '<plist version="1.0">'; \
		echo '<dict>'; \
		echo '  <key>CFBundleDevelopmentRegion</key>'; \
		echo '  <string>en</string>'; \
		echo '  <key>CFBundleExecutable</key>'; \
		echo '  <string>$(APP_NAME)</string>'; \
		echo '  <key>CFBundleIconFile</key>'; \
		echo '  <string>AppIcon.icns</string>'; \
		echo '  <key>CFBundleIdentifier</key>'; \
		echo '  <string>$(BUNDLE_ID)</string>'; \
		echo '  <key>CFBundleInfoDictionaryVersion</key>'; \
		echo '  <string>6.0</string>'; \
		echo '  <key>CFBundleName</key>'; \
		echo '  <string>$(APP_NAME)</string>'; \
		echo '  <key>CFBundlePackageType</key>'; \
		echo '  <string>APPL</string>'; \
		echo '  <key>CFBundleShortVersionString</key>'; \
		echo '  <string>$(APP_VERSION)</string>'; \
		echo '  <key>CFBundleVersion</key>'; \
		echo '  <string>$(APP_VERSION)</string>'; \
		echo '  <key>LSApplicationCategoryType</key>'; \
		echo '  <string>public.app-category.developer-tools</string>'; \
		echo '  <key>LSMinimumSystemVersion</key>'; \
		echo '  <string>14.0</string>'; \
		echo '  <key>NSAppTransportSecurity</key>'; \
		echo '  <dict>'; \
		echo '    <key>NSAllowsArbitraryLoads</key>'; \
		echo '    <true/>'; \
		echo '  </dict>'; \
		echo '  <key>NSHighResolutionCapable</key>'; \
		echo '  <true/>'; \
		echo '</dict>'; \
		echo '</plist>'; \
	} > "$(CONTENTS_DIR)/Info.plist"
	codesign --force --deep --sign "$(CODESIGN_IDENTITY)" "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

app-arch:
	swift build -c $(CONFIGURATION) --arch $(ARCH)
	rm -rf "$(ARCH_APP_BUNDLE)"
	mkdir -p "$(ARCH_APP_BUNDLE)/Contents/MacOS" "$(ARCH_APP_BUNDLE)/Contents/Resources"
	cp "$(ARCH_BINARY)" "$(ARCH_APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	chmod +x "$(ARCH_APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp "AppIcon.icns" "$(ARCH_APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	{ \
		echo '<?xml version="1.0" encoding="UTF-8"?>'; \
		echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'; \
		echo '<plist version="1.0">'; \
		echo '<dict>'; \
		echo '  <key>CFBundleDevelopmentRegion</key>'; \
		echo '  <string>en</string>'; \
		echo '  <key>CFBundleExecutable</key>'; \
		echo '  <string>$(APP_NAME)</string>'; \
		echo '  <key>CFBundleIconFile</key>'; \
		echo '  <string>AppIcon.icns</string>'; \
		echo '  <key>CFBundleIdentifier</key>'; \
		echo '  <string>$(BUNDLE_ID)</string>'; \
		echo '  <key>CFBundleInfoDictionaryVersion</key>'; \
		echo '  <string>6.0</string>'; \
		echo '  <key>CFBundleName</key>'; \
		echo '  <string>$(APP_NAME)</string>'; \
		echo '  <key>CFBundlePackageType</key>'; \
		echo '  <string>APPL</string>'; \
		echo '  <key>CFBundleShortVersionString</key>'; \
		echo '  <string>$(APP_VERSION)</string>'; \
		echo '  <key>CFBundleVersion</key>'; \
		echo '  <string>$(APP_VERSION)</string>'; \
		echo '  <key>LSApplicationCategoryType</key>'; \
		echo '  <string>public.app-category.developer-tools</string>'; \
		echo '  <key>LSMinimumSystemVersion</key>'; \
		echo '  <string>14.0</string>'; \
		echo '  <key>NSAppTransportSecurity</key>'; \
		echo '  <dict>'; \
		echo '    <key>NSAllowsArbitraryLoads</key>'; \
		echo '    <true/>'; \
		echo '  </dict>'; \
		echo '  <key>NSHighResolutionCapable</key>'; \
		echo '  <true/>'; \
		echo '</dict>'; \
		echo '</plist>'; \
	} > "$(ARCH_APP_BUNDLE)/Contents/Info.plist"
	codesign --force --deep --sign "$(CODESIGN_IDENTITY)" "$(ARCH_APP_BUNDLE)"
	@echo "Built $(ARCH_APP_BUNDLE)"

package-arch: app-arch
	mkdir -p "$(PKG_DIR)"
	if [ -n "$(PKG_SIGN_IDENTITY)" ]; then \
		productbuild --component "$(ARCH_APP_BUNDLE)" /Applications --sign "$(PKG_SIGN_IDENTITY)" "$(PKG_DIR)/$(APP_NAME)-$(APP_VERSION)-macos-$(ARCH).pkg"; \
	else \
		productbuild --component "$(ARCH_APP_BUNDLE)" /Applications "$(PKG_DIR)/$(APP_NAME)-$(APP_VERSION)-macos-$(ARCH).pkg"; \
	fi
	@echo "Packaged $(PKG_DIR)/$(APP_NAME)-$(APP_VERSION)-macos-$(ARCH).pkg"

release:
	$(MAKE) package-arch ARCH=arm64
	$(MAKE) package-arch ARCH=x86_64
	@echo "Release packages are in $(PKG_DIR)"

install: app
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	ditto "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed $(INSTALL_DIR)/$(APP_NAME).app"

run: app
	open "$(APP_BUNDLE)"

clean:
	rm -rf .build
