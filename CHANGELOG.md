# Changelog

## [1.6.0](https://github.com/VictorMCavalcante/Wavern/compare/v1.5.1...v1.6.0) (2026-11-26)


### Features

* **brand:** Wavern app icon, menu bar glyph and brand kit ([9542ee7](https://github.com/VictorMCavalcante/Wavern/commit/9542ee77fdd4c41b95aacb7cb835768ab896ca7f))
* read per-browser tab files and write volumes to the owner's file ([b650d2b](https://github.com/VictorMCavalcante/Wavern/commit/b650d2b9f3ce43b235e41d844ee882e8ad21740f))
* **recovery:** pause idle taps so quiet apps cost no IO ([07cf188](https://github.com/VictorMCavalcante/Wavern/commit/07cf18860c1e63df8a30c596ff01128e1fdf186e))
* **recovery:** pure watchdog verdict and device-change classification ([c09aab3](https://github.com/VictorMCavalcante/Wavern/commit/c09aab3197ada57b775c70700b264ee7d193c0ff))
* **recovery:** watchdog rebuilds dead taps; give up keeps muted apps muted ([9cd466e](https://github.com/VictorMCavalcante/Wavern/commit/9cd466ebbb1d0f3bba5b3add517da19b052ab5b5))
* stability rework, CrispShot panel, Sparkle updates ([31962de](https://github.com/VictorMCavalcante/Wavern/commit/31962ded5788888ca87cb23e53d9a50dbbda1c2a))
* **ui:** CrispShot-style panel content with chips, focus tile and lilac sliders ([34986e9](https://github.com/VictorMCavalcante/Wavern/commit/34986e9b36839dd33e1bcc3dae5e04aa71e084e3))
* **ui:** custom status panel with CrispShot theme; no rendering while closed ([3a5703b](https://github.com/VictorMCavalcante/Wavern/commit/3a5703bdf81cbc567ddbe7117b3f6a98014765cc))
* **updates:** replace the hand-rolled updater with Sparkle; Developer ID-ready CI ([93d237b](https://github.com/VictorMCavalcante/Wavern/commit/93d237b45db0427bf42b78e9b7c4552ff3f028b1))


### Bug Fixes

* attribute WebKit GPU process audio to the hosting app ([ad996f6](https://github.com/VictorMCavalcante/Wavern/commit/ad996f6d54a51590a844169124dc7e3c84fbe81c))
* **ducking:** duck only while a call app is using the microphone ([747ca93](https://github.com/VictorMCavalcante/Wavern/commit/747ca93c6e9f829a60d9d206a07f88dc6b882823))
* **ducking:** poll ducker mic state while ducking is on ([aa0d9aa](https://github.com/VictorMCavalcante/Wavern/commit/aa0d9aa8e70da78a91b014c68bc3665e11cd6aa5))
* **recovery:** keep output device listeners when pruning vanished processes ([e6866c8](https://github.com/VictorMCavalcante/Wavern/commit/e6866c8446a64b2c03d0e7d59cab4a284aff735b))
* **recovery:** load new profile before rebuild; drop stale ids on coreaudiod restart ([0881bd2](https://github.com/VictorMCavalcante/Wavern/commit/0881bd216367e11321e6653abca70bb753bffb71))
* **recovery:** never leave an app untapped during a rebuild; muted stays muted on failed activation ([9d5dcc2](https://github.com/VictorMCavalcante/Wavern/commit/9d5dcc2d4a346efa593b4e61eccf6ae709dd244a))
* **recovery:** single rebuild path for device, format, wake and coreaudiod restart ([c144749](https://github.com/VictorMCavalcante/Wavern/commit/c144749325e9fe8b8de48707f8926f67deb2952e))
* **recovery:** targeted watchdog rebuilds, no doubled audio, quieter device events ([2df893f](https://github.com/VictorMCavalcante/Wavern/commit/2df893f9b6c7aa9c59e76b95fc3b7a23c4f80581))
* retry keeps mute state, safe readArray, debounced tab writes, apple-events entitlement, safer updater ([8d81fd2](https://github.com/VictorMCavalcante/Wavern/commit/8d81fd2fa4588e33305bc61d722d3ccf13d05d47))
* **settings:** a saved volume of 0 is mute, never a silent unmuted app ([6df1da3](https://github.com/VictorMCavalcante/Wavern/commit/6df1da34f7334a2e5065e607db97b59f1dfd20b5))
* **settings:** unmuting clears a stale saved volume of 0 ([98218c3](https://github.com/VictorMCavalcante/Wavern/commit/98218c3a00f035144f25341cebc6bf5011a12385))
* **tap:** channel-aware render with gain ramp; record IO timestamps; no tap leak on setup error ([56d3323](https://github.com/VictorMCavalcante/Wavern/commit/56d33230c845a52dd0ed843ea8db473fc7d347f8))
* **ui:** cap the tile list height and scroll; close the panel on app switch; name command-line tools ([8317c8c](https://github.com/VictorMCavalcante/Wavern/commit/8317c8cd573724dc2a83bb119335e6e5da643114))
* **ui:** drop stale focused and hovered ids when their tile goes away ([2244111](https://github.com/VictorMCavalcante/Wavern/commit/2244111fe15e79dcb97d4065a9c845873b1848b4))

## [1.5.1](https://github.com/VictorMCavalcante/Wavern/compare/v1.5.0...v1.5.1) (2026-09-04)


### Bug Fixes

* audio silent after rebuild due to missing system-audio permission prompt ([f0b3256](https://github.com/VictorMCavalcante/Wavern/commit/f0b325620f7d508e4749d003529c451e5e013940))

## [1.5.0](https://github.com/VictorMCavalcante/Wavern/compare/v1.4.0...v1.5.0) (2026-09-04)


### Features

* output device picker and master volume slider; decouple HAL listeners ([c4e4f5b](https://github.com/VictorMCavalcante/Wavern/commit/c4e4f5ba1419cb2b228266087e4e1468409b3445))

## [1.4.0](https://github.com/VictorMCavalcante/Wavern/compare/v1.3.2...v1.4.0) (2026-09-03)


### Features

* event-driven detection, ducking, per-device profiles, media keys, per-tab volume ([6445e7e](https://github.com/VictorMCavalcante/Wavern/commit/6445e7e55e48e6802a7f26586eeca59b6e0e553e))

## [1.3.2](https://github.com/VictorMCavalcante/Wavern/compare/v1.3.1...v1.3.2) (2026-09-02)


### Bug Fixes

* inject MARKETING_VERSION from release tag in xcodebuild ([972f9b2](https://github.com/VictorMCavalcante/Wavern/commit/972f9b25434519ae09e1e3a62f2adf8e0c06e7f6))
* use MARKETING_VERSION build var in CFBundleShortVersionString ([3cf129a](https://github.com/VictorMCavalcante/Wavern/commit/3cf129a0114fe847a15093536e86898055c3e093))

## [1.3.1](https://github.com/VictorMCavalcante/Wavern/compare/v1.3.0...v1.3.1) (2026-09-02)


### Bug Fixes

* bundle WavernBrowserBridge into app MacOS dir via dependency and post-build script ([1d69e90](https://github.com/VictorMCavalcante/Wavern/commit/1d69e903547bef81d9d4296340d8837e5579426e))
* set MARKETING_VERSION to 1.2.0 and add release-please annotation ([81d5766](https://github.com/VictorMCavalcante/Wavern/commit/81d57667f1ee7dc7b1a90fd548832b4c4a52e4ff))

## [1.3.0](https://github.com/VictorMCavalcante/Wavern/compare/v1.2.0...v1.3.0) (2026-09-02)


### Features

* auto-install update by downloading DMG and relaunching ([752da7c](https://github.com/VictorMCavalcante/Wavern/commit/752da7cdb0fae6d758232ed4850f17d25627e534))

## [1.2.0](https://github.com/VictorMCavalcante/Wavern/compare/v1.1.2...v1.2.0) (2026-09-02)


### Features

* add GitHub release update checker with menu banner ([b43c487](https://github.com/VictorMCavalcante/Wavern/commit/b43c487fff08e29730f861f6069cef9aa978e71c))

## [1.1.2](https://github.com/VictorMCavalcante/Wavern/compare/v1.1.1...v1.1.2) (2026-09-02)


### Bug Fixes

* include BrowserExtension as folder resource in XcodeGen target ([54b6b71](https://github.com/VictorMCavalcante/Wavern/commit/54b6b7177c6baa0e899146adb2441af408c7d559))

## [1.1.1](https://github.com/VictorMCavalcante/Wavern/compare/v1.1.0...v1.1.1) (2026-09-02)


### Bug Fixes

* add missing AppKit import for NSImage in AudioProcessController ([36fd60c](https://github.com/VictorMCavalcante/Wavern/commit/36fd60c83a349623d613b67140ef7a2f6636c13a))
* replace DispatchQueue.async with Task.detached, fix ShapeStyle accentColor, add NSImage type annotation ([59f2acd](https://github.com/VictorMCavalcante/Wavern/commit/59f2acd7cba894ebfdfa58eb424c1204906679d0))

## [1.1.0](https://github.com/VictorMCavalcante/Wavern/compare/v1.0.0...v1.1.0) (2026-09-02)


### Features

* AudioProcess with chromiumBrowserName, NowPlaying with artwork fields, NowPlayingService ([e5c8484](https://github.com/VictorMCavalcante/Wavern/commit/e5c84845514a371ed63e7e65b7f48ec5a7987911))
* AudioProcessController with persistence, artwork fetch, browser tab integration ([a517c27](https://github.com/VictorMCavalcante/Wavern/commit/a517c27df4dcf162f33755ba0a433b3778cd9cbb))
* full redesigned MenuView with frosted glass, album art, waveform, browser tab enrichment ([f4e3ca0](https://github.com/VictorMCavalcante/Wavern/commit/f4e3ca05b2665ce165cb1dd9120b123e7ba1127c))
* initial release ([efa3620](https://github.com/VictorMCavalcante/Wavern/commit/efa36206818ddf9570074ce4a7c667ae1c70e9b7))
* WaveformView, VisualEffectBackground, BrowserTabStore, BrowserBridgeInstaller ([5455e10](https://github.com/VictorMCavalcante/Wavern/commit/5455e1039864b74dad0c2874cab31aedfbd5798f))
* WavernApp entry point with animated menu bar icon and transparent panel ([4837e25](https://github.com/VictorMCavalcante/Wavern/commit/4837e251f51bc1f5893036b96576c756237ec672))
* WavernBrowserBridge CLI, Chrome extension with stable key, extension ID registered ([b6d66fb](https://github.com/VictorMCavalcante/Wavern/commit/b6d66fbb825c7f320084dea697f8197246953f24))


### Bug Fixes

* NowPlaying optional defaults, ProcessTap bundle IDs ([8aaf6f2](https://github.com/VictorMCavalcante/Wavern/commit/8aaf6f27af0aa41894ce3979fc22446a2023962c))
