/// Supported matrix expansion modes.
enum MatrixMode {
  /// Cartesian product of all parameter lists.
  permutations,

  /// Zip parameter lists row-by-row (all lists must be the same length).
  list,
}
