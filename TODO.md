# overseer - To-Do & Roadmap

## Package Distribution & Layout

- [ ] **Standardize Example**: Rename `example/example_runner.dart` to `example/overseer_example.dart` (or `example/example.dart`). According to Dart's [package layout conventions](https://dart.dev/tools/pub/package-layout#examples), `pub.dev` specifically looks for `example/example.dart` or a file matching the package name to automatically populate the **Example** tab online!
- [ ] **Refine Pubspec**: Improve package tags and description on `pub.dev`.

## Core Features & Enhancements

- [ ] **`mode: random_n`**: Implement a random permutation selector in `MatrixEngine` so users can evaluate exactly `N` distinct random cases from an enormous hyper-parameter space.
- [ ] **Conditional Matrix Parameters**: Add support for dependent arguments (e.g. if `video_codec: h265`, only inject `bitrate: 4k`).
- [ ] **Custom Reporter Templates**: Allow users to override how the Markdown report is visually dumped out.
- [ ] **UI Responsiveness**: Bullet-proof the `InteractivePrompter` tabular header outputs so they wrap cleanly if a user is evaluating an exceptionally long parameter string on a tiny terminal width.

## Testing & Hardening

- [ ] **OS-Level `autoOpen` Tests**: Currently the native runner auto-open functionality isn't tested out-of-the-box. We could mock `Process.run` to securely test these cross-platform invocation strings.
- [ ] **Integration Stub**: Expand the example generator stub into an actual minimal hitl test suite for users to see exactly what an end-to-end `overseer` environment feels like.
