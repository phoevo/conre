# Conre — Phase 2

Native macOS working-memory companion with approved foreground-app and focused-window-title awareness. SwiftUI with AppKit; macOS 26.5 minimum, Xcode 26.6.

## Run and permissions

Open `conre.xcodeproj`, select **conre → My Mac**, and run with **⌘R**. Conre starts with only its background-free icon and status text beside the notch. Click it to open the app. Closing the main window keeps observation running. Appearance provides saved icon/text colors.

In **App awareness**, approve individual running applications. Click **Allow window metadata…**, then enable Conre in **System Settings → Privacy & Security → Accessibility**. Permission changes are checked every two seconds. Without permission, foreground app identity continues to work and window titles report unavailable. Conre does not prompt automatically at launch.

Switch between approved apps or change the focused window/title to generate raw records. Polling runs every two seconds, so brief intermediate changes may be missed. Apps that don't expose window titles produce an unavailable status. Pause/resume and approval revocation stop future collection; existing history remains until cleared. Sleep suspends observation.

## Security scope

With explicit user authorization, **App Sandbox is disabled in Debug and Release** for this local/direct-distribution build so Accessibility can read focused-window titles. The deployment target, signing settings, and build-script sandbox remain unchanged. No temporary exceptions or extra entitlements were introduced. This configuration is not the sandboxed Mac App Store distribution.

Accessibility grants broader OS capabilities than this implementation uses. Conre only reads focused-window/title attributes for approved foreground applications, with bounded AX messaging timeouts. It rechecks the foreground application and trust before storing a title. The app approval list is enforced by Conre, not by macOS. Revoke Accessibility permission in System Settings to stop window-title access.

Accessibility text capture remains the default. Optional per-app window-only visual fallback and on-device OCR are described below. No audio, input hooks, UI control actions, AI, BYOK, or network operations are implemented. Window titles may contain sensitive information; all observations remain local.

## Storage and migration

Raw records live in `~/Library/Application Support/Conre/raw-observations.json`, separately from the working-memory timeline in `working-memory.json`. Raw records contain timestamp, application name, bundle ID, PID, and available focused-window title/status. The newest 5,000 change records are retained. The timeline still contains explicitly labeled mock Syndeo events, seeded once.

On the first non-sandboxed launch, missing history files are copied from the old `~/Library/Containers/phoevo.conre/Data/Library/Application Support/Conre` directory. Missing preferences (approvals, pause, colors) are copied from the previous container preferences. Existing destination data is never overwritten, and original sandbox files are retained. Migration failures appear in the main UI and are retried on a later launch.

JSON writes are atomic. Unreadable history files are preserved, with a warning and in-memory use rather than overwriting them. Persistence remains synchronous for this small local prototype.

## Architecture

- `Models`: working-memory events and threads.
- `Memory`: working-memory store, JSON persistence, and one-time sandbox storage migration.
- `Observation`: app allowlist, permission-aware foreground/window collector, and separate raw log.
- `Views`: mock timeline, app approvals/raw log, floating status, and appearance controls.
- `conreApp.swift`: app lifecycle and on-demand main window.

Future interpretation can turn raw observations into meaningful timeline events without coupling observation to AI or changing existing mock history.

## Validation

Run unit tests with **⌘U**. Coverage includes timeline persistence and ordering, one-time mock seeding, app approvals/pause persistence, raw-log reload/clear/corruption handling, and migration without overwriting current data or removing originals.

Manual checks: launch, grant Accessibility, approve one app, switch windows/tabs within it, and verify titles in the raw log. Switch to an unapproved app and confirm no records; pause/resume, revoke Accessibility, revoke app approval, and relaunch. Check unavailable states for apps without titles. Live permission grants and title collection require manual verification in the running signed app.


## Recent work and intent

The default **Recent work** tab groups consecutive observations into app visits, listing window titles in order. Durations are approximate approved foreground time, not attention or user-action detection. Pause, unapproved apps, sleep, approval changes, and shutdown end a visit. Restart never fills an unobserved gap. Legacy raw records show unknown durations. The last confirmed duration is saved about every ten seconds and at session boundaries; an unexpected quit can lose the last few seconds.

The main window uses a persistent top navigation bar. Recent work requires no manual notes: it automatically shows observed app/window sessions. Manual intent input has been removed and new observations are no longer tagged with a saved intent. Previously recorded notes remain visible on their historical sessions. The raw log remains separate from the mock working-memory timeline, and clearing it also clears Recent work. The waiting status uses a spinner; Reduce Motion uses a static symbol instead. Existing permissions and collection scope are unchanged.


