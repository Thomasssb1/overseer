# overseer

A Dart human-in-the-loop (HitL) testing framework for manually verifying backend artifacts - videos, audio clips, images, and AI-generated output.

## Features

- **Matrix Engine** - define parameter permutations in a YAML file; expand them automatically.
- **Execution Wrapper** - pass each parameter set to your custom generation logic.
- **Interactive Prompter** - auto-opens the artifact, walks you through a checklist, supports hot-retry (`r`) and save-and-quit (`q`).
- **Reporter** - compiles your answers into a Markdown or versioned JSON test report.
- **Verify** - checks JSON reports against a matrix, commit SHA, and review policy for CI gates.
- **Resume / Lock File** - quit at any point and pick up exactly where you left off.

## Quick Start

```dart
import 'package:overseer/overseer.dart';

void main() async {
  final runner = OverseerRunner(
    matrixPath: 'tests/my_test.matrix.yaml',
    generator: (testCase) async {
      // Your generation logic here
      final outputPath = await myGenerateVideo(testCase.params);
      return ArtifactResult(path: outputPath);
    },
  );

  await runner.run();
}
```

## Try the Example

From the package root:

```sh
dart pub get
dart run example/overseer_example.dart
```

This self-contained demo writes text artifacts for four parameter combinations and walks you through reviewing them.
No API keys or external services are needed.
Open each displayed artifact path manually; use `r` to regenerate or `q` to save and quit.
Run the same command again to resume at the first unfinished case.

Reports are saved under `example/output/reports/`.
See the [example walkthrough](example/README.md) for retry behavior, partial reports, resume details, and adapting the generator.

## Matrix YAML

```yaml
name: "video_quality_check"
version: '1.0.0' # optional matrix revision tag
parameters:
  resolution: [720, 1080]
  bitrate: [low, high]
mode: permutations # or: list
checklist:
  - "Video plays without artefacts"
  - "Audio is in sync"
  - "No black frames at start"
```

`mode: permutations` produces the cartesian product of all parameter lists (4 cases above).  
`mode: list` zips parameter lists row-by-row (all lists must be the same length).

Add an optional quoted `version`, such as `'1.0.0'`, to track matrix revisions
in prompts and reports. Update it when changing parameters or checklist items.

## CLI Shortcuts

| Key | Action                               |
| --- | ------------------------------------ |
| `y` | Pass this checklist item             |
| `n` | Fail this checklist item             |
| `s` | Skip this checklist item             |
| `r` | Hot-retry - regenerate this artifact |
| `q` | Save progress and quit               |

## Report Output

A Markdown report is written to `reports/overseer_report_<timestamp>.md` at the end of the run (or on quit).

### JSON reports for CI

Select JSON when creating the runner. `run()` returns the `.json` report path:

```dart
final runner = OverseerRunner(
  matrixPath: 'tests/my_test.matrix.yaml',
  reportFormat: ReportFormat.json,
  generator: generateArtifact,
  // Optional: commitSha: 'full Git commit SHA',
);
final reportPath = await runner.run();
```

Reports follow the [JSON schema](schema/report.v3.json).
Validate a decoded report:

```dart
final report = jsonDecode(await File(reportPath).readAsString());
validateReport(report); // Throws ReportException for an invalid structure.
```

Reports include every expected case, review outcomes, commit SHA, and matrix SHA-256.
`successful` requires every checklist item in every case to pass.
Use `overseer verify` to compare the report with the checkout being tested.
Field descriptions are in the schema.

Resume requires matching commit and matrix provenance, so older lock files start a fresh review.

### Verify a report in CI

```sh
dart run overseer verify --report reports/review.json --matrix tests/my_test.matrix.yaml --expected-sha "$GITHUB_SHA" > verification.json
```

All three options are required; `--expected-sha` takes a full Git commit SHA.
Verification checks the report schema, case coverage and outcomes, commit SHA,
and the exact matrix file hash.

All verdicts must pass by default. Enable `--allow-failures`, `--allow-skips`, or
`--allow-errors` independently to allow failed verdicts, skipped verdicts, or
terminal generator errors. Pending and interrupted reviews always fail.

JSON results go to stdout and readable diagnostics to stderr. Exit codes are
**0** for success and **1** for invalid input or failed verification.
Run `dart run overseer verify --help` for options.
