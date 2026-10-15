# Shell Copy

A small macOS menu bar app that reconnects prose wraps on the clipboard. Swift + AppKit, no third-party dependencies or background service. Local rules work offline. Optional Jev (TypeSafe) or bjev (ByteDance) judgment sends eligible copied text to the selected service and requires its own API key.

## Build and launch

Requires macOS 13 or later and an installed Swift 5.9+ toolchain, such as Xcode Command Line Tools.

```sh
bash scripts/check.sh
open "build/Shell Copy.app"
```

`check.sh` runs the tests, builds a release executable for the current Mac's architecture and creates an ad-hoc signed app at `build/Shell Copy.app`. For a build without tests, run `bash scripts/build-app.sh`. Outputs and Swift caches stay in `.build/` and `build/`. No installation or login item is created. The app has a menu bar icon and no Dock icon or main window.

Tests use uniquely named macOS pasteboards and disposable preferences suites. They never read or write the general clipboard. Cloud tests intercept HTTP through `URLProtocol`; they make no live API calls and need no credentials. Clipboard tests need access to the local macOS pasteboard server; an agent sandbox that denies that access must run the acceptance command with authorized sandbox escalation. A missing pasteboard fails acceptance rather than silently skipping tests.

## Use

The menu contains:

- **Automatically Join Wrapped Lines**: checked when enabled. First launch defaults to off; your choice persists across launches. Enabling, or launching with a saved enabled choice, takes the current clipboard as a baseline and leaves it unchanged. Copy new text to process it.
- **Processing Method**: choose **Local Rules (Offline)**, **Jev (Sends Text to TypeSafe)**, or **bjev (Sends Text to bjev (ByteDance))**. New installs default to local rules. Existing Jev users retain their selected mode and key. The selected method persists; switching cancels pending requests and leaves the current copy unchanged. In either AI mode, conservative local rules join recognized wraps first; the selected service judges only remaining candidates. If no candidate remains, no request is sent. Only one service receives a copy.
- **Use Local Rules If AI Fails**: on by default, preserving the existing fallback preference. Failed requests use the conservative local rules and show the provider and failure reason. A successful judgment that chooses no additional joins keeps the local result; it is not reprocessed by local rules afterward.
- **TypeSafe API Key…** and **bjev (ByteDance) API Key…**: paste a key or choose **Import File…** for a UTF-8 file containing just the key. Each service has a separate macOS keychain item. Updating one never replaces the other. Removing the selected service's key switches to local rules. Keys are never stored in preferences, logs, source, or the app bundle.
- A status line names the active provider and shows processing, completion, or failure. HTTP/transport error codes are shown without response bodies or credentials.
- **Restore Original Text**: restores the most recent transformed item's original representations. It is disabled when unavailable.
- **Quit Shell Copy**.

The app polls every 300 ms with 50 ms timer tolerance. Actual latency can be longer when macOS is busy or asleep. Pasting immediately after copying can paste the original text; several copies between polls expose only the last one. Disabled mode never rewrites the clipboard.

### Enable a cloud service

1. Save or import the corresponding key from its **API Key…** menu item.
2. Choose **Processing Method → Jev** or **Processing Method → bjev**, and enable **Automatically Join Wrapped Lines**.
3. Copy new text and wait for the status to finish before pasting. Use **Restore Original Text** if needed.

bjev uses the ByteDance internal service. Obtain its key from the playground's **API Key → Generate new API Key** flow. Generating a replacement invalidates old bjev keys. An optional local backup belongs in `.secrets/` (ignored by version control), with directory mode 700 and file mode 600. The app reads imported keys from the keychain after import, not from the backup file.

For setup without copying a secret to the clipboard or shell arguments:

```sh
"build/Shell Copy.app/Contents/MacOS/ShellCopy" --import-api-key bjev "$PWD/.secrets/bjev-api-key.txt" --select
```

Use `jev` for TypeSafe instead. `--select` selects that provider without changing the automatic-joining or fallback preferences. Restart the app to load changes made through this command. The import does not print the key.

