# Automatic summaries and return recap

## Behavior

The app delegate now owns the summary coordinator so it keeps running when the main window is closed. A five-second check batches meaningful differences in captured text, waits for 25 seconds of settling or three minutes of accumulated information, and flushes smaller useful batches on idle/return. Exact repeats and tiny token changes do not count. No image-difference AI request loop or input recording was added.

The feature is enabled by default in response to the explicit request for automatic operation. It sends bounded text evidence to OpenAI using the saved key. Only currently approved detailed-text apps are eligible. Settings expose the automatic toggle and cost/data explanation. Background Keychain reads disallow authentication interaction; issues are shown for manual recovery. Two-minute cooldown, 12 automatic calls per rolling hour, and ten-minute error backoff apply; request timestamps and backoff are persisted. These are not a dollar spending cap.

Recent work combines AI tree nodes with newer captured text, with supporting evidence tucked into disclosures. Main capture diagnostics, API setup, manual requests, and limits are available in Summary options/Advanced.

Aggregate idle time triggers an away state after three minutes; input after that or return from sleep/session activity shows an 18-second nonactivating recap. It uses a timestamped existing summary when suitable, or labeled app/window metadata when no suitable AI result exists. A new result can refresh an open recap. The panel expands beneath the menu bar beside the notch, then restores its compact current-action display.

## Verification

All 65 signed Swift Testing regression tests passed. New tests exercise scheduler thresholds, noise/repeats, hourly limits/backoff, overlapping captures, removal of eligible history, idle/sleep return, disabled automation, and a complete coordinator-generated summary/recap with fake AI and synthetic context. Existing summary, Keychain, capture, and persistence tests remain covered.

The minimal tree was inspected in a separately compiled preview using synthetic button/theme examples, an isolated data directory, no observation loop, no real API key, and no network service. The expanded floating recap was also inspected visually with synthetic activity, including its close control, timestamp, and click-through button. Real AI accuracy and costs remain dependent on the account and captured evidence. No production context was deliberately sent during these checks.

## Limits

Activity inference remains partial. The text-change heuristic can include scrolling and miss short or low-information changes; it does not measure every pixel change or prove edits. The tree represents a bounded recent window and can be reorganized by later summaries. Recaps can lag a work change while the next request is pending; timestamps and fallback labels expose this. Aggregate idle can also mean reading or watching rather than being away. Already-submitted requests may still be billed after cancellation.

## Wake recap correction

An unchanged screen does not suppress a return recap. Explicit wake/session-active notifications now trigger a recap directly, even when the aggregate idle counter has not reset or a preceding sleep notification was missed. Duplicate wake signals within 30 seconds are coalesced. The wake-triggered recap stays available until an input event newer than the wake signal; only then does its 18-second dismissal timer begin. A saved summary remains usable after an overnight gap and displays its date when it is from an earlier day.

Regression tests simulate stale idle counters, missing sleep notifications, duplicate wake signals, and overnight reuse of a saved summary. A real lid-close/unlock cycle was not automated. No fresh AI request is required simply to display the saved recap.
