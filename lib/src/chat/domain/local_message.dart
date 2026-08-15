import 'package:isar/isar.dart';

part 'local_message.g.dart';

/// Mensagem de chat, em cache local (Isar).
///
/// [peerNumber] é sempre o número virtual da OUTRA pessoa na conversa
/// (independente de [outgoing]) — é a chave usada para agrupar em
/// conversas e para abrir uma thread específica.
@collection
class LocalMessage {
  Id id = Isar.autoIncrement;

  /// UUID da linha em `public.messages` no Supabase.
  @Index(unique: true)
  late String remoteId;

  /// Número virtual (String) da outra pessoa na conversa.
  @Index()
  late String peerNumber;

  /// user_id (Supabase Auth) da outra pessoa — usado para novas mensagens.
  late String peerUserId;

  late String content;

  /// true = eu enviei; false = eu recebi.
  late bool outgoing;

  late DateTime sentAt;

  late bool delivered;

  /// Relevante só para mensagens recebidas (outgoing = false).
  late bool read;
}
