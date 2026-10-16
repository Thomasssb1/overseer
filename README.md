# overseer

A Dart human-in-the-loop (HitL) testing framework for manually verifying backend artifacts - videos, audio clips, images, and AI-generated output.

## Features

- **Matrix Engine** - define parameter permutations in a YAML file; expand them automatically.
- **Execution Wrapper** - pass each parameter set to your custom generation logic.
- **Interactive Prompter** - auto-opens the artifact, walks you through a checklist, supports hot-retry (`r`) and save-and-quit (`q`).
- **Reporter** - compiles your answers into a Markdown or versioned JSON test report.
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

Both report formats include the generating Overseer package version, the tested
Git commit SHA, and the matrix version when one is supplied. These values also
appear in partial reports. The package version is compiled into the library and
exported as `overseerVersion`; it is separate from the report schema version and
the matrix's revision tag.

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

New reports use [schema version 3](schema/report.v3.json), which requires
`overseer_version`. Validate a decoded report (versions 1, 2, and 3 are supported):

```dart
final report = jsonDecode(await File(reportPath).readAsString());
validateReport(report); // Throws ReportException for an invalid structure.
```

Reports include every expected case, review outcomes, commit SHA, and matrix SHA-256.
`successful` requires every checklist item in every case to pass.
CI should also compare the commit SHA, matrix hash, and expected case count with the checkout being tested.
Field descriptions are in the schema.

The commit SHA is captured before generation from `commitSha`, then `GITHUB_SHA`,
then Git HEAD in the matrix's directory. It is `null` in JSON or `unavailable` in
Markdown if no revision can be resolved. A standalone `Reporter` needs a
`ReportContext` to include the tested revision.
Resume requires matching commit and matrix provenance, so older lock files start a fresh review.

When releasing Overseer, update `lib/src/version.dart` alongside the version in
`pubspec.yaml`; the test suite checks that they match.
