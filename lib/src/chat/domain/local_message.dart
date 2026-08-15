/// Mensagem de chat, em cache local (Hive CE, guardada como `Map`).
///
/// [peerNumber] é sempre o número virtual da OUTRA pessoa na conversa
/// (independente de [outgoing]) — é a chave usada para agrupar em
/// conversas e para abrir uma thread específica.
///
/// Guardada na box com chave = [remoteId] (uuid da linha em
/// `public.messages` no Supabase) — usar a mesma chave em `put()`
/// automaticamente evita duplicar mensagem que já existe.
class LocalMessage {
  const LocalMessage({
    required this.remoteId,
    required this.peerNumber,
    required this.peerUserId,
    required this.content,
    required this.outgoing,
    required this.sentAt,
    required this.delivered,
    required this.read,
  });

  final String remoteId;
  final String peerNumber;
  final String peerUserId;
  final String content;

  /// true = eu enviei; false = eu recebi.
  final bool outgoing;

  final DateTime sentAt;
  final bool delivered;

  /// Relevante só para mensagens recebidas (outgoing = false).
  final bool read;

  LocalMessage copyWith({bool? read}) {
    return LocalMessage(
      remoteId: remoteId,
      peerNumber: peerNumber,
      peerUserId: peerUserId,
      content: content,
      outgoing: outgoing,
      sentAt: sentAt,
      delivered: delivered,
      read: read ?? this.read,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'remoteId': remoteId,
      'peerNumber': peerNumber,
      'peerUserId': peerUserId,
      'content': content,
      'outgoing': outgoing,
      'sentAt': sentAt.toIso8601String(),
      'delivered': delivered,
      'read': read,
    };
  }

  factory LocalMessage.fromMap(Map<String, dynamic> map) {
    return LocalMessage(
      remoteId: map['remoteId'] as String,
      peerNumber: map['peerNumber'] as String,
      peerUserId: map['peerUserId'] as String,
      content: map['content'] as String,
      outgoing: map['outgoing'] as bool,
      sentAt: DateTime.parse(map['sentAt'] as String),
      delivered: map['delivered'] as bool,
      read: map['read'] as bool,
    );
  }
}