## Screenshot-free detailed context experiment

Open **App awareness → Detailed context…**. Enable text capture separately for each already-approved app. No app is opted in automatically, and revoking app approval also removes detailed-context approval. Pause, sleep, and leaving an approved app stop capture; clearing context cancels any pending result before deleting history. Disabling capture retains prior snapshots, which can be deleted in the inspector.

The reader runs off the UI thread. It prioritizes the focused element, then inspects the focused window's Accessibility tree. App/window changes trigger an attempt; otherwise attempts occur at most every eight seconds. Captures are partial, not guaranteed complete or limited strictly to visible pixels: Accessibility sometimes exposes offscreen text. Snapshots are deduplicated locally and record their source app, window title, timestamp, and extraction status. Nothing is interpreted as an action or sent to AI.

Limits: up to three seconds for root discovery, then two seconds for text extraction (plus bounded in-flight calls), 160 extraction nodes, depth 32, 120 children per node, and 6,000 stored characters. Recognized secure fields, text-input fields, and combo boxes are excluded; text areas use a bounded visible-character-range request instead of reading entire document values. Apps that expose private content through ordinary static text cannot be perfectly filtered. Treat captured context as potentially sensitive. Textless apps show explicit unavailable/partial results, rather than guessed content.

Only changed snapshots are stored, retaining the newest 300 in `~/Library/Application Support/Conre/context.json`, separately from raw activity and the mock timeline. Corrupt history is preserved with an inspector warning and session-only capture. Foreground app, app approvals, window title, and Accessibility trust are checked again before saving a result; stale or cancelled results are discarded.

Manual evaluation: opt in ChatGPT, your browser, and your editor individually. Use the ordinary debugging workflow, then inspect the saved text in each disclosure row. Check whether the actual problem statement, Appwrite page labels, and editor snippets appear. This measures available evidence; it does not yet reconstruct goals, extract exact editor edits/functions, import chat histories, or summarize your work. Those depend on observed coverage and later integrations/interpretation.


### Browser content filtering

Known Safari, Chrome, Firefox, Edge, Brave, Vivaldi, Arc, and Opera bundle identifiers use a page-only capture path. The reader searches for an exposed `AXWebArea` within the focused window, preferring a page containing the focused element. Toolbars, menus, bookmark bars, and address-field suggestions are excluded from the search and extraction. No page root means an explicit unavailable result, not a fallback to browser chrome. Support depends on the browser actually exposing its page Accessibility tree; generic or unknown browser variants still require validation. Existing snapshots are retained; use **Delete context** to remove earlier toolbar/bookmark captures.


### Body-text capture quality

Title-only and control-only results are now reported as **No body text captured**, with the number of inspected elements and whether a traversal limit was reached. Window titles are not treated as evidence of a conversation. Extraction uses exposed `AXChildren`; a non-empty but incomplete `AXVisibleChildren` list no longer hides sibling content, and static text can use its accessible description when no title/value is available. Read-only text areas without visible-range support may use a bounded stored excerpt of their exposed value, only after Accessibility confirms the value is not settable. Editable fields/composers remain excluded. This improves extraction coverage but does not establish that a particular app exposes its conversations; live app validation is still required.


### Deferred app Accessibility support

Some Electron/Chromium apps expose only a small native shell until a reader requests their renderer's Accessibility tree. For a known supported app that is foreground, approved, and opted into Detailed context, Conre now attempts the documented `AXManualAccessibility` (Electron) or `AXEnhancedUserInterface` (Chromium) support flag before its first capture for that process. This enables app text exposure, not macOS permission; existing Accessibility permission is still required. Unsupported requests do not bypass missing data. The app may need another capture interval to populate its tree.

This is the only app-attribute write: Conre does not click controls, change document/form values, or type. The support mode may remain enabled in the target app until it exits; Conre does not force it off because another assistive tool may need it. Collection still stops on pause, revocation, app changes, or disabling Detailed context. A support request is not evidence that conversation content is readable; validate actual saved body text after rebuilding.

References: https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md and https://www.chromium.org/developers/design-documents/accessibility/ .


### Capture failure diagnostics

Empty captures now include request counts, Accessibility error-code counts, and role-query counts. Browser root discovery distinguishes timeout from no exposed page root. These diagnostics contain no document text and help separate unsupported attributes, missing permissions, sparse trees, and traversal timeouts. The body scan avoids repeated role requests. Live Chrome inspection confirmed an exposed Appwrite web area, but Conre-specific extraction still requires validation after rebuilding; unit tests do not establish live app coverage.


