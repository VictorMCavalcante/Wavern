# Wavern Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Wavern — a macOS menu bar per-app volume mixer — from scratch. Frosted glass UI, album art, volume persistence, Chrome tab enrichment.

**Architecture:** Port the Core Audio process tap engine from Voulum (MIT, at `/Users/victor/Documents/estudos/voulum-main/`). Build all new UI and features on top. Two Swift targets: `Wavern` (app) + `WavernBrowserBridge` (CLI). One Chrome extension (MV3) bundled as resource.

**Lightweight constraint:** No background work when menu closed. All animations paused on `onDisappear`. Minimal allocations per poll tick.

**Tech Stack:** Swift 5, SwiftUI, AppKit, Core Audio (macOS 14.4+), NSVisualEffectView, AppleScript (NSAppleScript), URLSession, Chrome Extensions Manifest V3, Native Messaging stdio.

**Reference source:** `/Users/victor/Documents/estudos/voulum-main/Sources/Voulum/`
**Spec:** `docs/superpowers/specs/2026-09-02-wavern-design.md`

---

## File Map

### Created (new project)
| File | Purpose |
|------|---------|
| `project.yml` | XcodeGen config — Wavern app + WavernBrowserBridge CLI |
| `Sources/Wavern/WavernApp.swift` | App entry, MenuBarExtra, AppDelegate, animated icon |
| `Sources/Wavern/CoreAudioUtils.swift` | Ported from Voulum — typed Core Audio property wrappers |
| `Sources/Wavern/AudioProcess.swift` | Ported + extended with `chromiumBrowserName` |
| `Sources/Wavern/AudioProcessController.swift` | Ported + persistence + artwork + browserTabStore |
| `Sources/Wavern/ProcessTap.swift` | Ported from Voulum unchanged |
| `Sources/Wavern/LoginItem.swift` | Ported from Voulum unchanged |
| `Sources/Wavern/NowPlaying.swift` | Ported + `artworkData`/`artworkURLString` fields |
| `Sources/Wavern/NowPlayingService.swift` | Ported + artwork fetch |
| `Sources/Wavern/MarqueeText.swift` | Ported from Voulum unchanged |
| `Sources/Wavern/WaveformView.swift` | New — three-bar animated Canvas waveform |
| `Sources/Wavern/VisualEffectBackground.swift` | New — NSViewRepresentable vibrancy wrapper |
| `Sources/Wavern/BrowserTabStore.swift` | New — reads browser-tabs.json, publishes tabs |
| `Sources/Wavern/BrowserBridgeInstaller.swift` | New — writes NativeMessagingHosts JSON at launch |
| `Sources/Wavern/MenuView.swift` | New — full redesigned UI |
| `Sources/Wavern/Info.plist` | App metadata, NSMicrophoneUsageDescription |
| `Sources/Wavern/Wavern.entitlements` | Audio input entitlement |
| `Sources/WavernBrowserBridge/main.swift` | New — native messaging stdio relay |
| `Sources/BrowserExtension/manifest.json` | Chrome extension manifest (MV3) |
| `Sources/BrowserExtension/background.js` | Chrome extension service worker |

---

## Phase 0 — Project Scaffold

### Task 1: XcodeGen config and ported engine files

**Files:**
- Create: `project.yml`
- Create: `Sources/Wavern/Info.plist`
- Create: `Sources/Wavern/Wavern.entitlements`
- Create: `Sources/Wavern/CoreAudioUtils.swift` (port)
- Create: `Sources/Wavern/ProcessTap.swift` (port)
- Create: `Sources/Wavern/LoginItem.swift` (port)
- Create: `Sources/WavernBrowserBridge/main.swift` (placeholder)

- [ ] **Step 1: Create project.yml**

  ```yaml
  name: Wavern
  options:
    bundleIdPrefix: com.wavern
    deploymentTarget:
      macOS: "14.4"
    createIntermediateGroups: true
  settings:
    base:
      MARKETING_VERSION: "1.0.0"
      CURRENT_PROJECT_VERSION: "1"
      SWIFT_VERSION: "5.0"
      DEVELOPMENT_TEAM: ""
      CODE_SIGN_STYLE: Automatic
  targets:
    Wavern:
      type: application
      platform: macOS
      sources:
        - path: Sources/Wavern
      resources:
        - path: Sources/BrowserExtension
      settings:
        base:
          PRODUCT_BUNDLE_IDENTIFIER: com.wavern.app
          PRODUCT_NAME: Wavern
          INFOPLIST_FILE: Sources/Wavern/Info.plist
          CODE_SIGN_ENTITLEMENTS: Sources/Wavern/Wavern.entitlements
          GENERATE_INFOPLIST_FILE: NO
          ENABLE_HARDENED_RUNTIME: YES
          ENABLE_APP_SANDBOX: NO
          MACOSX_DEPLOYMENT_TARGET: "14.4"

    WavernBrowserBridge:
      type: tool
      platform: macOS
      sources:
        - path: Sources/WavernBrowserBridge
      settings:
        base:
          PRODUCT_BUNDLE_IDENTIFIER: com.wavern.browserbridge
          PRODUCT_NAME: WavernBrowserBridge
          MACOSX_DEPLOYMENT_TARGET: "14.4"
          ENABLE_APP_SANDBOX: NO
          ENABLE_HARDENED_RUNTIME: NO
          SWIFT_VERSION: "5.0"
  ```

- [ ] **Step 2: Create Info.plist**

  Create `Sources/Wavern/Info.plist`:

  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>CFBundleName</key>
      <string>Wavern</string>
      <key>CFBundleIdentifier</key>
      <string>com.wavern.app</string>
      <key>CFBundleVersion</key>
      <string>1</string>
      <key>CFBundleShortVersionString</key>
      <string>1.0.0</string>
      <key>CFBundleExecutable</key>
      <string>$(EXECUTABLE_NAME)</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>LSUIElement</key>
      <true/>
      <key>NSMicrophoneUsageDescription</key>
      <string>Wavern needs audio access to control per-app volume using Core Audio process taps.</string>
      <key>NSAppleEventsUsageDescription</key>
      <string>Wavern reads now-playing metadata from Spotify and Apple Music.</string>
  </dict>
  </plist>
  ```

- [ ] **Step 3: Create Wavern.entitlements**

  Create `Sources/Wavern/Wavern.entitlements`:

  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>com.apple.security.device.audio-input</key>
      <true/>
  </dict>
  </plist>
  ```

- [ ] **Step 4: Port CoreAudioUtils.swift**

  Copy `CoreAudioUtils.swift` from `/Users/victor/Documents/estudos/voulum-main/Sources/Voulum/CoreAudioUtils.swift` to `Sources/Wavern/CoreAudioUtils.swift`. Change only the logger subsystem:

  Find: `Logger(subsystem: "com.voulum.app", category: "audio")`
  Replace: `Logger(subsystem: "com.wavern.app", category: "audio")`

