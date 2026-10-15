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

This self-contained demo writes text artifacts for four parameter combinations
and walks you through reviewing them. No API keys or external services are needed.
Open each displayed artifact path manually; use `r` to regenerate or `q` to save
and quit. Run the same command again to resume at the first unfinished case.

Reports are saved under `example/output/reports/`. See the
[example walkthrough](example/README.md) for retry behavior, partial reports,
resume details, and adapting the generator.

## Matrix YAML

```yaml
name: "video_quality_check"
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

JSON reports follow [schema version 1](schema/report-v1.schema.json) and contain:

- `$schema`, `schema_version`, and a UTC `generated_at` timestamp.
- `commit_sha`: an explicit override, otherwise `GITHUB_SHA`, otherwise Git HEAD
  in the matrix's directory. It is `null` when no revision can be determined.
- `matrix.path` and `matrix.sha256`, a SHA-256 of the exact matrix file bytes
  captured before generation. Line-ending changes affect the hash.
- `expected_case_count`, `completed_case_count`, and `complete`.
- `summary` counts for `passed`, `failed`, `skipped`, `error`, and `pending`.
- Every expected case, including parameters, artifact path, retry count,
  checklist verdicts, completion, status, and generator error details.

`successful` uses a strict review policy: at least one expected case, every case
completed, and every checklist item passed. A case with any failed answer is
`failed`; otherwise any skipped or missing answer makes it `skipped`. Cases with
terminal generator failures are `error`; unreviewed cases are `pending`. A
partially answered case is never completed. Recovered generator failures are
represented by the final review and its retry count. Markdown keeps its existing
summary behavior.

Progress is reused only when both the matrix hash and commit match. Older lock
files without this provenance start a fresh review. Resumed reports include all
completed cases, while quit, EOF, and retry exhaustion produce partial reports.

In CI, validate the report against the schema, compare its commit and matrix
identity with the checkout being tested, and enforce your review policy. For
example, with `REPORT` pointing to the JSON report, this Bash/jq check enforces
four fully passing cases:

```sh
MATRIX=tests/my_test.matrix.yaml
MATRIX_SHA256=$(sha256sum "$MATRIX" | cut -d ' ' -f 1)
jq -e --arg sha "$GITHUB_SHA" --arg hash "$MATRIX_SHA256" --argjson expected 4 '
  .schema_version == 1 and
  .commit_sha == $sha and .matrix.sha256 == $hash and
  .expected_case_count == $expected and
  .completed_case_count == $expected and .complete and .successful and
  .summary == {passed: $expected, failed: 0, skipped: 0, error: 0, pending: 0} and
  ([.cases[].index] == [range(0; $expected)]) and
  all(.cases[]; .completed and .status == "passed" and
      all(.checklist[]; .verdict == "pass"))
' "$REPORT"
```

Use the expected count from your checked-in matrix rather than trusting the
report's own count. Direct `Reporter` users can supply a `ReportContext` with
the expected cases and matrix provenance when selecting `ReportFormat.json`.
