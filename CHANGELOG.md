# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Non-interactive `overseer verify` command and `verifyReport` API for CI gates, with schema/version validation, exact case coverage, consistent outcomes and totals, commit and matrix provenance checks, and explicit failure/skip/error policy flags. The CLI emits JSON on stdout, diagnostics on stderr, and exits 0 or 1.

## [1.1.0] - 2026-10-17

### Added

- Overseer package version in Markdown and JSON reports, plus the tested commit SHA in Markdown, including partial reports. The `overseerVersion` value is read from the installed package's pubspec.yaml.
- Report schema supports matrix version tags and requires `overseer_version`; validation of older reports is preserved.
- Optional matrix `version` tags, preserved in generated cases, terminal labels, Markdown and JSON reports, and resumable results. Invalid tags fail with a descriptive matrix parse error.
- Opt-in JSON reports with a versioned JSON schema, commit SHA, matrix SHA-256, expected and completed case counts, strict pass policy, and all case outcomes for CI validation, including partial reviews and generator errors.
- A `validateReport` helper backed by `json_schema` for validating report structure.

### Fixed

- Count and label mixed pass/skipped and incomplete Markdown reviews as skipped, using the same review status rules as JSON.
- Bind resumable progress to the matrix contents and commit so stale reviews cannot be attributed to a different source revision or matrix.
- Preserve completed progress if writing the final report fails.

## [1.0.1] - 2026-10-11

### Added

- Cross-platform artifact-opening tests covering launcher arguments, paths with spaces, command failures, and unsupported platforms without opening applications.

### Changed

- Remove emojis from terminal status messages and print the example's report location only once.
- Clarify the package description and add pub.dev topics for discoverability.
- Rename the runnable example for pub.dev's Example tab and document artifact review, retries, save-and-quit, resume behavior, and report locations.

### Fixed

- Wrap interactive case headers to fit narrow terminals, preserving long parameter values and artifact paths.
- Stop the session and preserve completed progress when hot retries are exhausted, so the unfinished case can be resumed instead of silently omitted from a completed run.
- Treat end-of-input as save-and-quit, preserving partial review results and resumable progress instead of repeatedly prompting after EOF.
- Use the same Dart SDK for CI and publishing, validate the package before creating a release, and fail the release workflow if publishing fails.

## [1.0.0] - 2026-03-21

### Added

- **Initial Release** of the `overseer` hitl-testing package!
- **MatrixEngine**: Parse parameter permutations (`mode: permutations` and `mode: list`) from YAML tests.
- **ExecutionWrapper**: Safely run user-defined asynchronous generation callbacks with robust error-wrapping.
- **InteractivePrompter**: Terminal-based CLI prompting UI. Includes OS-native auto-opening of artifacts (`start`/`open`/`xdg-open`), and hot-retry support (`r`).
- **Reporter**: Generates formatted Markdown reports documenting parameters, retry counts, and final checklist verdicts cleanly.
- **Session Locking**: Auto-persisting `.overseer.lock` capabilities so users can quit mid-session (`q`) and seamlessly resume.