- [ ] **Step 5: Port ProcessTap.swift**

  Copy `ProcessTap.swift` from `/Users/victor/Documents/estudos/voulum-main/Sources/Voulum/ProcessTap.swift` to `Sources/Wavern/ProcessTap.swift`. No changes needed.

- [ ] **Step 6: Port LoginItem.swift**

  Copy `LoginItem.swift` from `/Users/victor/Documents/estudos/voulum-main/Sources/Voulum/LoginItem.swift` to `Sources/Wavern/LoginItem.swift`. No changes needed.

- [ ] **Step 7: Port MarqueeText.swift**

  Copy `MarqueeText.swift` from `/Users/victor/Documents/estudos/voulum-main/Sources/Voulum/MarqueeText.swift` to `Sources/Wavern/MarqueeText.swift`. No changes needed.

- [ ] **Step 8: Create WavernBrowserBridge placeholder**

  Create `Sources/WavernBrowserBridge/main.swift`:

  ```swift
  import Foundation
  // WavernBrowserBridge — implemented in Task 10
  print("WavernBrowserBridge placeholder")
  ```

- [ ] **Step 9: Create BrowserExtension placeholder files**

  Create `Sources/BrowserExtension/manifest.json`:

  ```json
  { "manifest_version": 3, "name": "Wavern Tab Bridge", "version": "1.0" }
  ```

  Create `Sources/BrowserExtension/background.js`:

  ```javascript
  // implemented in Task 9
  ```

- [ ] **Step 10: Generate Xcode project and verify it builds (empty)**

  ```bash
  cd /Users/victor/Documents/estudos/wavern
  xcodegen generate
  xcodebuild -project Wavern.xcodeproj -scheme Wavern \
    -configuration Debug -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -10
  ```

  At this point the build will fail because Swift source files are missing. That's expected — we just need to confirm the `.xcodeproj` was generated without errors.

  Expected: `xcodegen` exits 0, `.xcodeproj` created.

- [ ] **Step 11: Commit scaffold**

  ```bash
  cd /Users/victor/Documents/estudos/wavern
  git add -A
  git commit -m "chore: project scaffold — XcodeGen config, ported engine files"
  ```

---

## Phase 1 — Audio Model and Controller

### Task 2: AudioProcess, NowPlaying, NowPlayingService

**Files:**
- Create: `Sources/Wavern/AudioProcess.swift`
- Create: `Sources/Wavern/NowPlaying.swift`
- Create: `Sources/Wavern/NowPlayingService.swift`

- [ ] **Step 1: Create AudioProcess.swift**

  Port from Voulum and add `chromiumBrowserName`. Create `Sources/Wavern/AudioProcess.swift`:

  ```swift
  import AppKit
  import CoreAudio
  import Foundation

  struct AudioProcess: Identifiable, Hashable {
      let objectID: AudioObjectID
      let pid: pid_t
      let bundleID: String?
      var isPlaying: Bool

      var id: AudioObjectID { objectID }

      var name: String {
          if let app = runningApp, let n = app.localizedName { return n }
          if let bundleID { return prettyBundleName(bundleID) }
          return "PID \(pid)"
      }

      var icon: NSImage? { runningApp?.icon }

      var resolvedBundleID: String? {
          runningApp?.bundleIdentifier ?? bundleID
      }

      /// Non-nil for Chromium-family browsers with tab enrichment support.
      var chromiumBrowserName: String? {
          guard let b = resolvedBundleID else { return nil }
          let known: [String: String] = [
              "com.google.Chrome":           "Chrome",
              "company.thebrowser.Browser":  "Arc",
              "com.brave.Browser":           "Brave",
              "com.microsoft.edgemac":       "Edge",
          ]
          return known[b]
      }

      var runningApp: NSRunningApplication? {
          var firstMatch: NSRunningApplication?
          var current: pid_t? = pid
          var hops = 0
          while let p = current, hops < 8 {
              if let app = NSRunningApplication(processIdentifier: p) {
                  if app.activationPolicy == .regular { return app }
                  if firstMatch == nil { firstMatch = app }
              }
              current = AudioProcess.parentPID(of: p)
              hops += 1
          }
          return firstMatch
      }

      private static func parentPID(of pid: pid_t) -> pid_t? {
          var info = kinfo_proc()
          var size = MemoryLayout<kinfo_proc>.stride
          var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
          let rc = mib.withUnsafeMutableBufferPointer { buf in
              sysctl(buf.baseAddress, UInt32(buf.count), &info, &size, nil, 0)
          }
          guard rc == 0, size > 0 else { return nil }
          let ppid = info.kp_eproc.e_ppid
          return ppid > 1 ? ppid : nil
      }

      func activate() {
          runningApp?.activate(options: [.activateAllWindows])
      }
  }

  private func prettyBundleName(_ bundleID: String) -> String {
      let parts = bundleID.split(separator: ".")
      guard parts.count > 2 else { return bundleID }
      return parts.dropFirst(2).joined(separator: " ")
  }
  ```

- [ ] **Step 2: Create NowPlaying.swift**

  Create `Sources/Wavern/NowPlaying.swift`:

  ```swift
  import Foundation

  struct NowPlaying: Equatable {
      let title: String
      let artist: String
      let album: String?
      let isPlaying: Bool
      var artworkData: Data?        // Apple Music: raw bytes from AppleScript descriptor
      var artworkURLString: String? // Spotify: URL string, download via URLSession

      var subtitle: String {
          switch (artist.isEmpty, album?.isEmpty ?? true) {
          case (false, false): return "\(artist) — \(album!)"
          case (false, true):  return artist
          case (true, false):  return album!
          case (true, true):   return ""
          }
      }
  }
  ```