The secure key field supports **Command-V** to paste and **Command-A** to select an existing entry for replacement. The app installs standard Edit menu actions so those shortcuts work in its modal dialog.

When the local rules leave candidate breaks, the selected cloud service adds a network round trip. Requests have a two-second network deadline and responses older than two seconds from the start of processing are discarded. There are no automatic retries. The original text remains available to paste while a request is in flight; the app does not intercept or delay Command-V.

A successful conversion writes plain text. Any admitted HTML/RTF formatting is absent from that converted copy. Restore brings back the exact saved bytes of every original representation. The snapshot is kept only in memory, at most one item and 8 MiB total. It expires on restore, the next external clipboard change, or app exit. Turning automatic mode off does not by itself discard it. Restore also works while automatic mode is off. It never reprocesses its own restored copy. This is an undo for the current conversion, not clipboard history.

Only single items with UTF-8 plain text and optional known plain-text, RTF or HTML representations are admitted. Files, URLs with URL representations, images, attachments, multiple items, concealed markers and unknown app-specific formats are skipped. Plain text larger than 1 MiB and snapshots larger than 8 MiB are skipped. The app does not log or save clipboard contents to disk. Both cloud providers use an ephemeral HTTP session with no response cache or credential/cookie storage, and refuses redirects.

Before rewriting or restoring, the app checks the pasteboard change count and abandons stale work if a newer copy arrived. It also checks after claiming pasteboard ownership. AppKit does not provide atomic compare-and-swap across the check/clear/write calls, so there is still a small unavoidable race with other processes during those calls. A detected later change is left for the next poll.

## What gets joined locally

Each blank-line-separated block must have a long, unindented prose first line, at least 48 approximate display columns and either 12 Chinese characters or eight alphabetic words. Every following line must have the same continuation indentation of at least two ordinary spaces. A prose block with recognizable code, commands, logs, tabs or nested indentation is left alone. List items are handled separately: long prose continuations aligned with the text after a bullet or numbered marker can join within that item. Titles, blank lines, new list items and nested markers keep their boundaries. Leading tab padding is also accepted for Chinese list continuations; internal tabs remain protected. Original list markers, initial indentation and Markdown text are retained. Fenced text makes the whole copy ineligible. Sentence endings and ambiguous boundary punctuation also prevent joining. The two-space minimum covers copied terminal prose with shallow hanging indentation; the other checks still apply.

If a selection begins directly at a list marker, the first line's original padding may be missing while continuation padding remains. For that opening item only, when its content includes Chinese and the first continuation starts with a Chinese character, deeper space indentation is inferred from the first continuation instead of requiring marker alignment. Subsequent space continuations must use that same indentation. The long-prose, sentence-ending and structured-text checks still apply. Later items and items with retained leading spaces keep the strict alignment rule. This is a heuristic: a deliberately indented Chinese paragraph after an unfinished opening list item can look identical in plain text; use Restore Original Text if needed.

Chinese fragments join without an extra space; English words get one separating space. Internal spacing, including column alignment within the first line, remains intact. Blank paragraphs and surviving LF/CRLF line endings remain exact. A no-op never rewrites the clipboard.

Within an eligible prose block or list item, punctuation protects only its own boundary, not the entire block. For example, local mode keeps a newline after a colon but can join later wrapped lines. Untouched boundaries retain their original line endings, trailing spaces and continuation indentation, including accepted list padding.

For example, with 32 spaces before the second line:

```text
useDag=0 直接物化 Hive    临时升级环境下通过，存在交付限制。 7377/429330 成功 11 人；7378/429331 Hive 成功后因 COUNT=0 失败。但依赖临时 Base64 模板和测试 JAR，验收后恢复了原模板，不能算永久启用
                                完成。
```

becomes:

```text
useDag=0 直接物化 Hive    临时升级环境下通过，存在交付限制。 7377/429330 成功 11 人；7378/429331 Hive 成功后因 COUNT=0 失败。但依赖临时 Base64 模板和测试 JAR，验收后恢复了原模板，不能算永久启用完成。
```

