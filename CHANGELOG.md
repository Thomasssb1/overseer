# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Stop the session and preserve completed progress when hot retries are exhausted, so the unfinished case can be resumed instead of silently omitted from a completed run.
- Treat end-of-input as save-and-quit, preserving partial review results and resumable progress instead of repeatedly prompting after EOF.

## [1.0.0] - 2026-03-21

### Added

- **Initial Release** of the `overseer` hitl-testing package!
- **MatrixEngine**: Parse parameter permutations (`mode: permutations` and `mode: list`) from YAML tests.
- **ExecutionWrapper**: Safely run user-defined asynchronous generation callbacks with robust error-wrapping.
- **InteractivePrompter**: Terminal-based CLI prompting UI. Includes OS-native auto-opening of artifacts (`start`/`open`/`xdg-open`), and hot-retry support (`r`).
- **Reporter**: Generates formatted Markdown reports documenting parameters, retry counts, and final checklist verdicts cleanly.
- **Session Locking**: Auto-persisting `.overseer.lock` capabilities so users can quit mid-session (`q`) and seamlessly resume.
