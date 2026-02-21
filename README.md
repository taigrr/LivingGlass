# LivingGlass

Conway's Game of Life as a dynamic macOS desktop wallpaper.

## Features

- Runs on **all monitors** simultaneously
- **Multi-color palette** — 16 vibrant colors, cells inherit colors from neighbors with occasional mutations
- **Dying cell animation** — cells vibrate and shrink as they fade to darkness
- **Self-sustaining** — injects new patterns when population drops too low
- **Menu bar app** — no dock icon, just a 🧬 in the menu bar
- Reset or quit from the menu bar

## Build & Run

```bash
chmod +x build.sh
./build.sh
open "build/LivingGlass.app"
```

Requires macOS 14+ and Xcode Command Line Tools (`xcode-select --install`).

## Install

```bash
cp -r "build/LivingGlass.app" /Applications/
```

To auto-start: System Settings → General → Login Items → add LivingGlass.

## Controls

- **🧬 menu bar icon** → Reset / Quit
