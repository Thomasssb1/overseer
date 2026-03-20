/// The artifact produced by the user's generator for a given [TestCase].
class ArtifactResult {
  ArtifactResult({
    required this.path,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata ?? <String, dynamic>{};

  /// Absolute or relative path to the generated artifact file.
  final String path;

  /// Optional extra metadata to include in the report.
  final Map<String, dynamic> metadata;
}
