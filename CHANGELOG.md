## 1.0.0

- **Initial Release** of the `overseer` hitl-testing package!
- **MatrixEngine**: Parse parameter permutations (`mode: permutations` and `mode: list`) from YAML tests.
- **ExecutionWrapper**: Safely run user-defined asynchronous generation callbacks with robust error-wrapping.
- **InteractivePrompter**: Terminal-based CLI prompting UI. Includes OS-native auto-opening of artifacts (`start`/`open`/`xdg-open`), and hot-retry support (`r`).
- **Reporter**: Generates formatted Markdown reports documenting parameters, retry counts, and final checklist verdicts cleanly.
- **Session Locking**: Auto-persisting `.overseer.lock` capabilities so users can quit mid-session (`q`) and seamlessly resume.