- [ ] **Step 3: Create NowPlayingService.swift**

  Create `Sources/Wavern/NowPlayingService.swift`:

  ```swift
  import AppKit
  import Foundation

  enum NowPlayingService {

      enum Command { case playPause, next, previous }

      private struct Recipe {
          let metadata: String
          let playPause: String
          let next: String
          let previous: String
      }

      private static let recipes: [String: Recipe] = [
          "com.spotify.client": spotifyStyle(),
          "com.apple.Music":    musicStyle(),
          "org.videolan.vlc":   vlcStyle(),
      ]

      static func supports(_ bundleID: String?) -> Bool {
          guard let bundleID else { return false }
          return recipes[bundleID] != nil
      }

      static func send(_ command: Command, bundleID: String) {
          guard let recipe = recipes[bundleID] else { return }
          let source: String
          switch command {
          case .playPause: source = recipe.playPause
          case .next:      source = recipe.next
          case .previous:  source = recipe.previous
          }
          run(source, context: "command \(command)")
      }

      /// Fetches track metadata. Returns nil on failure or no track.
      /// Runs blocking Apple events — call off the main thread.
      static func fetch(bundleID: String) -> NowPlaying? {
          guard let recipe = recipes[bundleID] else { return nil }
          guard let raw = run(recipe.metadata, context: "metadata"),
                raw != noTrackSentinel else { return nil }
          let parts = raw.components(separatedBy: "\n")
          guard parts.count >= 4 else { return nil }
          let album = parts[2].isEmpty ? nil : parts[2]
          let isPlaying = parts[3].caseInsensitiveCompare("playing") == .orderedSame
          let artURLString: String? = parts.count >= 5 && !parts[4].isEmpty ? parts[4] : nil
          return NowPlaying(title: parts[0], artist: parts[1], album: album,
                            isPlaying: isPlaying, artworkURLString: artURLString)
      }

      /// Fetches raw artwork bytes from Apple Music. Runs blocking — call off main thread.
      static func fetchArtworkData(bundleID: String) -> Data? {
          guard bundleID == "com.apple.Music" else { return nil }
          let source = """
          tell application "Music"
              try
                  get data of artwork 1 of current track
              on error
                  return ""
              end try
          end tell
          """
          guard let script = NSAppleScript(source: source) else { return nil }
          var errorInfo: NSDictionary?
          let descriptor = script.executeAndReturnError(&errorInfo)
          if errorInfo != nil { return nil }
          return descriptor.data
      }

      @discardableResult
      private static func run(_ source: String, context: String) -> String? {
          guard let script = NSAppleScript(source: source) else { return nil }
          var errorInfo: NSDictionary?
          let output = script.executeAndReturnError(&errorInfo)
          if let errorInfo {
              log.error("NowPlaying \(context, privacy: .public) failed: \(errorInfo)")
              return nil
          }
          return output.stringValue
      }

      private static func spotifyStyle() -> Recipe {
          let metadata = """
          tell application "Spotify"
              try
                  set trackName to name of current track
                  set trackArtist to artist of current track
                  set trackAlbum to album of current track
                  set playState to (player state as text)
                  set artURL to ""
                  try
                      set artURL to artwork url of current track
                  end try
                  return trackName & linefeed & trackArtist & linefeed & trackAlbum & linefeed & playState & linefeed & artURL
              on error
                  return "\(noTrackSentinel)"
              end try
          end tell
          """
          return Recipe(
              metadata: metadata,
              playPause: "tell application \"Spotify\" to playpause",
              next:      "tell application \"Spotify\" to next track",
              previous:  "tell application \"Spotify\" to previous track")
      }

      private static func musicStyle() -> Recipe {
          let metadata = """
          tell application "Music"
              try
                  set trackName to name of current track
                  set trackArtist to artist of current track
                  set trackAlbum to album of current track
                  set playState to (player state as text)
                  return trackName & linefeed & trackArtist & linefeed & trackAlbum & linefeed & playState & linefeed & ""
              on error
                  return "\(noTrackSentinel)"
              end try
          end tell
          """
          return Recipe(
              metadata: metadata,
              playPause: "tell application \"Music\" to playpause",
              next:      "tell application \"Music\" to next track",
              previous:  "tell application \"Music\" to previous track")
      }

      private static func vlcStyle() -> Recipe {
          let metadata = """
          tell application "VLC"
              try
                  set trackName to name of current item
                  if trackName is missing value then set trackName to ""
                  set playState to "paused"
                  if (playing) then set playState to "playing"
                  if trackName is "" then return "\(noTrackSentinel)"
                  return trackName & linefeed & "" & linefeed & "" & linefeed & playState & linefeed & ""
              on error
                  return "\(noTrackSentinel)"
              end try
          end tell
          """
          return Recipe(
              metadata: metadata,
              playPause: "tell application \"VLC\" to play",
              next:      "tell application \"VLC\" to next",
              previous:  "tell application \"VLC\" to previous")
      }

      private static let noTrackSentinel = "__wavern_no_track__"
  }
  ```

- [ ] **Step 4: Commit**

  ```bash
  cd /Users/victor/Documents/estudos/wavern
  git add Sources/Wavern/AudioProcess.swift Sources/Wavern/NowPlaying.swift \
          Sources/Wavern/NowPlayingService.swift
  git commit -m "feat: audio process model, NowPlaying with artwork fields, NowPlayingService"
  ```

### Task 3: AudioProcessController with persistence and artwork

**Files:**
- Create: `Sources/Wavern/AudioProcessController.swift`

