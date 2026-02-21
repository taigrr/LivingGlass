#!/bin/bash
set -e

APP_NAME="LivingGlass"
BUNDLE_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

echo "Building LivingGlass..."

# Clean
rm -rf build/

# Create .app bundle structure
mkdir -p "${MACOS_DIR}"

# Compile
swiftc \
    -O \
    -o "${MACOS_DIR}/LivingGlass" \
    -framework AppKit \
    -framework QuartzCore \
    Sources/GameEngine.swift \
    Sources/GameOfLifeView.swift \
    Sources/AppDelegate.swift \
    Sources/main.swift

# Copy Info.plist
cp Info.plist "${CONTENTS_DIR}/Info.plist"

# Generate .icns from iconset if iconutil is available
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
mkdir -p "${RESOURCES_DIR}"
if command -v iconutil &>/dev/null && [ -d icon.iconset ]; then
    iconutil -c icns icon.iconset -o "${RESOURCES_DIR}/AppIcon.icns"
    echo "App icon bundled."
elif [ -d icon.iconset ]; then
    # Fallback: just copy the iconset for manual conversion
    cp -r icon.iconset "${RESOURCES_DIR}/"
    echo "Warning: iconutil not found. Icon iconset copied but not converted."
fi

echo "Built: ${BUNDLE_DIR}"
echo ""
echo "To run:  open \"${BUNDLE_DIR}\""
echo "To install: cp -r \"${BUNDLE_DIR}\" /Applications/"
echo ""
echo "To auto-start on login:"
echo "  1. Open System Settings > General > Login Items"
echo "  2. Add 'LivingGlass' under 'Open at Login'"
