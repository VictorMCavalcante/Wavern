# Wavern — Design Spec

**Date:** 2026-09-02
**App name:** Wavern (macOS menu bar per-app volume mixer)
**Bundle prefix:** com.wavern
**Scope:** New project from scratch. Visual design (frosted glass), album art, volume persistence, Chrome tab integration. Lightweight — minimal CPU/memory footprint.

---

## 0. Project Structure (new project)

```
wavern/
├── project.yml
├── Sources/
│   ├── Wavern/                  ← main app target
│   │   ├── WavernApp.swift
│   │   ├── AudioProcess.swift
│   │   ├── AudioProcessController.swift
│   │   ├── CoreAudioUtils.swift
│   │   ├── ProcessTap.swift
│   │   ├── LoginItem.swift
│   │   ├── NowPlaying.swift
│   │   ├── MenuView.swift
│   │   ├── MarqueeText.swift
│   │   ├── WaveformView.swift
│   │   ├── VisualEffectBackground.swift
│   │   ├── BrowserTabStore.swift
│   │   ├── BrowserBridgeInstaller.swift
│   │   ├── Info.plist
│   │   └── Wavern.entitlements
│   ├── WavernBrowserBridge/     ← CLI native messaging host
│   │   └── main.swift
│   └── BrowserExtension/        ← Chrome extension (bundled as resource)
│       ├── manifest.json
│       └── background.js
└── docs/
```

**Starting point:** Port the working Core Audio + process tap engine from Voulum (open source, MIT). All new UI and features built on top.

---

## 1. Visual Design

### Philosophy
Lightweight-first: no background work when menu closed. All animations paused/stopped when menu closes. NSVisualEffectView is GPU-composited by the OS — cheaper than flat colors on Apple Silicon.

### Background / Material

`NSViewRepresentable` wrapping `NSVisualEffectView` with `.popover` material and `.behindWindow` blending. Applied as `.background(VisualEffectBackground())` on the root `VStack`. Panel window set to `backgroundColor = .clear, isOpaque = false` in AppDelegate so the vibrancy shows through.

### Menu dimensions

Width: **340px**. Height: dynamic, grows with number of playing apps.

### Menu bar icon

- Idle (nothing playing): `speaker.wave.2.fill` (static SF Symbol)
- Active (≥1 app playing): `waveform` with `.symbolEffect(.variableColor.iterative.reversing)`

Icon updates only when `controller.playing.isEmpty` changes — no polling cost.

### Header

None. No "Playing Audio" label. Context is clear from menu bar placement.

### Row layout (340px wide)

```
[art 40×40] [title/subtitle marquee · waveform] [jump] [mute] [────slider────] [pct]
            ↑ app icon badge 16×16 overlaid
              bottom-right corner of art
```

- **Art area (40×40):** `RoundedRectangle(cornerRadius: 8)`. Album art when available (Spotify/Music). Fallback: app icon 28×28 centered in 40×40 `.quaternary` fill.
- **App icon badge:** 16×16 app icon at bottom-right of art when artwork is shown. 1pt white stroke, 1pt shadow.
- **Waveform indicator:** `WaveformView(isAnimating:)` — three bars, `TimelineView(.animation(paused: !isAnimating))`. Paused when muted or idle. Canvas-based, no hidden layers.
- **Slider:** `.tint(.accentColor)`, `.controlSize(.small)`.
- **Mute button:** `speaker.slash.fill` in `.red` when muted.
- **Hover:** `onHover` → `.background(Color(.quaternaryLabelColor).opacity(0.3))`. `.contentShape(Rectangle())` for full-row hit testing.
- **Volume % label:** `.caption.monospacedDigit()`, 38pt right-aligned. Shows "muted" in `.secondary`.

### Row dividers

1px `Divider()` with `.leading` padding of 52pt (clears the art column).

### Empty state

Speaker slash icon + "Nothing is playing" in `.secondary`. Centered, `padding(.vertical, 20)`.

### Footer

Launch at login toggle + Quit button. `padding(.vertical, 6)`.

---

## 2. Album Art

### NowPlaying model

```swift
struct NowPlaying: Equatable {
    let title: String
    let artist: String
    let album: String?
    let isPlaying: Bool
    var artworkData: Data?        // Apple Music: raw bytes via AppleScript descriptor
    var artworkURLString: String? // Spotify: URL string, downloaded via URLSession
}
```

### Fetch strategy

- **Apple Music:** Separate AppleScript `get data of artwork 1 of current track` → `descriptor.data`. Runs on `scriptQueue` (already off main).
- **Spotify:** `get artwork url of current track` appended to metadata script → URL string → `URLSession.shared.dataTask` download. Fires once per new track.

### Cache (in AudioProcessController)

```swift
private var artworkCache: [String: NSImage] = [:]  // key: "\(artist)∙\(title)"
@Published private(set) var artworkImages: [AudioObjectID: NSImage] = [:]
```

