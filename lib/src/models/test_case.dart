/// Contains the resolved parameter map and checklist items defined in the
/// matrix YAML file.
class TestCase {
  const TestCase({
    required this.name,
    required this.index,
    required this.params,
    required this.checklist,
  });

  /// The name of the test suite (from the matrix YAML `name` field).
  final String name;

  /// The zero-based index of this case within the expanded matrix.
  final int index;

  /// The resolved parameter map for this case (e.g. `{resolution: 1080}`).
  final Map<String, dynamic> params;

  /// The ordered list of checklist items the reviewer must answer.
  final List<String> checklist;

  /// Returns a human-readable label for display in the CLI.
  String get label {
    final baseLabel = '$name #${index + 1}';
    if (params.isEmpty) return baseLabel;
    final paramStr =
        params.entries.map((e) => '${e.key}=${e.value}').join(', ');
    return '$baseLabel [$paramStr]';
  }

  @override
  String toString() => 'TestCase($label)';
}
