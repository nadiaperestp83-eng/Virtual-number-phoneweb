/// Resumo de uma conversa, calculado a partir das [LocalMessage]
/// agrupadas por `peerNumber`. Não é uma tabela própria — é derivado.
class ConversationSummary {
  const ConversationSummary({
    required this.peerNumber,
    required this.peerUserId,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
  });

  final String peerNumber;
  final String peerUserId;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int unreadCount;
}