The fences above illustrate the clipboard content; copying the fences themselves intentionally prevents conversion. These rules are structural, not matched to the example's wording. Independent Chinese and English examples are covered by tests.

## What the cloud services judge

The providers share the same bounded request and deterministic reconstruction:

| Provider | Endpoint | Model | Initial join threshold |
| --- | --- | --- | --- |
| Jev / TypeSafe | `https://api.typesafe.ai/v1/systemone` | `jev-1.13.0` | 0.98 |
| bjev / ByteDance | Internal service (configured in the app) | `bjev` | 0.80 |

After local rules run, each remaining candidate newline gets one `noul` question asking whether the next line continues the same unfinished prose sentence. Questions share the original lines and IDs in one request. The response must match the selected provider's model, and every required answer must be a finite `noul` in [0, 1] before any change. Only values meeting that provider's threshold allow joining. These thresholds are decision policies, not accuracy guarantees. Jev's previous threshold remains unchanged.

Unlike local mode, cloud judgment can cover short text and unindented or unevenly indented prose. After the local pass, blank lines, recognized code/commands/logs/list blocks, tabs, and ambiguous terminal punctuation other than colons remain protected by code. Colons in otherwise eligible prose are submitted for judgment: a high score joins the boundary, while a low score preserves it and retains any local joins. ASCII labelled records such as `description:` remain protected even with no inline value. Recognized list wraps use the same local handling in either cloud mode. Fences and null characters skip the whole copy. Only selected newline boundaries and their ordinary-space padding change; leading indentation, internal column spacing, untouched lines, and their LF/CRLF endings stay exact. Chinese fragments join without a space and English fragments use a separating space. The model never generates replacement text.

Cloud requests are limited to **12 KiB of UTF-8 text and 64 candidate boundaries** per copy. If either limit is exceeded, or no candidate remains after the local pass, nothing is sent and the local result is used. When a request is made, the plain-text copy after local joining is sent as context, including any protected paragraphs. HTML/RTF representations are kept locally for undo and are not sent. This is not a sensitive-data detector; only select a cloud provider for text you are willing to send to that service. The app never automatically sends a copy to the other cloud provider on failure.

Missing keys, network failures, authentication errors, rate limits, invalid/missing answers, unexpected model versions, and timeouts trigger local fallback when enabled. If the rules cannot recognize a wrap, or fallback is off, the original text remains unchanged. Successful cloud responses that choose no additional joins retain the result of the initial local pass. Local fallback keeps the same snapshot/undo and clipboard-version protections as cloud results.

**HTTP 451** means TypeSafe has refused the current network region. On October 13, 2026, an unauthenticated request from the development Mac returned `Typesafe is not available in your region.` This occurs before model judgment, so changing the join threshold cannot resolve it. Local fallback remains available; selecting **Local Rules** runs local rules without waiting for a network response. These diagnostics did not read the user's API key or clipboard. A native smoke test with synthetic English prose and an invalid test credential also received HTTP 451, then joined the text locally and restored the original in approximately 0.71 seconds. The user's reported Chinese example is covered by local regression tests; it was not sent by the diagnostic.

### bjev smoke evaluation — October 13, 2026

The initial Jev threshold of 0.98 missed clear synthetic continuations: bjev returned 0.8848 for a Chinese wrap and 0.9094 for an English wrap. Its initial threshold is therefore separate, at 0.80. The [30 synthetic cases](fixtures/line-judgments.json) and [observed probabilities](fixtures/bjev-results-2026-10-13.json) record this calibration. Both fixture splits were inspected when selecting the threshold; this is not an independent accuracy benchmark.

At 0.80, 14 of 15 intended joins were selected, all 15 intentional breaks stayed intact, and there were no false joins in this small sample. The remaining intended join started with `for`, which the existing command guard protected before any API call. This documents a conservative limitation; it does not prove a zero false-join rate on real clipboard text. A subsequent check through the final production client joined synthetic Chinese and English wraps, preserved an independent break, and joined/restored an isolated macOS pasteboard. Individual final smoke requests took approximately 0.17–0.25 seconds. No general clipboard contents were read for these checks.

