import '../models.dart';

/// Result of a prompted session — either a completed checklist or a signal.
sealed class PromptOutcome {}

/// The reviewer answered all checklist items.
class PromptCompleted extends PromptOutcome {
  PromptCompleted(this.result);
  final ChecklistResult result;
}

/// The reviewer pressed `r` — regenerate this artifact from scratch.
class PromptRetry extends PromptOutcome {
  PromptRetry();
}

/// The reviewer pressed `q` — save progress and quit the session.
class PromptQuit extends PromptOutcome {
  PromptQuit(this.partial);

  /// Partial result collected before the user quit (may be incomplete).
  final ChecklistResult? partial;
}
