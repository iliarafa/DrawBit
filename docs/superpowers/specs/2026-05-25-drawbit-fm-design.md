# DrawBit FM — looping audio player

**Date:** 2026-05-25
**Status:** Implemented on branch `drawbit-fm`
**Scope:** `DrawBit/Audio/`, `DrawBit/State/RadioController.swift`, `DrawBit/Views/Gallery/RadioStrip.swift`, `DrawBit/DrawBitApp.swift`, `DrawBit/Views/Gallery/GalleryView.swift`, `project.yml`. No SwiftData / model changes.

## Why

DrawBit had no audio. "DrawBit FM" is a curated lo-fi station that loops while the user browses and draws — polish for the app's vibe.

## Decisions

- **Placement:** a persistent player strip in the **Gallery**, under the `GALLERY` header, above the piece grid (`GalleryView` `VStack`, between `topBar` and the `ScrollView`).
- **Tracks: bundled station.** The developer drops `.m4a`/`.mp3` files into `DrawBit/Resources/Audio/`; they ship with the build. No runtime import, no persistence of audio. Discovery: `BundledTracks.load` enumerates the bundle (tries the `Audio` subdirectory, falls back to the flattened root — xcodegen flattens resources), numeric-aware filename sort, filename→title prettifier.
- **Loop: playlist radio.** `Playlist` is a pure value type with empty-safe, wraparound `next/previous/advance`. A track ending calls `advance()` (loops to the first after the last). A single track replays.
- **Controls:** play/pause, prev, next, current title, draggable progress/scrub bar. No volume slider.
- **App-global audio.** `RadioController` is owned as `@State` in `DrawBitApp` and injected via `.environment`, so playback survives Gallery↔Editor navigation and the background.
- **Audio session:** `.playback` (plays over the silent switch; **interrupts other apps' audio** — intended for a station), activated lazily on first play. Handles interruptions (pause/resume) and route changes (pause on headphone removal).
- **Background + lock screen:** `UIBackgroundModes: [audio]` (in `project.yml` `info.properties`). `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` (play/pause/next/prev/seek) give lock-screen / Control Center transport everywhere, so the UI only needs to live in the gallery.

## Architecture

Pure sequencing (`DrawBit/Audio/Playlist.swift`, `AudioTrack.swift`, `BundledTracks.swift` — Foundation only, unit-tested) is separated from the AVFoundation engine (`DrawBit/State/RadioController.swift`, `@MainActor @Observable`, the only file importing AVFoundation/MediaPlayer). The controller mirrors `PlaybackController`'s timer discipline (main run loop, `.common` mode, invalidate on stop/deinit) and uses a small `NSObject` `PlayerDelegate` shim for `AVAudioPlayerDelegate` (the `@Observable` class doesn't conform itself). The scrub bar is a custom pixel-styled control (`GeometryReader` + `DragGesture`), seeking on release.

## Empty-station behavior

The app builds and runs with **zero** audio files: `hasTracks == false`, the strip shows a dimmed `NO STATION` state, no audio session is activated, no Now Playing entry, no crash. Adding files to `Resources/Audio/` + regenerating the project lights it up.

## Verification

- **Unit:** `PlaylistTests` (wraparound/empty/single/select), `BundledTracksTests` (prettify/sort/empty).
- **UI:** `RadioStripUITests` asserts the strip + transport controls are present in the gallery (no real-audio assertions).
- **Manual smoke (after adding ~3 clips to `Resources/Audio/`, `rm -rf DrawBit.xcodeproj && xcodegen generate`, run):** play starts + title shows; track-end auto-advances and loops; next/prev wrap; scrub jumps and resumes; audio continues into the Editor; backgrounded/locked playback continues with working lock-screen transport; phone-call interruption pauses then resumes; headphone unplug pauses.
