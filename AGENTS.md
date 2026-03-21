# OVERSEER AGENT INSTRUCTIONS

This document contains rules, preferences, and architectural standards extracted from previous sessions. **You must strictly obey these guidelines when generating or modifying code in this repository.**

## 1. Architectural & File Structure

- **Strict 1:1 File-to-Class Ratio:** Never bundle multiple classes, enums, or sealed class hierarchies into a single file. Every `class`, `enum`, and `sealed class` must live in its own dedicated, correctly named file in its respective directory.
- **Barrel Files:** Use barrel files (e.g., `exceptions.dart`, `models.dart`, `overseer.dart`) at the top of directories to export the underlying deeply-nested individual files. External modules should import the barrel file rather than reaching directly into internal file structures if possible.
- **Refactoring:** If you encounter legacy files that contain multiple classes/enums grouped together, proactively extract them into their own files and wire up the imports/exports to prevent breaking changes.

## 2. Dart Best Practices & Linting

- **Single Quotes (`prefer_single_quotes`):** Always use single quotes strings (`'`) in Dart code. Double quotes (`"`) are only allowed if the string strictly contains a literal single quote inside it (e.g., `'Parameter \'$key\''` or `"Parameter '$key'"`).
- **`dart format`:** Always ensure any Dart code written strictly aligns with the native `dart format .` standards.

## 3. Testing Mandates

- **No Un-tested Code:** Every new class, function, or engine feature you write **must** include an accompanying unit test inside the `test/src/` directory that accurately mirrors the `lib/src/` path structure.
- **Exhaustive Branch Coverage:** When writing tests (especially for logic/schema parsing like `MatrixEngine`), do not just write happy-path tests. You must write explicit tests that trigger structural Exceptions, schema validation failures, and mismatched list/variable length failures.
- **Temporary Files in Tests:** If testing file-system reading (like `.matrix.yaml`), strictly use `Directory.systemTemp.createTempSync()` in `setUp()` and safely delete the temporary directory in `tearDown()`.

## 4. Error Handling & Validation

- **No Raw Target Exceptions:** When extracting data or parsing YAML objects, do not allow native Dart `TypeError` exceptions to kill the process (e.g. failing an `as String?` downcast). Trap dynamic inputs using `is` checks and immediately throw a custom, descriptive repository exception (e.g., `MatrixParseException`).
- **Strict Schema Integrity:** Never silently fallback on invalid configurations (like wrapping a `YamlMap` into a list when a scalar was expected). If the schema strictly defines arrays of scalars, explicitly validate and throw exceptions if complex objects are provided.
