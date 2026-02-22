# Lock Screen Metal GPU Access

## Summary

macOS lock screen (screen saver) Metal GPU access has restrictions
that affect LivingGlass rendering.

## Findings

### What Works
- **Screen saver bundles (`.saver`)** can use Metal when the screen saver
  is running *before* the screen locks (e.g., idle timeout screen saver).
- The `ScreenSaverView` subclass receives `draw(_:)` calls and can use
  Metal command buffers normally during this phase.

### Restrictions
1. **After screen lock**: macOS suspends GPU access for screen saver
   processes. Metal command buffers may fail silently or return errors.
   The screen saver freezes on the last rendered frame.

2. **System-level install required**: For the screen saver to appear on
   the lock screen (not just the pre-lock screen saver), it must be
   installed to `/Library/Screen Savers/` (system-wide), not
   `~/Library/Screen Savers/` (per-user).

3. **WindowServer handoff**: When the lock screen activates, WindowServer
   takes over rendering. Third-party screen savers don't get GPU access
   during actual lock screen display on macOS Sonoma+.

4. **macOS Sonoma+ changes**: Apple introduced a new lock screen
   architecture. The lock screen wallpaper is controlled by System
   Settings and is separate from the screen saver. Screen savers only
   run during the idle phase before lock.

### Practical Impact
- LivingGlass **works as a screen saver** during the idle phase.
- Once the screen locks, it freezes on the last frame (acceptable —
  the lock UI overlays it anyway).
- There is **no supported way** for third-party apps to render
  dynamically on the actual macOS lock screen (Sonoma+).

### Alternatives Considered
- **CGDisplayStream**: Capture-only, cannot write to lock screen.
- **IOSurface sharing**: Would require a system extension (SPI).
- **Login window plugin**: Deprecated in macOS 13+.

## Recommendation

Ship the screen saver as-is. It provides a pleasant idle animation
before lock. The lock screen freeze is expected behavior and consistent
with how all third-party macOS screen savers work on Sonoma+.

Focus effort on the main wallpaper app instead — it provides the
best experience as a persistent desktop background.
