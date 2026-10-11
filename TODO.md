# overseer - To-Do & Roadmap

## Package Distribution & Layout

- [x] **Standardize Example**: Provide `example/overseer_example.dart` for the pub.dev Example tab, with a documented run, retry, resume, and report walkthrough.
- [x] **Refine Pubspec**: Improve package topics and description on `pub.dev`.

## Core Features & Enhancements

- [ ] **`mode: random_n`**: Implement a random permutation selector in `MatrixEngine` so users can evaluate exactly `N` distinct random cases from an enormous hyper-parameter space.
- [ ] **Conditional Matrix Parameters**: Add support for dependent arguments (e.g. if `video_codec: h265`, only inject `bitrate: 4k`).
- [ ] **Custom Reporter Templates**: Allow users to override how the Markdown report is visually dumped out.
- [ ] **UI Responsiveness**: Bullet-proof the `InteractivePrompter` tabular header outputs so they wrap cleanly if a user is evaluating an exceptionally long parameter string on a tiny terminal width.

## Testing & Hardening

- [x] **OS-Level `autoOpen` Tests**: Verify Windows, macOS, and Linux launcher arguments, paths with spaces, failed commands, exceptions, and unsupported platforms without launching applications.
- [ ] **Integration Stub**: Expand the example generator stub into an actual minimal hitl test suite for users to see exactly what an end-to-end `overseer` environment feels like.
