import 'dart:io';

import 'package:yaml/yaml.dart';

import '../exceptions.dart';
import '../models.dart';

import 'matrix_mode.dart';

/// Loads a matrix YAML file and expands it into a list of [TestCase]s.
///
/// ## YAML schema
/// ```yaml
/// name: "video_quality_check"
/// parameters:
///   resolution: [720, 1080]
///   bitrate: [low, high]
/// mode: permutations  # or: list
/// checklist:
///   - "Video plays without artefacts"
///   - "Audio is in sync"
/// ```
class MatrixEngine {
  const MatrixEngine._();

  /// Parses [yamlPath] and returns the fully expanded list of [TestCase]s.
  ///
  /// Throws [MatrixParseException] if the file is missing, malformed, or
  /// contains incompatible parameter list lengths in `list` mode.
  static List<TestCase> load(String yamlPath) {
    final file = File(yamlPath);
    if (!file.existsSync()) {
      throw MatrixParseException('Matrix file not found: $yamlPath');
    }

    try {
      final dynamic rawData = loadYaml(file.readAsStringSync());
      if (rawData is! YamlMap) {
        throw const MatrixParseException('Matrix YAML root must be a map.');
      }

      final name = _requireString(rawData, 'name');
      final checklist = _requireStringList(rawData, 'checklist');
      final mode = _parseMode(rawData['mode']);
      final parameters = _parseParameters(rawData['parameters']);

      final cases = mode == MatrixMode.permutations
          ? _expandPermutations(name, checklist, parameters)
          : _expandList(name, checklist, parameters);

      return cases;
    } on YamlException catch (e) {
      throw MatrixParseException(
          'Failed to parse matrix YAML in \'$yamlPath\': ${e.message}');
    } on FileSystemException catch (e) {
      throw MatrixParseException(
          'Failed to read matrix file \'$yamlPath\': ${e.message}');
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static String _requireString(YamlMap map, String key) {
    final value = map[key];
    if (value == null) {
      throw MatrixParseException('Missing required field \'$key\'.');
    }
    if (value is! String || value.trim().isEmpty) {
      throw MatrixParseException('Field \'$key\' must be a non-empty string.');
    }
    return value;
  }

  static List<String> _requireStringList(YamlMap map, String key) {
    final value = map[key];
    if (value == null) {
      throw MatrixParseException('Missing required field \'$key\'.');
    }
    if (value is! YamlList) {
      throw MatrixParseException('Field \'$key\' must be a list.');
    }
    if (value.isEmpty) {
      throw MatrixParseException('Field \'$key\' must not be empty.');
    }
    final result = <String>[];
    for (var i = 0; i < value.length; i++) {
      final item = value[i];
      if (item is! String || item.trim().isEmpty) {
        throw MatrixParseException(
            'Item at index $i in \'$key\' must be a non-empty string.');
      }
      result.add(item);
    }
    return result;
  }

  static MatrixMode _parseMode(dynamic rawMode) {
    if (rawMode == null) return MatrixMode.list;
    if (rawMode is! String) {
      throw const MatrixParseException('Field \'mode\' must be a string.');
    }
    switch (rawMode.toLowerCase()) {
      case 'permutations':
        return MatrixMode.permutations;
      case 'list':
        return MatrixMode.list;
      default:
        throw MatrixParseException(
            'Unknown mode \'$rawMode\'. Expected \'permutations\' or \'list\'.');
    }
  }

  static Map<String, List<dynamic>> _parseParameters(dynamic rawParameters) {
    if (rawParameters == null) {
      throw const MatrixParseException('Missing required field \'parameters\'.');
    }
    if (rawParameters is! YamlMap) {
      throw const MatrixParseException('Field \'parameters\' must be a map.');
    }
    final result = <String, List<dynamic>>{};
    for (final entry in rawParameters.entries) {
      final dynamic rawKey = entry.key;
      if (rawKey is! String || rawKey.trim().isEmpty) {
        throw MatrixParseException(
            'Parameter names in \'parameters\' must be non-empty strings.');
      }
      final String key = rawKey;
      final value = entry.value;
      if (value is YamlList) {
        if (value.isEmpty) {
          throw MatrixParseException(
              'Parameter \'$key\' must have at least one value.');
        }
        for (final item in value) {
          if (item is YamlMap || item is YamlList) {
            throw MatrixParseException(
                'Parameter \'$key\' items must be scalar values, not complex objects.');
          }
        }
        result[key] = value.toList();
      } else if (value is YamlMap) {
        throw MatrixParseException(
            'Parameter \'$key\' must be a scalar or list of scalars, not a map.');
      } else {
        // Single scalar value — wrap in a list.
        result[key] = [value];
      }
    }
    if (result.isEmpty) {
      throw const MatrixParseException(
          'Field \'parameters\' must contain at least one entry.');
    }
    return result;
  }

  /// Cartesian product expansion.
  static List<TestCase> _expandPermutations(
    String name,
    List<String> checklist,
    Map<String, List<dynamic>> parameters,
  ) {
    // Start with one empty map and accumulate.
    var combinations = [<String, dynamic>{}];

    for (final entry in parameters.entries) {
      final expanded = <Map<String, dynamic>>[];
      for (final existing in combinations) {
        for (final v in entry.value) {
          expanded.add({...existing, entry.key: v});
        }
      }
      combinations = expanded;
    }

    return [
      for (var i = 0; i < combinations.length; i++)
        TestCase(
          name: name,
          index: i,
          params: combinations[i],
          checklist: checklist,
        ),
    ];
  }

  /// Zip / row-by-row expansion.
  static List<TestCase> _expandList(
    String name,
    List<String> checklist,
    Map<String, List<dynamic>> parameters,
  ) {
    final keys = parameters.keys.toList();
    final values = parameters.values.toList();
    final length = values.first.length;

    for (var i = 1; i < values.length; i++) {
      if (values[i].length != length) {
        throw MatrixParseException(
          'In \'list\' mode all parameter lists must be the same length. '
          '\'${keys[i]}\' has ${values[i].length} items but expected $length.',
        );
      }
    }

    return [
      for (var r = 0; r < length; r++)
        TestCase(
          name: name,
          index: r,
          params: {for (var c = 0; c < keys.length; c++) keys[c]: values[c][r]},
          checklist: checklist,
        ),
    ];
  }
}
