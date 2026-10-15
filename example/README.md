# Try Overseer

This example writes local text files and takes you through a human review session.
It needs no API keys, model downloads, or external services. The model names in
the matrix are parameter labels; the generator does not call those models.

From the package root, run:

```sh
dart pub get
dart run example/overseer_example.dart
```

The [example matrix](tests/example.matrix.yaml) combines two model labels with
two temperatures, producing four cases with four checklist items each.
Its `version: '1.0.0'` tag identifies the matrix revision in prompts and reports.
Update this tag when revising the matrix; a changed matrix starts a fresh review.

## Review a case

For each case, open the `.txt` file shown beside **Artifact** in the terminal.
Automatic opening is disabled in this demo. Set `autoOpen: true` in
[overseer_example.dart](overseer_example.dart) to use your default application.

Answer each checklist item with `y` (pass), `n` (fail), or `s` (skip), then Enter.
The generated text is a placeholder: choose the verdicts you want to explore to
see how they appear in the report.

## Retry, quit, and resume

1. Complete the first case to save its verdicts.
2. On the next case, enter `r` to regenerate its artifact and restart its
   checklist. This stub writes the same text to the same path, so the content
   stays the same even though the retry count increases.
3. Answer an item, then enter `q` to stop. Overseer writes a partial report;
   unanswered items on that partially reviewed case appear as skipped. End of
   input also follows this save-and-quit path.
4. Run the same command again. Completed cases are restored. The unfinished
   case is generated and reviewed again from the beginning; its partial answers
   remain in the earlier report, rather than being restored into the checklist.

The default allowance is five retries per case in a session. Requesting another
retry after that limit saves a partial report and stops, so you can resume later.

## Find the output

All paths are relative to the package root:

| Path | Contents |
| --- | --- |
| `example/output/artifacts/` | Generated text files, one per parameter combination. |
| `example/output/reports/overseer_report_<timestamp>.md` | A report for each completed or interrupted run. |
| `example/output/.overseer.lock` | Completed-case progress, saved once a case finishes and removed when the full run completes. |

Reports contain summary counts, parameters, artifact paths, retry counts, and
checklist verdicts. An interrupted report may contain fewer than all four cases.
The final report includes restored results from completed cases and the newly
reviewed results. Generated output is excluded from Git and the published package.

## Use your own generator

Edit the matrix to define your parameters and checklist. In
[overseer_example.dart](overseer_example.dart), replace the generator callback's
text-writing code with your own generation logic and return
`ArtifactResult(path: outputPath)` for the file you want to review. Finish the
current session before changing its matrix, or use a separate `outputDir` for a
new matrix so existing progress is kept separate.
