# overseer

A Dart human-in-the-loop (HitL) testing framework for manually verifying backend artifacts — videos, audio clips, images, and AI-generated output.

## Features

- **Matrix Engine** — define parameter permutations in a YAML file; expand them automatically.
- **Execution Wrapper** — pass each parameter set to your custom generation logic.
- **Interactive Prompter** — auto-opens the artifact, walks you through a checklist, supports hot-retry (`r`) and save-and-quit (`q`).
- **Reporter** — compiles your y/n answers into a Markdown test report.
- **Resume / Lock File** — quit at any point and pick up exactly where you left off.

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

## Matrix YAML

```yaml
name: "video_quality_check"
parameters:
  resolution: [720, 1080]
  bitrate: [low, high]
mode: permutations   # or: list
checklist:
  - "Video plays without artefacts"
  - "Audio is in sync"
  - "No black frames at start"
```

`mode: permutations` produces the cartesian product of all parameter lists (4 cases above).  
`mode: list` zips parameter lists row-by-row (all lists must be the same length).

## CLI Shortcuts

| Key | Action |
|-----|--------|
| `y` | Pass this checklist item |
| `n` | Fail this checklist item |
| `s` | Skip this checklist item |
| `r` | Hot-retry — regenerate this artifact |
| `q` | Save progress and quit |

## Report Output

A Markdown report is written to `reports/overseer_report_<timestamp>.md` at the end of the run (or on quit).
