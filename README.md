# Conre

A native macOS working-memory companion. Requires macOS 26.5 and Xcode 26.6. Captured history is stored locally. Automatic AI summaries send a bounded selection of approved-app text to OpenAI using your saved API key; disable them in Advanced or Summary options. Manual previews remain available. No audio capture is implemented.

## Run

Open `conre.xcodeproj`, select **conre → My Mac**, and run. Conre starts as a notch-adjacent status pill. Click it to open the app; closing the window keeps observation running. Pause and resume from the app UI. Appearance configures icon, text, ring, and background colors, including opacity.

Keep the existing Apple Development signing team and bundle identifier when rebuilding. A stable signing identity helps macOS recognize the same app; signing changes or OS permission behavior can still require permission review. Do not reset permissions as a routine build step.

## Apps and permissions

In **Apps**, choose a capture mode for each app:

- **Off**: no new collection.
- **App activity**: foreground app and available window metadata.
- **Detailed text**: also reads text exposed through Accessibility.
- **Text + visual fallback**: separately opts into temporary window-only capture and on-device OCR when Accessibility returns no usable body text.

Accessibility permission enables window metadata and detailed text. Visual fallback also requires Screen Recording permission. Conre shows relevant permission actions without requesting access automatically at launch. Return to the source app after granting access; macOS may require relaunch after Screen Recording changes. Approvals are enforced by Conre; macOS permissions are broader than its per-app rules.

App Sandbox is already disabled with explicit user authorization for this local/direct-distribution build. This polish preserves signing, deployment target, and sandbox settings.

## Recent work

Recent work is a minimal, expandable activity tree with a short overview. New captured text appears beneath it until the next AI update. Expand a step to see its supporting observations. New text is not proof of an edit: scrolling, layout changes, and OCR corrections also change visible text.

Automatic summaries are enabled for this user-requested mode. They use the saved OpenAI key, only for apps currently approved for detailed text. A meaningful batch waits 25 seconds after its last change; sustained changes can trigger an update after three minutes. Small useful batches flush at idle/return or after waiting. Repeated captures and tiny changes do not trigger requests. A minimum two-minute cooldown, 12 automatic requests per rolling hour, and ten-minute error backoff limit background work. Cooldown/history survive restarts. These are request limits, not a dollar spending cap; OpenAI charges apply.

After three minutes without input, returning briefly expands the notch-adjacent pill with the last work recap. Sleep and session return also participate. The recap shows one AI sentence and its observation time; if no suitable summary is ready, a labeled last-window fallback appears. It dismisses after 18 seconds, with a close button and click-through to the tree. The compact pill otherwise shows current activity or summary progress. No input content is recorded by idle detection.

Pause in Recent work stops observation and automatic generation. The ellipsis opens Summary options, including the automatic toggle and the manual preview/API-key flow. Advanced contains the same controls, capture health, and diagnostics. Manual summaries can cover 15 minutes, one hour, or four hours; automatic summaries use a bounded hour of context. New automatic requests use only currently approved detailed-text apps, not revoked app history.

## Capture quality and limits

Known browsers search the active page Accessibility tree, preferring conversation/main-content regions over navigation. Known editors prioritize a focused editor text area belonging to the active window. Useful body text is stored separately from interface controls. Unknown or sparse Accessibility trees can still provide little or no content.

Accessibility traversal has bounded time, depth, node, and text budgets (6,000 stored characters per capture). Editable/secure fields are excluded where identifiable. Accessibility can expose offscreen text, so capture is not a strict visible-pixel boundary. Supported Electron/Chromium apps may receive an Accessibility-support flag; Conre does not type, click, or edit their content.

Visual fallback requires explicit per-app approval and a uniquely matched foreground window. There is no display-wide fallback. A temporary image is processed by Vision OCR and discarded; images and recordings are not saved. OCR can contain sensitive content and misread code. A conservative reading-column filter removes obvious sidebar/top controls only when several substantial lines support the layout; ambiguous layouts retain the evidence. Secure-field protection is best effort.

Foreground app, permissions, approvals, pause, cancellation, and window identity are rechecked before accepting results. Capture is partial evidence, not a guarantee of complete activity or conversation history.

## Efficiency and storage