- [ ] **Step 1: Create AudioProcessController.swift**

  Port from Voulum and add: persistence, artworkImages, artworkCache, browserTabStore. Create `Sources/Wavern/AudioProcessController.swift`:

  ```swift
  import AudioToolbox
  import Combine
  import CoreAudio
  import Foundation

  @MainActor
  final class AudioProcessController: ObservableObject {

      static let shared = AudioProcessController()

      @Published private(set) var processes: [AudioProcess] = []
      var playing: [AudioProcess] {
          processes.filter(\.isPlaying)
              .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
      }

      private var pollTimer: Timer?
      private let pollInterval: TimeInterval = 1.0

      private let halQueue = DispatchQueue(label: "com.wavern.hal", qos: .userInitiated)
      private var reloadInFlight = false

      // MARK: Now playing

      @Published private(set) var nowPlaying: [AudioObjectID: NowPlaying] = [:]
      private let scriptQueue = DispatchQueue(label: "com.wavern.nowplaying", qos: .userInitiated)
      private var nowPlayingRefreshInFlight = false

      func nowPlaying(for process: AudioProcess) -> NowPlaying? { nowPlaying[process.id] }

      // MARK: Artwork

      @Published private(set) var artworkImages: [AudioObjectID: NSImage] = [:]
      private var artworkCache: [String: NSImage] = [:]   // key: "\(artist)∙\(title)"

      private func artworkCacheKey(for np: NowPlaying) -> String { "\(np.artist)∙\(np.title)" }

      private func fetchSpotifyArtwork(for id: AudioObjectID, urlString: String, cacheKey: String) {
          guard let url = URL(string: urlString) else { return }
          URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
              guard let data, let image = NSImage(data: data) else { return }
              Task { @MainActor in
                  guard let self else { return }
                  self.artworkCache[cacheKey] = image
                  self.artworkImages[id] = image
              }
          }.resume()
      }

      // MARK: Browser tabs

      let browserTabStore = BrowserTabStore()

      // MARK: Transport

      func sendMediaCommand(_ command: NowPlayingService.Command, to process: AudioProcess) {
          guard let bundleID = process.resolvedBundleID,
                NowPlayingService.supports(bundleID) else { return }
          if command == .playPause, let current = nowPlaying[process.id] {
              nowPlaying[process.id] = NowPlaying(title: current.title, artist: current.artist,
                                                   album: current.album, isPlaying: !current.isPlaying)
          }
          scriptQueue.async { [weak self] in
              NowPlayingService.send(command, bundleID: bundleID)
              Task { @MainActor in
                  try? await Task.sleep(nanoseconds: 350_000_000)
                  self?.refreshNowPlaying()
              }
          }
      }

      // MARK: Volume state

      private var taps: [AudioObjectID: ProcessTap] = [:]
      @Published private(set) var volumes: [AudioObjectID: Float] = [:]
      @Published private(set) var muted: Set<AudioObjectID> = []
      @Published private(set) var tapErrors: [AudioObjectID: String] = [:]

      @Published private(set) var audioPermissionGranted: Bool =
          UserDefaults.standard.bool(forKey: "wavern.hasGrantedAudioTap")

      static let maxGain: Float = 2.0

      func volume(for process: AudioProcess) -> Float { volumes[process.id] ?? 1.0 }
      func isMuted(_ process: AudioProcess) -> Bool { muted.contains(process.id) }

      func setVolume(_ value: Float, for process: AudioProcess) {
          volumes[process.id] = value
          if value > 0 { muted.remove(process.id) }
          if let b = process.resolvedBundleID {
              UserDefaults.standard.set(value, forKey: "wavern.vol.\(b)")
              UserDefaults.standard.set(false, forKey: "wavern.muted.\(b)")
          }
          applyGain(for: process)
      }

      func toggleMute(_ process: AudioProcess) {
          if muted.contains(process.id) { muted.remove(process.id) }
          else { muted.insert(process.id) }
          if let b = process.resolvedBundleID {
              UserDefaults.standard.set(muted.contains(process.id), forKey: "wavern.muted.\(b)")
          }
          applyGain(for: process)
      }

      private func applyGain(for process: AudioProcess) {
          let effective: Float = muted.contains(process.id) ? 0 : (volumes[process.id] ?? 1.0)
          guard let tap = ensureTap(for: process) else { return }
          tap.gain = effective
      }

      private func restorePersistedState(for process: AudioProcess) {
          guard let bundleID = process.resolvedBundleID else { return }
          guard volumes[process.id] == nil else { return }
          let v = UserDefaults.standard.float(forKey: "wavern.vol.\(bundleID)")
          if v > 0 { volumes[process.id] = v }
          if UserDefaults.standard.bool(forKey: "wavern.muted.\(bundleID)") {
              muted.insert(process.id)
          }
      }

      private func ensureTap(for process: AudioProcess) -> ProcessTap? {
          if let existing = taps[process.id] { return existing }
          let tap = ProcessTap(process: process)
          taps[process.id] = tap
          tapErrors[process.id] = nil
          let id = process.id
          let name = process.name
          halQueue.async { [weak self] in
              do {
                  try tap.activate()
                  Task { @MainActor in self?.rememberPermissionGranted() }
              } catch {
                  let message = String(describing: error)
                  log.error("Tap activation failed for \(name, privacy: .public): \(message, privacy: .public)")
                  Task { @MainActor in
                      guard let self else { return }
                      if self.taps[id] === tap {
                          self.taps.removeValue(forKey: id)
                          self.tapErrors[id] = message
                      }
                  }
              }
          }
          return tap
      }

      private func rememberPermissionGranted() {
          guard !audioPermissionGranted else { return }
          audioPermissionGranted = true
          UserDefaults.standard.set(true, forKey: "wavern.hasGrantedAudioTap")
      }

      private func pruneVanishedTaps(livingIDs: Set<AudioObjectID>) {
          for (id, tap) in taps where !livingIDs.contains(id) {
              halQueue.async { tap.invalidate() }
              taps.removeValue(forKey: id)
              volumes.removeValue(forKey: id)
              muted.remove(id)
              tapErrors.removeValue(forKey: id)
          }
      }

      private var started = false

      func start() {
          guard !started else { return }
          started = true
          log.info("Wavern starting")
          halQueue.async { ProcessTap.reapLeakedDevices() }
          reload()
      }

      // MARK: Live updates

      func beginLiveUpdates() {
          reload()
          pollTimer?.invalidate()
          pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
              Task { @MainActor in self?.reload() }
          }
      }

      func endLiveUpdates() {
          pollTimer?.invalidate()
          pollTimer = nil
      }

      // MARK: Enumeration

      func reload() {
          guard !reloadInFlight else { return }
          reloadInFlight = true
          halQueue.async { [weak self] in
              let result = Self.enumerateProcesses()
              Task { @MainActor in
                  guard let self else { return }
                  self.reloadInFlight = false
                  self.processes = result
                  for process in result { self.restorePersistedState(for: process) }
                  let living = Set(result.map(\.id))
                  self.pruneVanishedTaps(livingIDs: living)
                  self.nowPlaying = self.nowPlaying.filter { living.contains($0.key) }
                  self.refreshNowPlaying()
                  self.browserTabStore.refresh()
              }
          }
      }

      private func refreshNowPlaying() {
          guard !nowPlayingRefreshInFlight else { return }
          let targets: [(id: AudioObjectID, bundleID: String)] = playing.compactMap { process in
              guard let bundleID = process.resolvedBundleID,
                    NowPlayingService.supports(bundleID) else { return nil }
              return (process.id, bundleID)
          }
          let playingIDs = Set(targets.map(\.id))
          if nowPlaying.keys.contains(where: { !playingIDs.contains($0) }) {
              nowPlaying = nowPlaying.filter { playingIDs.contains($0.key) }
          }
          guard !targets.isEmpty else { return }
          nowPlayingRefreshInFlight = true
          scriptQueue.async { [weak self] in
              var fetched: [AudioObjectID: NowPlaying] = [:]
              for target in targets {
                  if var info = NowPlayingService.fetch(bundleID: target.bundleID) {
                      if let data = NowPlayingService.fetchArtworkData(bundleID: target.bundleID) {
                          info.artworkData = data
                      }
                      fetched[target.id] = info
                  }
              }
              Task { @MainActor in
                  guard let self else { return }
                  self.nowPlayingRefreshInFlight = false
                  for (id, info) in fetched { self.nowPlaying[id] = info }
                  for id in playingIDs where fetched[id] == nil {
                      self.nowPlaying.removeValue(forKey: id)
                  }
                  // Resolve artwork
                  for (id, info) in fetched {
                      let key = self.artworkCacheKey(for: info)
                      if let cached = self.artworkCache[key] {
                          self.artworkImages[id] = cached
                      } else if let data = info.artworkData, let img = NSImage(data: data) {
                          self.artworkCache[key] = img
                          self.artworkImages[id] = img
                      } else if let urlStr = info.artworkURLString {
                          self.fetchSpotifyArtwork(for: id, urlString: urlStr, cacheKey: key)
                      }
                  }
                  let liveKeys = Set(fetched.values.map { self.artworkCacheKey(for: $0) })
                  self.artworkCache = self.artworkCache.filter { liveKeys.contains($0.key) }
                  for id in self.artworkImages.keys where fetched[id] == nil {
                      self.artworkImages.removeValue(forKey: id)
                  }
              }
          }
      }

      nonisolated private static func enumerateProcesses() -> [AudioProcess] {
          do {
              let objectIDs: [AudioObjectID] = try AudioObjectID.system.readArray(
                  kAudioHardwarePropertyProcessObjectList)
              var result: [AudioProcess] = []
              result.reserveCapacity(objectIDs.count)
              for objectID in objectIDs where objectID.isValid {
                  guard let process = makeProcess(objectID) else { continue }
                  result.append(process)
              }
              return result
          } catch {
              log.error("Failed to read process list: \(String(describing: error))")
              return []
          }
      }

      nonisolated private static let ownPID: pid_t = ProcessInfo.processInfo.processIdentifier

      nonisolated private static func makeProcess(_ objectID: AudioObjectID) -> AudioProcess? {
          let pid: pid_t = (try? objectID.read(kAudioProcessPropertyPID, default: pid_t(-1))) ?? -1
          guard pid > 0, pid != ownPID else { return nil }
          let bundleID: String? = try? objectID.readCF(kAudioProcessPropertyBundleID, as: String.self) ?? nil
          let isRunningOutput: UInt32 = (try? objectID.read(
              kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) ?? 0
          return AudioProcess(objectID: objectID, pid: pid, bundleID: bundleID,
                              isPlaying: isRunningOutput != 0)
      }
  }
  ```

