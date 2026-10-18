# Conre — Phase 1

A native macOS working-memory timeline using a clearly labeled Syndeo sample workflow.

## Run

Open `conre.xcodeproj` in Xcode 26.6, select the `conre` scheme and **My Mac**, then Run (Command-R). The existing minimum deployment target is macOS 26.5. Run the Swift Testing suite with Command-U or select `conreTests` in the Test navigator.

## Structure

- `Models`: Codable activity events and work threads, including provenance, confidence, metadata, and parent relationships.
- `Memory`: main-actor observable store and a `MemoryPersistence` boundary. JSON is one implementation; a future SQLite implementation can replace it without involving views or interpretation.
- `Observation`: logical pause/resume intent only. No application observation, capture, accessibility access, or network requests occur.
- `Views`: oldest-to-newest scrollable timeline, initially positioned at the newest event, using native appearance-aware styles.
- `conreApp.swift`: owns the shared store and observation state for the window lifecycle.

Future flow: approved observations → ContextInterpreter → explicit activity events → WorkingMemoryStore → TimelineView. Interpretation must remain independent of persistence; observations must remain independent of views. A future NotchPanelController will host the view through AppKit. Neither future component is implemented in Phase 1.

## Persistence

The sandboxed app writes `Conre/working-memory.json` beneath its Application Support directory. Snapshots are versioned and written atomically. Mock data seeds once only when both events and threads are empty; an explicit seed marker persists across launches. Every sample event has the `mock` source and Syndeo metadata.

Missing data starts a fresh store. Invalid JSON, unsupported versions, and other read failures preserve the existing file, show a visible message, and allow in-memory use without overwriting that file. Write failures also appear in the UI. Recovery/import tools are outside this milestone. Back up or repair an unreadable file before relaunching to resume persistence.

The pause switch changes logical intent for this session only. It does not modify existing history or the work thread status. JSON writes are synchronous on the main actor for this small foundation; larger histories should move persistence and querying off the UI actor.

## Validation

Built with Xcode 26.6 using the existing project configuration, with signing disabled for local verification. Six Swift Testing tests cover insertion, ordering/recent limits, thread associations and active transitions, reloads, one-time mock seeding, missing/corrupt files, and invalid confidence. UI automation and visual appearance verification were not performed.

Next milestone: explicit application approval and transparent foreground-app/window-metadata observation (Phase 2). No screen capture or AI interpretation yet.
