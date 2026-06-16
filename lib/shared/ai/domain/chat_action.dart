/// A data-mutating action the chat AI proposed but has NOT yet applied.
///
/// The `chat` Cloud Function defers every add_*/delete_* tool call into one of
/// these instead of running it; the chat UI shows a confirm card and only on the
/// user's accept does [AiService.applyChatActions] run them server-side — mirroring
/// Smart Add's "pending then accept" flow, but with the writes done by the same
/// server-side tool executors (so no mutation logic is duplicated on the client).
class ProposedAction {
  /// The tool name, e.g. `add_event`, `delete_todo`.
  final String name;

  /// The raw JSON argument string emitted by the model, passed back verbatim to
  /// `applyChatActions` (the server re-parses and executes it).
  final String arguments;

  const ProposedAction({required this.name, required this.arguments});

  factory ProposedAction.fromJson(Map<String, dynamic> j) => ProposedAction(
        name: (j['name'] as String?) ?? '',
        arguments: (j['arguments'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {'name': name, 'arguments': arguments};
}

/// The outcome of one chat turn: the assistant's reply text (already appended to
/// the `chat_messages` thread server-side) plus any actions awaiting the user's
/// confirmation. When [proposedActions] is empty the turn was a plain reply.
class ChatTurn {
  final String reply;
  final List<ProposedAction> proposedActions;

  const ChatTurn({required this.reply, required this.proposedActions});
}
