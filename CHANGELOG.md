# Changelog

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
