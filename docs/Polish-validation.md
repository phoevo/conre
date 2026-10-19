# Conre polish validation

Validated 2026-10-19 using the existing macOS deployment target and Apple Development signing configuration.

## Delivered

1. Recent work defaults to line changes against the previous app/window capture, with full evidence available on expansion. Removed lines are counted; no edits or goals are inferred.
2. Useful Accessibility body text excludes appended interface controls; known editors prioritize their focused editor region. OCR uses conservative layout filtering with an ambiguous-layout fallback.
3. Capture health and last useful capture are visible. Partial context does not trigger a missing-context failure.
4. Apps combines per-app collection into Off, App activity, Detailed text, and Text + visual fallback. Existing approvals are preserved; visual capture remains explicit opt-in.
5. Per-run capture duration, OCR reuse, successful history writes/bytes, and repetition counters are available. Sandbox-state lookup is cached and app-duration disk checkpoints are reduced to every 30 seconds.
6. Raw observations, technical diagnostics, and the explicitly labeled sample timeline are under Advanced. Top navigation remains available.

## Automated checks

- Signed Debug build succeeded using the normal Xcode DerivedData path.
- All **44 Swift Testing tests passed** in the signed test build.
- Synthetic context-change projection: 200 records, 51 lines each, 10 iterations, average **8.67 ms**. This measures projection only, not capture, OCR, rendering, or whole-app performance.
- Existing signing and project settings were preserved by this polish. No commit or push was made.

## Live interface checks

Restarted the normal-path signed app and verified the status pill opens the main window. Verified Recent work defaults to Context changes, the full top navigation remains present, capture health reports partial context and last useful text, and Apps shows the existing per-app modes and permission readiness.

The computer-use connection closed during the Advanced inspection. Its visual layout was not verified. No permissions were granted or reset during this verification. Automated checks do not prove live capture coverage for every third-party app.

## Process measurements

Two 30-second observational samples used cumulative process CPU time and resident memory:

| Sample | CPU time / elapsed | Average one-core utilization | Resident memory |
| --- | --- | --- | --- |
| Before polish | 5.43 s / 30.05 s | about 18.1% | 72–114 MiB |
| After restart with polish | 3.52 s / 30.06 s | about 11.7% | 24–33 MiB |

The samples used different live workloads and process ages. They are **not a controlled before/after benchmark** and do not establish CPU, memory, or battery improvement. The post-change app was freshly restarted following interface inspection; the earlier process had a longer running history. No battery-life result is claimed.

The new in-app counters report completed accepted attempts and application history writes, not CPU consumption or all OS disk activity. A future controlled run should use the same app, window content, scrolling sequence, duration, and warm-up, comparing OCR and Accessibility separately.

## Remaining limits

Capture is bounded, app-dependent evidence. Scrolling and OCR corrections can appear as text changes. Geometry filtering may retain UI noise or omit a relevant line; ambiguous layouts retain all lines. Context changes are a presentation over stored snapshots, not a new semantic summary or a complete activity recording. Historical data is retained and not bulk rewritten. No AI or network integration was added.
