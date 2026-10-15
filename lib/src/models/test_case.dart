/// A single test case produced by the [MatrixEngine].
///
/// Contains the resolved parameter map and checklist items defined in the
/// matrix YAML file.
class TestCase {
  const TestCase({
    required this.name,
    required this.index,
    required this.params,
    required this.checklist,
    this.matrixVersion,
  });

  /// The name of the test suite (from the matrix YAML `name` field).
  final String name;

  /// The matrix's optional `version` tag, independent of the report schema.
  final String? matrixVersion;

  /// The zero-based index of this case within the expanded matrix.
  final int index;

  /// The resolved parameter map for this case (e.g. `{resolution: 1080}`).
  final Map<String, dynamic> params;

  /// The ordered list of checklist items the reviewer must answer.
  final List<String> checklist;

  /// Returns a human-readable label for display in the CLI.
  String get label {
    final versionLabel =
        matrixVersion == null ? '' : ' (version $matrixVersion)';
    final baseLabel = '$name$versionLabel #${index + 1}';
    if (params.isEmpty) return baseLabel;
    final paramStr =
        params.entries.map((e) => '${e.key}=${e.value}').join(', ');
    return '$baseLabel [$paramStr]';
  }

  @override
  String toString() => 'TestCase($label)';
}
