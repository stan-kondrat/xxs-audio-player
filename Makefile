CC = clang
CFLAGS = -std=c2x -Wall -Wextra -Wno-deprecated-declarations -Wno-unused-parameter
FRAMEWORKS = -framework Cocoa -framework AVFoundation -framework MediaPlayer -framework CoreMedia -framework UniformTypeIdentifiers -framework QuartzCore
TARGET = XXS-Audio-Player
BUILD_DIR = build
APP_BUNDLE = "$(BUILD_DIR)/$(TARGET).app"
ICON_FILE = $(BUILD_DIR)/icons/AppIcon.icns

all: build run

build: $(APP_BUNDLE)

SOURCES = main.m ID3Metadata.m

$(APP_BUNDLE): $(SOURCES) Info.plist $(ICON_FILE)
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	$(CC) $(CFLAGS) $(FRAMEWORKS) -o "$(APP_BUNDLE)/Contents/MacOS/$(TARGET)" $(SOURCES)
	cp Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp $(ICON_FILE) "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"

# ARM64 (Apple Silicon) — macOS 11.0 Big Sur and later
build-arm64: $(ICON_FILE)
	mkdir -p "build-arm64/$(TARGET).app/Contents/MacOS"
	mkdir -p "build-arm64/$(TARGET).app/Contents/Resources"
	$(CC) $(CFLAGS) $(FRAMEWORKS) -arch arm64 \
		-mmacosx-version-min=11.0 \
		-o "build-arm64/$(TARGET).app/Contents/MacOS/$(TARGET)" $(SOURCES)
	cp Info.plist "build-arm64/$(TARGET).app/Contents/Info.plist"
	cp $(ICON_FILE) "build-arm64/$(TARGET).app/Contents/Resources/AppIcon.icns"

# x86_64 (Intel 64-bit) — macOS 10.13 High Sierra and later
build-x86_64: $(ICON_FILE)
	mkdir -p "build-x86_64/$(TARGET).app/Contents/MacOS"
	mkdir -p "build-x86_64/$(TARGET).app/Contents/Resources"
	$(CC) $(CFLAGS) $(FRAMEWORKS) -arch x86_64 \
		-mmacosx-version-min=10.13 \
		-o "build-x86_64/$(TARGET).app/Contents/MacOS/$(TARGET)" $(SOURCES)
	cp Info.plist "build-x86_64/$(TARGET).app/Contents/Info.plist"
	cp $(ICON_FILE) "build-x86_64/$(TARGET).app/Contents/Resources/AppIcon.icns"

# Generate icon from SVG
$(ICON_FILE): icons/icon.svg icons/generate_icon.sh
	cd icons && ./generate_icon.sh icon.svg

clean:
	rm -rf $(BUILD_DIR) build-arm64 build-x86_64

run: $(APP_BUNDLE)
	open "$(APP_BUNDLE)"

.PHONY: all build build-arm64 build-x86_64 clean run