### Conversation region selection

Live Chrome inspection confirmed that ChatGPT's web page exposes message text under a group labelled **Conversation**, separately from its chat-history sidebar. Browser capture now searches within the active web area for a focused/semantic Conversation or main-content region before extracting text. This avoids spending the text budget on the chat-history sidebar. If none exists, capture uses the existing page root. Focus outside the page cannot select a content region from another page/window. Depth and child limits now contribute to the partial-capture status rather than silently stopping traversal. These changes address the browser path; native ChatGPT capture remains unverified.


## Optional window-only visual fallback

If an opted-in app returns no usable Accessibility body text, its floating status shows a red exclamation icon and **Context not gathered**. Click it to open Detailed context with the affected app first. Enable **Window-only visual fallback** separately for that app, then use **Allow Screen Recording for window-only capture…** to request macOS permission. Return to the source app to retry; macOS may require a Conre relaunch after granting permission. Both app approval and Detailed context approval remain required. Removing either also removes visual approval.

Accessibility is always attempted first. Only an empty result, explicit per-app visual approval, Accessibility permission, and Screen Recording permission permit the visual path. A recognized focused secure field skips fallback. ScreenCaptureKit is configured with `desktopIndependentWindow` for one uniquely matched, onscreen foreground window. There is no display-wide capture fallback and no audio. The target is matched by PID and exact window ID when available, otherwise by matching bounds and title with exactly one candidate. Ambiguous/missing targets are skipped. Current foreground app, window, permission, pause state, and cancellation generation are rechecked before capture/OCR and before saving.

A temporary in-memory CGImage is processed with on-device Vision OCR. Conre does not write image files or retain a screen recording. Up to 6,000 characters of OCR text are saved in the same bounded local context history, labelled **Window-only OCR**; old snapshots decode without a source label. OCR is imperfect and can include navigation text, sensitive content, or misread code. Visual capture cannot reliably omit individual fields; secure-field checks are best-effort and images may contain anything visible in the chosen window. macOS grants Screen Recording more broadly than Conre's per-window application rules.

Turning off visual fallback, pausing, leaving the app, revoking permissions, or deleting context cancels/discards pending results. The no-context warning clears after usable text is saved, and uses red independently of normal custom status colors. Unit tests cover authorization gates, matching, legacy decoding, and local OCR on a generated test image. Real ScreenCaptureKit capture and the permission UI still need manual validation in the signed running app. No screenshots of user content were taken during automated verification.


## Context efficiency

New capture attempts adapt from 12 to 24, 48, then 60 seconds when results stay unchanged or nearly identical. New app/window context and permission/approval changes reset the schedule; distinct context resets it to 12 seconds. Basic foreground metadata still uses the existing two-second check. No input hooks or new permissions are introduced. Stable-window content changes may take up to a minute to detect, and brief changes may be missed.

Visual fallback compares a temporary 64×40 grayscale fingerprint before OCR. Near-unchanged images reuse cached extracted text for up to 60 seconds, then OCR is refreshed. Only the small fingerprint and text are retained in memory; images remain unsaved. This still requires capturing a window image for comparison, but avoids repeated expensive OCR for near-identical views.

Before storage, OCR text receives conservative exact-line removal of common control labels. Code-shaped text is kept intact. Exact repeated context is consolidated per app/window/source within a ten-minute span, including repeated empty diagnostics. Near-identical non-code OCR text can be coalesced for up to two minutes, retaining the latest wording, first timestamp, last-seen time, and sample count. Numeric changes, code-shaped changes, and Accessibility text changes are kept distinct. Small OCR-only prose changes can be consolidated; this is a storage tradeoff, not a guarantee that every edit is preserved.

Repeated samples update history in memory, with count/last-seen changes saved at most once per minute or on orderly termination, instead of rewriting JSON every poll. New distinct context is saved immediately. Future appends enforce 300 records and a 500,000-character text budget. Historical records are not bulk-rewritten or compacted on launch. The inspector shows consolidated sample counts and last-seen spans. No AI is connected, so there are currently no AI token costs; future retrieval should use the reduced context rather than all raw captures.

Automated tests validate repetition reduction, preservation of small code/numeric changes, adaptive delays, and image-change gating. CPU/battery improvements have not yet been measured on a live workload.
