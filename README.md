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

New reports use [schema version 3](schema/report.v3.json).
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

Run the non-interactive validator from a project that depends on Overseer:

```sh
dart run overseer verify --report reports/review.json --matrix tests/my_test.matrix.yaml --expected-sha "$GITHUB_SHA" > verification.json
```

Alternatively, `dart pub global activate overseer` installs the `overseer`
executable, which accepts the same `verify` command and options.

`--report`, `--matrix`, and `--expected-sha` are required. Supply the full Git
commit SHA you expect to have been reviewed (40 or 64 hex characters).
Verification supports report schema versions 1, 2, and 3 and checks:

- Schema structure and version, commit SHA equality, and SHA-256 of the exact
  matrix file bytes (including whitespace and line endings).
- Every expected case appears exactly once with matching name, parameter values,
  and ordered checklist. Report case order and checkout paths may differ.
- Matrix version metadata matches for schemas 2 and 3. Schema 1 predates version
  tags, so its matrix identity is checked using the byte hash.
- Case statuses, summary counts, and completion/success flags agree with the
  recorded outcomes. Pending cases, partial reviews, and missing answers fail.

By default, all checklist verdicts must pass. Optional policy flags are:

| Flag | Effect |
| --- | --- |
| `--allow-failures` | Allow failed checklist verdicts in fully reviewed cases. |
| `--allow-skips` | Allow skipped checklist verdicts in fully reviewed cases. |
| `--allow-errors` | Allow terminal generator errors without a completed review. |

Flags apply independently: a case with failed and skipped answers requires both
corresponding flags. Even with all flags enabled, pending or interrupted reviews
fail. `--allow-errors` can accept a report with `complete: false` only when every
unfinished case is a terminal generator error. The report's `successful` field
always retains its original all-pass meaning, regardless of verification policy.

The command exits **0** when verification passes and **1** for rejected reports
or invalid input. A readable summary and diagnostics go to **stderr**; **stdout**
contains one JSON result, including on failure:

```json
{
  "valid": true,
  "summary": "Verification passed: all 4 expected cases satisfy policy.",
  "expected_case_count": 4,
  "reported_case_count": 4,
  "errors": []
}
```

Counts are `null` when invalid inputs prevent verification. Use
`overseer verify --help` for command help. Dart callers can use
`verifyReport(decodedReport, matrixPath: path, expectedSha: sha)` and inspect the
returned `VerificationResult` or its `toJson()` representation.