- [ ] **Step 2: Build to verify**

  ```bash
  cd /Users/victor/Documents/estudos/wavern
  xcodegen generate
  xcodebuild -project Wavern.xcodeproj -scheme Wavern \
    -configuration Debug -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD"
  ```

  Will still fail — `BrowserTabStore` not yet created. Expected error: `cannot find type 'BrowserTabStore'`. That's fine — proceed.

- [ ] **Step 3: Commit**

  ```bash
  git add Sources/Wavern/AudioProcessController.swift
  git commit -m "feat: AudioProcessController with persistence, artwork fetch, browser tab store hook"
  ```

---

## Phase 2 — UI Components

### Task 4: WaveformView, VisualEffectBackground, BrowserTabStore, BrowserBridgeInstaller

**Files:**
- Create: `Sources/Wavern/WaveformView.swift`
- Create: `Sources/Wavern/VisualEffectBackground.swift`
- Create: `Sources/Wavern/BrowserTabStore.swift`
- Create: `Sources/Wavern/BrowserBridgeInstaller.swift`

- [ ] **Step 1: Create WaveformView.swift**

  Create `Sources/Wavern/WaveformView.swift`:

  ```swift
  import SwiftUI

  /// Three-bar animated waveform. Paused when isAnimating is false,
  /// so no CPU is used when muted or idle.
  struct WaveformView: View {
      var isAnimating: Bool

      var body: some View {
          TimelineView(.animation(paused: !isAnimating)) { context in
              Canvas { ctx, size in
                  let t = context.date.timeIntervalSinceReferenceDate
                  let barW: CGFloat = 3
                  let gap: CGFloat = 2
                  let phases: [Double] = [0, .pi * 0.7, .pi * 1.4]
                  for (i, phase) in phases.enumerated() {
                      let x = CGFloat(i) * (barW + gap)
                      let frac: CGFloat = isAnimating
                          ? CGFloat(0.25 + 0.75 * (sin(t * 4 + phase) * 0.5 + 0.5))
                          : 0.25
                      let h = size.height * frac
                      let y = (size.height - h) / 2
                      ctx.fill(
                          Path(roundedRect: CGRect(x: x, y: y, width: barW, height: h),
                               cornerRadius: 1.5),
                          with: .color(.secondary)
                      )
                  }
              }
          }
          .frame(width: 13, height: 14)
      }
  }
  ```

- [ ] **Step 2: Create VisualEffectBackground.swift**

  Create `Sources/Wavern/VisualEffectBackground.swift`:

  ```swift
  import AppKit
  import SwiftUI

  struct VisualEffectBackground: NSViewRepresentable {
      var material: NSVisualEffectView.Material = .popover
      var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

      func makeNSView(context: Context) -> NSVisualEffectView {
          let view = NSVisualEffectView()
          view.material = material
          view.blendingMode = blendingMode
          view.state = .active
          return view
      }

      func updateNSView(_ view: NSVisualEffectView, context: Context) {
          view.material = material
          view.blendingMode = blendingMode
      }
  }
  ```

- [ ] **Step 3: Create BrowserTabStore.swift**

  Create `Sources/Wavern/BrowserTabStore.swift`:

  ```swift
  import Foundation

  struct BrowserTab: Codable, Identifiable, Hashable {
      let title: String
      let url: String
      let favIconUrl: String?
      let audible: Bool?
      var id: String { url }
  }

  private struct BrowserTabsFile: Codable {
      let tabs: [BrowserTab]
      let timestamp: TimeInterval?
  }

  @MainActor
  final class BrowserTabStore: ObservableObject {
      @Published private(set) var audibleTabs: [BrowserTab] = []
      private var lastUpdated: Date?

      private let fileURL: URL = {
          let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first!
          return appSupport.appendingPathComponent("Wavern/browser-tabs.json")
      }()

      func refresh() {
          guard let data = try? Data(contentsOf: fileURL),
                let file = try? JSONDecoder().decode(BrowserTabsFile.self, from: data) else {
              if let last = lastUpdated, Date().timeIntervalSince(last) > 30 {
                  audibleTabs = []
                  lastUpdated = nil
              }
              return
          }
          lastUpdated = Date()
          audibleTabs = file.tabs.filter { $0.audible ?? true }
      }

      var isConnected: Bool {
          guard let last = lastUpdated else { return false }
          return Date().timeIntervalSince(last) < 5
      }
  }
  ```

- [ ] **Step 4: Create BrowserBridgeInstaller.swift**

  Create `Sources/Wavern/BrowserBridgeInstaller.swift`. The `extensionID` constant must be filled in during Task 9 (after generating the extension key pair). Use `"PENDING_EXTENSION_ID"` as placeholder now:

  ```swift
  import Foundation

  enum BrowserBridgeInstaller {

      static let hostName = "com.wavern.browserbridge"
      // Replace with actual ID after generating manifest key in Task 9.
      static let extensionID = "PENDING_EXTENSION_ID"

      private static var bridgePath: String {
          Bundle.main.bundleURL
              .appendingPathComponent("Contents/MacOS/WavernBrowserBridge")
              .path
      }

      private static let browserSupportDirs = [
          "Google/Chrome",
          "BraveSoftware/Brave-Browser",
          "Arc",
          "Microsoft Edge",
      ]

      static func install() {
          guard FileManager.default.fileExists(atPath: bridgePath) else { return }
          let manifest: [String: Any] = [
              "name":        hostName,
              "description": "Wavern browser tab bridge",
              "path":        bridgePath,
              "type":        "stdio",
              "allowed_origins": ["chrome-extension://\(extensionID)/"]
          ]
          guard let data = try? JSONSerialization.data(withJSONObject: manifest,
                                                        options: .prettyPrinted) else { return }
          let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first!
          for dir in browserSupportDirs {
              let hostDir = appSupport
                  .appendingPathComponent(dir)
                  .appendingPathComponent("NativeMessagingHosts")
              try? FileManager.default.createDirectory(at: hostDir, withIntermediateDirectories: true)
              let dest = hostDir.appendingPathComponent("\(hostName).json")
              // Skip if already installed with same content
              if let existing = try? Data(contentsOf: dest),
                 let existingStr = String(data: existing, encoding: .utf8),
                 existingStr.contains(bridgePath) { continue }
              try? data.write(to: dest)
          }
      }
  }
  ```

