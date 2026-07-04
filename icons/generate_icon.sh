#!/bin/bash
# Generate macOS .icns from SVG using only built-in macOS tools
# Requires: sips (for SVG rendering) and iconutil (for .icns creation)

set -e

SVG_FILE="${1:-icon.svg}"
OUTPUT_DIR="${2:-../build/icons}"

if [ ! -f "$SVG_FILE" ]; then
    echo "Error: SVG file not found: $SVG_FILE"
    echo "Usage: $0 <svg-file> [output-dir]"
    exit 1
fi

echo "Generating icon from $SVG_FILE..."

# Create output directory
mkdir -p "$OUTPUT_DIR"

ICONSET_DIR="$OUTPUT_DIR/AppIcon.iconset"
TEMP_PNG="$OUTPUT_DIR/icon_1024.png"

# Clean up old files
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# Generate PNG at highest resolution first using sips
echo "Converting SVG to PNG with transparency..."
sips -s format png -z 1024 1024 "$SVG_FILE" --out "$TEMP_PNG" > /dev/null 2>&1

# Generate all required sizes using sips
for size in 16 32 64 128 256 512 1024; do
    echo "Generating ${size}x${size}..."
    sips -z $size $size "$TEMP_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" > /dev/null 2>&1

    # Also create @2x versions for retina
    if [ $size -le 512 ]; then
        size2x=$((size * 2))
        sips -z $size2x $size2x "$TEMP_PNG" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" > /dev/null 2>&1
    fi
done

# Create .icns file
echo "Creating AppIcon.icns..."
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_DIR/AppIcon.icns"

echo "✓ AppIcon.icns created successfully"
echo "  Location: $OUTPUT_DIR/AppIcon.icns"
echo "  Size: $(du -h $OUTPUT_DIR/AppIcon.icns | cut -f1)"