### Local-first correction — version 1.0.1

A reported two-line Chinese paragraph met the existing local rules but bjev returned 0.6753 twice, below its 0.80 threshold. Removing complete sentences later in the second line changed the answer to 0.8097; the original pipeline allowed this unrelated context to prevent a local rule from joining the wrap. Prompt-only and sentence-fragment probes did not consistently fix both long and short inputs, so they were not shipped.

AI modes now run the existing conservative local normalizer first and submit only remaining candidate boundaries. The reported paragraph becomes one line without a network request in both Jev and bjev modes. Mixed copies still send unresolved boundaries to the selected provider in a single request. This is a policy change: locally recognized joins no longer require model approval. Local rules are still heuristic, and Restore remains available. Keys, cloud thresholds, prompts, and protections for structured content are unchanged. Regression tests cover the exact report, a low cloud score that must not block a local join, and partially normalized copies with both accepted and rejected cloud boundaries.

### Async consistency and availability

The clipboard remains the source of truth. A new copy, a mode change, or a key change cancels pending work. Before applying an answer, the controller checks its request ID, the enabled modes, deadline, and current pasteboard change count on the main thread. An old response cannot replace a newer copy, even before the next timer tick. Cancellation alone is not relied on for correctness.

This client/API design has no replicated shared database, so CP/AP is not a precise classification. During network failures it preserves copy/paste availability and uses conservative local correction when enabled. Otherwise it keeps the original. With connectivity it permits a bounded wait for a judgment, but never applies one to a different clipboard version. AppKit's existing non-atomic check/clear/write limitation still applies.

### Evaluating model quality

The automated tests verify request shape, response validation, text preservation, errors, cancellation, stale-response handling, and undo. They do not establish either provider's real-world accuracy or latency. Before relying on automatic cloud corrections, label representative Chinese, English, mixed-language, intentional-line-break, and structured-text examples. Measure false joins, missed joins, and end-to-end P95 latency with the pinned model. Tune the threshold against held-out examples, and repeat that evaluation before changing model versions. TypeSafe notes that its current model performs best in English.

Official references: [HTTP API](https://docs.typesafe.ai/api), [Noul](https://docs.typesafe.ai/primitives/noul), [models and language support](https://docs.typesafe.ai/models), [confidence and thresholds](https://docs.typesafe.ai/confidence).

## Limits

Plain text cannot reliably distinguish soft wrapping from intentional newlines. In local mode, unindented wraps, short text and uncertain blocks remain unchanged. Cloud judgment broadens the candidates but can still misjudge them. Some prose will be skipped, and intentional line breaks can still be joined. The recognizers do not parse every programming language or shell command. This app cannot promise lossless reconstruction of arbitrary terminal output; use Restore while the converted copy is still current if a conversion is unwanted.

## Source

- `Sources/ShellCopyCore/LineNormalizer.swift`: deterministic text-only rules.
- `Sources/ShellCopyCore/SystemOneNormalizer.swift`: bounded System One requests, protected boundaries, typed response validation, and deterministic reconstruction.
- `Sources/ShellCopyCore/CloudProvider.swift`: separate endpoints, models, and decision thresholds.
- `Sources/ShellCopyCore/ClipboardController.swift`: clipboard eligibility, snapshot, change-count checks and enable/restore state.
- `Sources/ShellCopy/main.swift`: menu and polling timer.
- `Sources/ShellCopy/ApplicationMenu.swift`: standard application/Edit menu and text-editing shortcuts.
- `Sources/ShellCopy/APIKeyStore.swift`: separate macOS keychain storage for each provider.
- `Sources/ShellCopy/APIKeyFile.swift`: bounded plain-text key import.
- `Tests/ShellCopyCoreTests/`: normalizer examples and real isolated-pasteboard state/race tests.
- `Tests/ShellCopyAppTests/`: AppKit shortcut dispatch and secure-field paste tests using synthetic keys and isolated pasteboards.