Cache checked before fetch. Evicted when track changes or process disappears. `NSImage` creation from `Data` is cheap on Apple Silicon (hardware JPEG/PNG decode).

---

## 3. Volume Persistence

`UserDefaults.standard`:

```
wavern.vol.<bundleID>    → Float  (0.0–2.0)
wavern.muted.<bundleID>  → Bool
```

**Save:** in `setVolume(_:for:)` and `toggleMute(_:)` when `process.resolvedBundleID != nil`.

**Restore:** in `reload()`, for each newly seen process, read UserDefaults and pre-populate `volumes[id]` / `muted`. Tap still created lazily — stored gain applied on first interaction.

---

## 4. Browser Tab Integration

### Architecture

```
Chrome Extension (JS, service worker)
  → chrome.tabs.query({audible: true})  [no polling cost on browser side]
  → Native Messaging (stdin/stdout, 4-byte LE length + JSON)
    → WavernBrowserBridge (Swift CLI)
      → atomic write ~/Library/Application Support/Wavern/browser-tabs.json
        → Wavern reads on 1s poll (only while menu open)
```

**Lightness:** WavernBrowserBridge is a minimal Swift process — no framework dependencies beyond Foundation. Only alive while Chrome extension is connected. Bridge process CPU: effectively 0 (blocks on stdin read).

### Chrome Extension (Manifest V3)

Location in bundle: `Wavern.app/Contents/Resources/BrowserExtension/`

`manifest.json`: MV3, permissions `["tabs", "nativeMessaging"]`, service worker `background.js`, deterministic `key` field for stable extension ID.

`background.js`:
- Connects to native host `com.wavern.browserbridge`
- `chrome.tabs.query({audible: true})` every 2s + on `tabs.onUpdated`/`tabs.onRemoved` events
- Posts `{tabs: [{title, url, favIconUrl, audible}]}` to host

### WavernBrowserBridge (Swift CLI target)

- Reads native messaging frames: 4-byte LE uint32 length + UTF-8 JSON body
- Adds `timestamp: TimeInterval` field
- Atomic write to `~/Library/Application Support/Wavern/browser-tabs.json`
- Exits when stdin closes (Chrome disconnects); writes `{tabs:[], timestamp:…}` on exit

### Native Messaging Host Registration (BrowserBridgeInstaller)

At launch, Wavern writes `com.wavern.browserbridge.json` to:
```
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/
~/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/
~/Library/Application Support/Arc/NativeMessagingHosts/
~/Library/Application Support/Microsoft Edge/NativeMessagingHosts/
```

Bridge path: `Wavern.app/Contents/MacOS/WavernBrowserBridge`. Skip if file already exists and path matches.

**Extension ID:** Stable because `manifest.json` contains a pre-generated `key` (RSA public key DER base64). ID derived once during setup, hardcoded in `BrowserBridgeInstaller`.

### Wavern Integration

`BrowserTabStore` (`@MainActor ObservableObject`):
- `@Published var audibleTabs: [BrowserTab]`
- `refresh()` reads JSON file, updates tabs, tracks `lastUpdated`
- `isConnected: Bool` — `lastUpdated` within 5s
- Called from `AudioProcessController.reload()` on existing 1s poll (menu-open only)

`AudioProcess.chromiumBrowserName: String?` — maps bundle IDs to browser names (Chrome, Arc, Brave, Edge).

Row display when Chromium + connected:
- Primary: audible tab title
- Subtitle: browser name
- Icon: favicon (if available) + browser icon badge

Row display when Chromium + not connected:
- "Install browser extension for tab names →" button → onboarding sheet

Onboarding sheet: 3 steps — open `chrome://extensions`, enable developer mode, load unpacked (copy path button).

---

## Architecture Summary

| Component | File | Responsibility |
|-----------|------|----------------|
| App entry | `WavernApp.swift` | MenuBarExtra scene, AppDelegate, animated icon |
| Audio engine | `ProcessTap.swift`, `CoreAudioUtils.swift` | Core Audio process taps, gain application |
| Process model | `AudioProcess.swift` | Process metadata, icon, `chromiumBrowserName` |
| Controller | `AudioProcessController.swift` | Enumeration, volumes, persistence, artwork, browser tabs |
| Now playing | `NowPlaying.swift`, `NowPlayingService.swift` | Metadata + artwork via AppleScript |
| UI root | `MenuView.swift` | Row list, empty state, footer, onboarding sheet |
| Art/wave | `WaveformView.swift`, `VisualEffectBackground.swift` | Reusable UI components |
| Browser | `BrowserTabStore.swift`, `BrowserBridgeInstaller.swift` | Tab data + host registration |
| Bridge CLI | `WavernBrowserBridge/main.swift` | Native messaging stdio relay |
| Extension | `BrowserExtension/` | Chrome extension JS |

---

## Out of Scope

- Firefox / Safari tab integration
- Per-tab volume (requires virtual audio driver)
- Notarization / Developer ID
- Album art for VLC
- Settings window (everything in footer)
