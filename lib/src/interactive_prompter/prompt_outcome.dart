import '../models.dart';

part 'prompt_completed.dart';
part 'prompt_quit.dart';
part 'prompt_retry.dart';

/// Result of a prompted session — either a completed checklist or a signal.
sealed class PromptOutcome {}