- [ ] **Step 5: Build**

  ```bash
  cd /Users/victor/Documents/estudos/wavern
  xcodebuild -project Wavern.xcodeproj -scheme Wavern \
    -configuration Debug -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD"
  ```

  Still missing `WavernApp.swift` and `MenuView.swift`. Expected: `cannot find type 'WavernApp'` or similar. Confirm no unexpected errors in the files just created.

- [ ] **Step 6: Commit**

  ```bash
  git add Sources/Wavern/WaveformView.swift Sources/Wavern/VisualEffectBackground.swift \
          Sources/Wavern/BrowserTabStore.swift Sources/Wavern/BrowserBridgeInstaller.swift
  git commit -m "feat: WaveformView, VisualEffectBackground, BrowserTabStore, BrowserBridgeInstaller"
  ```

### Task 5: MenuView — full redesigned UI

**Files:**
- Create: `Sources/Wavern/MenuView.swift`

- [ ] **Step 1: Create MenuView.swift**

  Create `Sources/Wavern/MenuView.swift`:

  ```swift
  import AppKit
  import SwiftUI

  // MARK: - MenuView

  struct MenuView: View {
      @EnvironmentObject var controller: AudioProcessController
      @EnvironmentObject var browserTabStore: BrowserTabStore
      @State private var launchAtLogin = LoginItem.isEnabled

      var body: some View {
          VStack(alignment: .leading, spacing: 0) {
              let playing = controller.playing
              if playing.isEmpty {
                  emptyState
              } else {
                  ForEach(playing) { process in
                      AudioProcessRow(process: process)
                      if process.id != playing.last?.id {
                          Divider().padding(.leading, 52)
                      }
                  }
              }
              Divider()
              footer
          }
          .frame(width: 340)
          .background(VisualEffectBackground(material: .popover, blendingMode: .behindWindow))
          .onAppear { controller.beginLiveUpdates() }
          .onDisappear { controller.endLiveUpdates() }
      }

      private var emptyState: some View {
          VStack(spacing: 6) {
              Image(systemName: "speaker.slash")
                  .font(.system(size: 24))
                  .foregroundStyle(.secondary)
              Text("Nothing is playing")
                  .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 20)
      }

      private var footer: some View {
          VStack(alignment: .leading, spacing: 8) {
              Toggle("Launch at login", isOn: launchAtLoginBinding)
                  .toggleStyle(.checkbox)
                  .controlSize(.small)
              if !controller.audioPermissionGranted {
                  Label("First volume change asks for audio permission.",
                        systemImage: "info.circle")
                      .font(.caption)
                      .foregroundStyle(.secondary)
              }
              HStack {
                  Button("Quit Wavern") { NSApp.terminate(nil) }
                      .buttonStyle(.borderless)
                  Spacer()
              }
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 6)
      }

      private var launchAtLoginBinding: Binding<Bool> {
          Binding(
              get: { launchAtLogin },
              set: { launchAtLogin = LoginItem.setEnabled($0) }
          )
      }
  }

  // MARK: - AudioProcessRow

  struct AudioProcessRow: View {
      let process: AudioProcess
      @EnvironmentObject var controller: AudioProcessController
      @EnvironmentObject var browserTabStore: BrowserTabStore
      @State private var isHovered = false
      @State private var showExtensionSheet = false

      private var isMuted: Bool { controller.isMuted(process) }

      private var volume: Binding<Double> {
          Binding(
              get: { isMuted ? 0 : Double(controller.volume(for: process)) },
              set: { controller.setVolume(Float($0), for: process) }
          )
      }

      private var enrichedTab: BrowserTab? {
          guard process.chromiumBrowserName != nil,
                browserTabStore.isConnected else { return nil }
          return browserTabStore.audibleTabs.first
      }

      var body: some View {
          VStack(alignment: .leading, spacing: 6) {
              HStack(spacing: 10) {
                  artArea

                  VStack(alignment: .leading, spacing: 2) {
                      HStack(spacing: 4) {
                          if let tab = enrichedTab {
                              MarqueeText(text: tab.title, weight: .medium)
                          } else if let track = controller.nowPlaying(for: process) {
                              MarqueeText(text: track.title, weight: .medium)
                          } else {
                              MarqueeText(text: process.name, weight: .medium)
                          }
                          WaveformView(isAnimating: process.isPlaying && !isMuted)
                      }

                      if let tab = enrichedTab, let browserName = process.chromiumBrowserName {
                          Text(browserName)
                              .font(.caption)
                              .foregroundStyle(.secondary)
                      } else if let track = controller.nowPlaying(for: process) {
                          MarqueeText(
                              text: track.subtitle.isEmpty
                                  ? process.name
                                  : "\(track.subtitle) · \(process.name)",
                              font: .caption
                          )
                          .foregroundStyle(.secondary)
                      } else {
                          Text(process.isPlaying ? "Playing" : "Idle")
                              .font(.caption)
                              .foregroundStyle(process.isPlaying ? Color.green : .secondary)
                      }
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)

                  if controller.nowPlaying(for: process) != nil {
                      transportControls
                  }

                  Button { process.activate() } label: {
                      Image(systemName: "arrow.up.right.square")
                  }
                  .buttonStyle(.borderless)
                  .help("Bring \(process.name) to front")
              }

              HStack(spacing: 8) {
                  Button {
                      controller.toggleMute(process)
                  } label: {
                      Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                          .foregroundStyle(isMuted ? Color.red : .primary)
                          .frame(width: 16)
                  }
                  .buttonStyle(.borderless)
                  .help(isMuted ? "Unmute" : "Mute")

                  Slider(value: volume, in: 0...Double(AudioProcessController.maxGain))
                      .controlSize(.small)
                      .tint(.accentColor)

                  Text(percentLabel)
                      .font(.caption.monospacedDigit())
                      .foregroundStyle(.secondary)
                      .frame(width: 38, alignment: .trailing)
              }

              // Browser extension nudge
              if process.chromiumBrowserName != nil && !browserTabStore.isConnected {
                  Button("Install browser extension for tab names →") {
                      showExtensionSheet = true
                  }
                  .buttonStyle(.borderless)
                  .font(.caption)
                  .foregroundStyle(.accentColor)
              }

              if let error = controller.tapErrors[process.id] {
                  Text(errorHint(error))
                      .font(.caption2)
                      .foregroundStyle(.red)
                      .lineLimit(2)
              }
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(isHovered ? Color(NSColor.quaternaryLabelColor).opacity(0.3) : .clear)
          .contentShape(Rectangle())
          .onHover { isHovered = $0 }
          .sheet(isPresented: $showExtensionSheet) {
              ExtensionOnboardingSheet()
          }
      }

      private var percentLabel: String {
          if isMuted { return "muted" }
          return "\(Int((controller.volume(for: process) * 100).rounded()))%"
      }

      private func errorHint(_ raw: String) -> String {
          "Couldn't tap audio. Grant Wavern permission in System Settings ▸ Privacy & Security ▸ Microphone, then retry."
      }

      @ViewBuilder private var transportControls: some View {
          let isPlaying = controller.nowPlaying(for: process)?.isPlaying ?? false
          HStack(spacing: 8) {
              Button { controller.sendMediaCommand(.previous, to: process) } label: {
                  Image(systemName: "backward.fill")
              }.help("Previous track")
              Button { controller.sendMediaCommand(.playPause, to: process) } label: {
                  Image(systemName: isPlaying ? "pause.fill" : "play.fill")
              }.help(isPlaying ? "Pause" : "Play")
              Button { controller.sendMediaCommand(.next, to: process) } label: {
                  Image(systemName: "forward.fill")
              }.help("Next track")
          }
          .buttonStyle(.borderless)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }

      @ViewBuilder private var artArea: some View {
          let artwork = controller.artworkImages[process.id]
          ZStack(alignment: .bottomTrailing) {
              Group {
                  if let artwork {
                      Image(nsImage: artwork)
                          .resizable()
                          .aspectRatio(contentMode: .fill)
                          .frame(width: 40, height: 40)
                          .clipShape(RoundedRectangle(cornerRadius: 8))
                  } else if let icon = process.icon {
                      ZStack {
                          RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                              .frame(width: 40, height: 40)
                          Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                      }
                  } else {
                      RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                          .frame(width: 40, height: 40)
                          .overlay {
                              Image(systemName: "app.dashed")
                                  .font(.system(size: 20)).foregroundStyle(.secondary)
                          }
                  }
              }
              if artwork != nil, let icon = process.icon {
                  Image(nsImage: icon)
                      .resizable().frame(width: 16, height: 16)
                      .clipShape(RoundedRectangle(cornerRadius: 3))
                      .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white, lineWidth: 1))
                      .shadow(radius: 1)
                      .offset(x: 3, y: 3)
              }
          }
      }
  }

  // MARK: - ExtensionOnboardingSheet

  struct ExtensionOnboardingSheet: View {
      @Environment(\.dismiss) private var dismiss

      private var extensionPath: String {
          Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension").path ?? "—"
      }

      var body: some View {
          VStack(alignment: .leading, spacing: 16) {
              Text("Install Wavern Tab Bridge")
                  .font(.headline)

              VStack(alignment: .leading, spacing: 10) {
                  Label("Open Chrome extensions page", systemImage: "1.circle")
                  Button("Open chrome://extensions") {
                      NSWorkspace.shared.open(
                          URL(string: "googlechrome://extensions") ?? URL(string: "https://google.com")!)
                  }
                  .buttonStyle(.borderedProminent)

                  Label("Enable **Developer Mode** (top-right toggle)", systemImage: "2.circle")
                      .fixedSize(horizontal: false, vertical: true)

                  Label("Click **Load unpacked** and select this folder:", systemImage: "3.circle")
                  HStack {
                      Text(extensionPath)
                          .font(.caption.monospaced())
                          .lineLimit(2)
                          .truncationMode(.middle)
                      Spacer()
                      Button("Copy") {
                          NSPasteboard.general.clearContents()
                          NSPasteboard.general.setString(extensionPath, forType: .string)
                      }
                      .controlSize(.small)
                  }
                  .padding(8)
                  .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
              }

              HStack {
                  Spacer()
                  Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
              }
          }
          .padding(20)
          .frame(width: 400)
      }
  }
  ```

