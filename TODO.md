# overseer - To-Do & Roadmap

## Package Distribution & Layout

- [x] **Standardize Example**: Provide `example/overseer_example.dart` for the pub.dev Example tab, with a documented run, retry, resume, and report walkthrough.
- [x] **Refine Pubspec**: Improve package topics and description on `pub.dev`.

## Core Features & Enhancements

- [ ] **`mode: random_n`**: Implement a random permutation selector in `MatrixEngine` so users can evaluate exactly `N` distinct random cases from an enormous hyper-parameter space.
- [ ] **Conditional Matrix Parameters**: Add support for dependent arguments (e.g. if `video_codec: h265`, only inject `bitrate: 4k`).
- [ ] **Custom Reporter Templates**: Allow users to override how the Markdown report is visually dumped out.
- [x] **UI Responsiveness**: Wrap case headers, long parameters, artifact paths, and key hints to the terminal width, with an 80-column fallback for redirected output.

## Testing & Hardening

- [x] **OS-Level `autoOpen` Tests**: Verify Windows, macOS, and Linux launcher arguments, paths with spaces, failed commands, exceptions, and unsupported platforms without launching applications.
- [ ] **Integration Stub**: Expand the example generator stub into an actual minimal hitl test suite for users to see exactly what an end-to-end `overseer` environment feels like.