Metadata checks occur every two seconds. Stable context backs off capture attempts from 12 to 24, 48, then 60 seconds. App/window changes reset the schedule. A temporary grayscale fingerprint can reuse recent OCR text for near-identical windows for up to 60 seconds. Window capture is still needed to compare fingerprints.

Repeated context is consolidated locally. Conservative near-identical OCR prose merging preserves code-shaped and numeric changes. New context is saved immediately; repeat metadata is checkpointed at most once per minute. App-visit duration checkpoints occur about every 30 seconds and at session boundaries. An unexpected quit can lose the latest uncheckpointed duration/repeat updates.

Local files in `~/Library/Application Support/Conre/`:

- `context.json`: newest 300 context records, with a 500,000-character budget applied on append.
- `raw-observations.json`: newest 5,000 app/window records.
- `working-memory.json`: original, explicitly labeled sample timeline.
- `activity-summary.json`: most recently generated summary/tree plus its supporting excerpts. This persists independently of captured context; use Clear saved summary to remove it.

History files use atomic JSON writes. Corrupt files are preserved with a visible warning and session-only operation. Existing historical captures are not bulk rewritten by this update. First non-sandboxed migration copies missing files/preferences from the old container without overwriting current data or removing originals.

## Advanced

Advanced contains saved-context inspection, expandable raw observations, and the clearly labeled original mock Syndeo timeline. Per-run counters show completed capture attempts, elapsed capture duration, OCR runs/reuse, history write count/bytes, and consolidated repeats. Elapsed capture time is not CPU time; counters exclude cancelled attempts and OS-internal writes.

## Validation

Run unit tests with **⌘U**. The polish build passed all 44 tests with the existing signing configuration. Coverage includes context deltas, health states, filtering, editor ownership, capture-mode authorization, metrics, and existing persistence/permission gates. See `docs/Polish-validation.md` for measurements and verification limits.

Live app coverage varies by app and version. Validate actual saved text in Advanced rather than assuming a successful permission grant means content is available.

## AI summaries and evidence trees

The API key is stored in the macOS login Keychain, not preferences or history. Save/replace/remove it from the summary preview. Requests go only to `https://api.openai.com/v1/responses`; redirects are refused. Networking uses an ephemeral session, bounded responses, and timeouts. Failed automatic updates wait at least ten minutes before another attempt; manual requests remain explicit. Cancelling stops the local request/result; an already submitted request may still incur API charges.

The input keeps the beginning of the selected period and recent changes: up to 12 observations and 9,000 body-text characters, with bounded app/window names. It includes app names, window titles, observation timestamps, source labels, and evidence IDs. No images or entire raw-history files are uploaded. The preview shows all selected excerpts; data may be sensitive. `store: false` disables stored Responses state but is not a promise of zero provider retention; OpenAI data policies apply.

Structured output is validated for one sentence, unique node IDs, cited evidence IDs, parent ordering, and a maximum of 12 nodes/three levels. Captured text is treated as untrusted data in the prompt. These checks do not establish factual accuracy or defeat every prompt injection; review the supporting observations. Page visits do not prove installs or edits, and missing context cannot reliably reveal intent.

Only the latest generated result is saved. Regeneration replaces it after success; a failed/cancelled request preserves the previous result. Clearing source context does not delete saved summary excerpts. Corrupt saved-summary files are preserved and new results remain in memory.

Signed build and 53 unit tests passed for this feature, including fake-transport API responses, refusal/limits, evidence validation, persistence, and cancellation. No real OpenAI request or user key was used during validation, so live account access and summary quality still need evaluation. See `docs/AI-summary-validation.md`.

## Automatic-summary validation

Signed regression tests cover batching, settling, repetition/noise suppression, cooldown, hourly limits, error backoff, removal of eligible history, preservation of changes arriving during a request, idle/sleep return, and full background coordination using a fake AI service. A separate synthetic UI preview verifies the minimal tree without collecting real activity or accessing the production API key. See `docs/Automatic-summary-validation.md` for limits.

### Return reminder colors

Appearance → Return reminder provides separate heading/icon, summary text, timestamp, summary-background, reminder-background, and ring colors, with opacity for backgrounds/ring. Defaults use green labels and timestamp, white summary text, and a subtly shaded summary card over a dark reminder. A shared live preview uses the actual reminder layout. Settings persist independently of compact-pill colors; Reset reminder colors restores only reminder defaults. The signed build passed and the customization controls and expanded reminder were visually verified with synthetic text.