- [ ] **Step 2: Build**

  ```bash
  cd /Users/victor/Documents/estudos/wavern
  xcodebuild -project Wavern.xcodeproj -scheme Wavern \
    -configuration Debug -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD"
  ```

  Still missing `WavernApp.swift`. Expected: `error: cannot find type 'WavernApp'` or no `@main`. Confirm no errors in MenuView itself.

- [ ] **Step 3: Commit**

  ```bash
  git add Sources/Wavern/MenuView.swift
  git commit -m "feat: full redesigned MenuView with frosted glass, album art, waveform, browser tab enrichment"
  ```

### Task 6: WavernApp entry point

**Files:**
- Create: `Sources/Wavern/WavernApp.swift`

- [ ] **Step 1: Create WavernApp.swift**

  Create `Sources/Wavern/WavernApp.swift`:

  ```swift
  import AppKit
  import SwiftUI

  @main
  struct WavernApp: App {
      @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
      @StateObject private var controller = AudioProcessController.shared

      var body: some Scene {
          MenuBarExtra {
              MenuView()
                  .environmentObject(controller)
                  .environmentObject(controller.browserTabStore)
          } label: {
              if controller.playing.isEmpty {
                  Image(systemName: "speaker.wave.2.fill")
              } else {
                  Image(systemName: "waveform")
                      .symbolEffect(.variableColor.iterative.reversing, isActive: true)
              }
          }
          .menuBarExtraStyle(.window)
      }
  }

  final class AppDelegate: NSObject, NSApplicationDelegate {
      func applicationDidFinishLaunching(_ notification: Notification) {
          AudioProcessController.shared.start()
          BrowserBridgeInstaller.install()
          // Make the MenuBarExtra panel transparent for vibrancy
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              for window in NSApp.windows {
                  if window is NSPanel {
                      window.backgroundColor = .clear
                      window.isOpaque = false
                  }
              }
          }
      }
  }
  ```

- [ ] **Step 2: Full build — must succeed**

  ```bash
  cd /Users/victor/Documents/estudos/wavern
  xcodegen generate
  xcodebuild -project Wavern.xcodeproj -scheme Wavern \
    -configuration Debug -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -10
  ```

  Expected: `** BUILD SUCCEEDED **`

  If there are errors, fix them before committing.

- [ ] **Step 3: Run and smoke test**

  Build and run in Xcode (⌘R). Verify:
  - Menu bar icon appears (speaker symbol)
  - Opening the menu shows frosted glass background
  - Any playing app shows up with art area, waveform, hover effect
  - Footer has "Launch at login" + "Quit Wavern"

- [ ] **Step 4: Commit**

  ```bash
  git add Sources/Wavern/WavernApp.swift
  git commit -m "feat: WavernApp entry point with animated menu bar icon and transparent panel"
  ```

---

## Phase 3 — Browser Integration

### Task 7: WavernBrowserBridge CLI implementation

**Files:**
- Modify: `Sources/WavernBrowserBridge/main.swift`

