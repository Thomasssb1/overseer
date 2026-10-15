/// The output format for a review report.
enum ReportFormat {
  /// A human-readable report with summary and checklist tables.
  markdown,

  /// A versioned report for automated validation and CI.
  json,
}
