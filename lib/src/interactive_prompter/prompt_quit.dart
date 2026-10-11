part of 'prompt_outcome.dart';

/// The reviewer pressed `q` — save progress and quit the session.
class PromptQuit extends PromptOutcome {
  PromptQuit(this.partial);

  /// Partial result collected before the user quit (may be incomplete).
  final ChecklistResult? partial;
}
