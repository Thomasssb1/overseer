part of 'prompt_outcome.dart';

/// The reviewer answered all checklist items.
class PromptCompleted extends PromptOutcome {
  PromptCompleted(this.result);
  final ChecklistResult result;
}