- [ ] **Step 1: Implement native messaging host**

  Replace `Sources/WavernBrowserBridge/main.swift` with:

  ```swift
  import Foundation

  // Native Messaging protocol: 4-byte LE uint32 length + UTF-8 JSON body

  let outputDir: URL = {
      let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask).first!
      let dir = appSupport.appendingPathComponent("Wavern")
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      return dir
  }()

  let outputFile = outputDir.appendingPathComponent("browser-tabs.json")

  func readMessage() -> Data? {
      let lengthData = FileHandle.standardInput.readData(ofLength: 4)
      guard lengthData.count == 4 else { return nil }
      let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
      guard length > 0, length < 1_048_576 else { return nil }
      let body = FileHandle.standardInput.readData(ofLength: Int(length))
      guard body.count == Int(length) else { return nil }
      return body
  }

  func writeOutput(_ data: Data) {
      let tmp = outputFile.appendingPathExtension("tmp")
      try? data.write(to: tmp, options: .atomic)
      _ = try? FileManager.default.replaceItemAt(outputFile, withItemAt: tmp)
  }

  while let message = readMessage() {
      guard var dict = (try? JSONSerialization.jsonObject(with: message)) as? [String: Any] else {
          continue
      }
      dict["timestamp"] = Date().timeIntervalSince1970
      if let enriched = try? JSONSerialization.data(withJSONObject: dict) {
          writeOutput(enriched)
      }
  }

  // Chrome disconnected — write empty tabs so Wavern stops showing nudge immediately
  let empty: [String: Any] = ["tabs": [], "timestamp": Date().timeIntervalSince1970]
  if let data = try? JSONSerialization.data(withJSONObject: empty) {
      writeOutput(data)
  }
  ```

- [ ] **Step 2: Build bridge**

  ```bash
  cd /Users/victor/Documents/estudos/wavern
  xcodebuild -project Wavern.xcodeproj -scheme WavernBrowserBridge \
    -configuration Debug -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
  ```

  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Smoke test**

  ```bash
  BRIDGE=$(find ~/Library/Developer/Xcode/DerivedData -name WavernBrowserBridge -type f 2>/dev/null | grep -v dSYM | head -1)
  echo "Bridge: $BRIDGE"
  python3 -c "
  import struct, json, sys
  msg = json.dumps({'tabs': [{'title': 'Test Tab', 'url': 'https://youtube.com', 'favIconUrl': None, 'audible': True}]}).encode()
  sys.stdout.buffer.write(struct.pack('<I', len(msg)) + msg)
  " | "$BRIDGE"
  cat ~/Library/Application\ Support/Wavern/browser-tabs.json
  ```

  Expected: JSON file with `{tabs: [{title: "Test Tab", ...}], timestamp: ...}`.

- [ ] **Step 4: Commit**

  ```bash
  git add Sources/WavernBrowserBridge/main.swift
  git commit -m "feat: WavernBrowserBridge native messaging host"
  ```

### Task 8: Chrome Extension

**Files:**
- Modify: `Sources/BrowserExtension/manifest.json`
- Modify: `Sources/BrowserExtension/background.js`

- [ ] **Step 1: Generate stable extension key pair**

  Run once (save the output — needed for next steps):

  ```bash
  cd /Users/victor/Documents/estudos/wavern
  openssl genrsa 2048 > /tmp/wavern-ext-key.pem 2>/dev/null
  echo "=== PUBLIC KEY (base64 DER) — paste as 'key' in manifest.json ==="
  openssl rsa -in /tmp/wavern-ext-key.pem -pubout -outform DER 2>/dev/null | base64 | tr -d '\n'
  echo ""
  echo "=== EXTENSION ID (32 chars) — paste in BrowserBridgeInstaller.swift ==="
  openssl rsa -in /tmp/wavern-ext-key.pem -pubout -outform DER 2>/dev/null | \
    shasum -a 256 | awk '{print $1}' | head -c 64 | \
    sed 'y/0123456789abcdef/abcdefghijklmnop/' | head -c 32
  echo ""
  ```

  Note both values.

- [ ] **Step 2: Write manifest.json with the generated key**

  Replace `Sources/BrowserExtension/manifest.json` (use the base64 public key from Step 1):

  ```json
  {
    "manifest_version": 3,
    "name": "Wavern Tab Bridge",
    "version": "1.0",
    "description": "Reports audible tabs to Wavern for richer audio mixing.",
    "key": "REPLACE_WITH_BASE64_PUBKEY_FROM_STEP1",
    "permissions": ["tabs", "nativeMessaging"],
    "background": {
      "service_worker": "background.js"
    }
  }
  ```

- [ ] **Step 3: Write background.js**

  Replace `Sources/BrowserExtension/background.js`:

  ```javascript
  'use strict';

  const HOST_NAME = 'com.wavern.browserbridge';
  let port = null;

  function connect() {
    try {
      port = chrome.runtime.connectNative(HOST_NAME);
      port.onDisconnect.addListener(() => {
        port = null;
        setTimeout(connect, 5000);
      });
    } catch (e) {
      port = null;
    }
  }

  function sendAudibleTabs() {
    if (!port) return;
    chrome.tabs.query({ audible: true }, (tabs) => {
      if (chrome.runtime.lastError || !port) return;
      const payload = {
        tabs: tabs.map(t => ({
          title: t.title || '',
          url: t.url || '',
          favIconUrl: t.favIconUrl || null,
          audible: t.audible || false
        }))
      };
      try { port.postMessage(payload); } catch (_) {}
    });
  }

  connect();
  setInterval(sendAudibleTabs, 2000);
  chrome.tabs.onUpdated.addListener((_id, change) => {
    if (change.audible !== undefined) sendAudibleTabs();
  });
  chrome.tabs.onRemoved.addListener(sendAudibleTabs);
  ```

- [ ] **Step 4: Update BrowserBridgeInstaller with real extension ID**

  In `Sources/Wavern/BrowserBridgeInstaller.swift`, replace `"PENDING_EXTENSION_ID"` with the 32-character ID from Step 1.

- [ ] **Step 5: Final build**

  ```bash
  cd /Users/victor/Documents/estudos/wavern
  xcodegen generate
  xcodebuild -project Wavern.xcodeproj -scheme Wavern \
    -configuration Debug -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
  ```

  Expected: `** BUILD SUCCEEDED **`

  Verify extension bundled:
  ```bash
  find ~/Library/Developer/Xcode/DerivedData -path "*/Wavern.app/Contents/Resources/BrowserExtension*" 2>/dev/null | head -5
  ```

- [ ] **Step 6: End-to-end test**

  1. Copy built `Wavern.app` to `/Applications`, ad-hoc sign it:
     ```bash
     APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Wavern.app" -type d | grep -v dSYM | head -1)
     cp -R "$APP" /Applications/
     codesign --force --deep --sign - \
       --entitlements Sources/Wavern/Wavern.entitlements /Applications/Wavern.app
     /Applications/Wavern.app/Contents/MacOS/Wavern &
     ```
  2. Open Chrome → YouTube → play a video.
  3. Open Wavern menu → Chrome row shows "Install browser extension for tab names →".
  4. Click → onboarding sheet with path. Copy path.
  5. Chrome: `chrome://extensions` → Developer Mode → Load unpacked → paste path.
  6. Reopen Wavern menu → Chrome row shows YouTube video title.

- [ ] **Step 7: Commit**

  ```bash
  git add Sources/BrowserExtension/ Sources/Wavern/BrowserBridgeInstaller.swift
  git commit -m "feat: Chrome extension + native messaging host registration with stable extension ID"
  ```
