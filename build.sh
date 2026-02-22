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

# Compile Metal shaders
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
mkdir -p "${RESOURCES_DIR}"
echo "Compiling Metal shaders..."
xcrun -sdk macosx metal -c Sources/Shaders.metal -o build/Shaders.air
xcrun -sdk macosx metallib build/Shaders.air -o "${RESOURCES_DIR}/default.metallib"
rm -f build/Shaders.air

# Compile Swift
swiftc \
    -O \
    -o "${MACOS_DIR}/LivingGlass" \
    -framework AppKit \
    -framework Metal \
    -framework MetalKit \
    -framework SwiftUI \
    Sources/GameEngine.swift \
    Sources/MetalRenderer.swift \
    Sources/GameOfLifeView.swift \
    Sources/Preferences.swift \
    Sources/AppDelegate.swift \
    Sources/main.swift

# Copy Info.plist
cp Info.plist "${CONTENTS_DIR}/Info.plist"

# Generate .icns from iconset if iconutil is available
# Copy wallpaper fallback image
cp Resources/caviar_bg.png "${RESOURCES_DIR}/caviar_bg.png"

if command -v iconutil &>/dev/null && [ -d icon.iconset ]; then
    iconutil -c icns icon.iconset -o "${RESOURCES_DIR}/AppIcon.icns"
    echo "App icon bundled."
elif [ -d icon.iconset ]; then
    # Fallback: just copy the iconset for manual conversion
    cp -r icon.iconset "${RESOURCES_DIR}/"
    echo "Warning: iconutil not found. Icon iconset copied but not converted."
fi

echo "Built: ${BUNDLE_DIR}"

# Build screen saver
echo ""
echo "Building LivingGlass Screen Saver..."

SAVER_DIR="build/LivingGlass.saver"
SAVER_CONTENTS="${SAVER_DIR}/Contents"
SAVER_MACOS="${SAVER_CONTENTS}/MacOS"
SAVER_RESOURCES="${SAVER_CONTENTS}/Resources"
mkdir -p "${SAVER_MACOS}" "${SAVER_RESOURCES}"

# Compile screen saver bundle (shared sources + screen saver entry point)
swiftc \
    -O \
    -o "${SAVER_MACOS}/LivingGlass" \
    -framework AppKit \
    -framework Metal \
    -framework MetalKit \
    -framework ScreenSaver \
    -emit-library \
    -module-name LivingGlass \
    Sources/GameEngine.swift \
    Sources/MetalRenderer.swift \
    Sources/Preferences.swift \
    Sources/GameOfLifeView.swift \
    ScreenSaver/LivingGlassView.swift

# Copy resources
cp ScreenSaver/Info.plist "${SAVER_CONTENTS}/Info.plist"
cp "${RESOURCES_DIR}/default.metallib" "${SAVER_RESOURCES}/default.metallib"

echo "Built: ${SAVER_DIR}"
echo ""
echo "=== Install ==="
echo ""
echo "Wallpaper app:"
echo "  open \"${BUNDLE_DIR}\""
echo "  cp -r \"${BUNDLE_DIR}\" /Applications/"
echo ""
echo "Screen saver (lock screen):"
echo "  open \"${SAVER_DIR}\""
echo "  # or: cp -r \"${SAVER_DIR}\" ~/Library/Screen\\ Savers/"
echo "  # Then: System Settings → Screen Saver → select LivingGlass"
echo ""
echo "Auto-start wallpaper on login:"
echo "  System Settings → General → Login Items → add LivingGlass"
