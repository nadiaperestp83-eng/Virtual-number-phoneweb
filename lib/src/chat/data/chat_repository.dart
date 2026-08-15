import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/local_db.dart';
import '../../numbers/data/number_repository.dart';
import '../domain/conversation_summary.dart';
import '../domain/local_message.dart';

class ChatRepository {
  ChatRepository({
    required this.supabase,
    required this.localDb,
    required this.numberRepository,
  });

  final SupabaseClient supabase;
  final LocalDb localDb;
  final NumberRepository numberRepository;

  RealtimeChannel? _channel;

  /// Assina o canal Realtime do Supabase para receber mensagens novas
  /// endereçadas a este usuário. Chamar uma vez, assim que o usuário
  /// estiver logado e com número ativo (ver `chatBootstrapProvider`).
  Future<void> startListening({required String myUserId}) async {
    _channel?.unsubscribe();
    _channel = supabase
        .channel('messages-inbox-$myUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: myUserId,
          ),
          callback: (payload) => _cacheIncoming(payload.newRecord),
        )
        .subscribe();
  }

  void stopListening() {
    _channel?.unsubscribe();
    _channel = null;
  }

  Future<void> _cacheIncoming(Map<String, dynamic> row) async {
    final local = LocalMessage(
      remoteId: row['id'] as String,
      peerNumber: row['sender_number'] as String,
      peerUserId: row['sender_id'] as String,
      content: row['content'] as String,
      outgoing: false,
      sentAt: DateTime.parse(row['sent_at'] as String),
      delivered: true,
      read: false,
    );

    // Chave = remoteId -> put com a mesma chave já evita duplicar.
    await localDb.messagesBox.put(local.remoteId, local.toMap());

    // Recebeu mensagem: reseta a contagem dos 7 dias de inatividade.
    await numberRepository.markInteraction();
  }

  /// Descobre o `owner_id` (user_id) do dono ATUAL de um número virtual
  /// ativo, via a função `resolve_active_number` (security definer —
  /// necessária porque a policy de SELECT de `virtual_numbers` não deixa
  /// um usuário ver o número ativo de outro diretamente).
  Future<String?> resolveOwnerId(String peerNumber) async {
    final response =
        await supabase.rpc(
              'resolve_active_number',
              params: {'p_number': peerNumber},
            )
            as List<dynamic>;

    if (response.isEmpty) return null;
    return (response.first as Map<String, dynamic>)['owner_id'] as String?;
  }

  Future<void> sendMessage({
    required String myNumber,
    required String myUserId,
    required String peerNumber,
    required String content,
  }) async {
    final ownerId = await resolveOwnerId(peerNumber);
    if (ownerId == null) {
      throw Exception('Esse número não está ativo na rede no momento.');
    }

    final row = await supabase
        .from('messages')
        .insert({
          'sender_number': myNumber,
          'receiver_number': peerNumber,
          'sender_id': myUserId,
          'receiver_id': ownerId,
          'content': content,
        })
        .select()
        .single();

    final local = LocalMessage(
      remoteId: row['id'] as String,
      peerNumber: peerNumber,
      peerUserId: ownerId,
      content: content,
      outgoing: true,
      sentAt: DateTime.parse(row['sent_at'] as String),
      delivered: true,
      read: true,
    );

    await localDb.messagesBox.put(local.remoteId, local.toMap());

    // Enviou mensagem: reseta a contagem dos 7 dias de inatividade.
    await numberRepository.markInteraction();
  }

  List<LocalMessage> _allMessages() {
    return localDb.messagesBox.values
        .map((raw) => LocalMessage.fromMap(Map<String, dynamic>.from(raw)))
        .toList();
  }

  /// Mensagens de uma conversa específica, mais antiga -> mais recente.
  Stream<List<LocalMessage>> watchThread(String peerNumber) async* {
    List<LocalMessage> compute() {
      final list = _allMessages().where((m) => m.peerNumber == peerNumber).toList()
        ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
      return list;
    }

    yield compute();
    await for (final _ in localDb.messagesBox.watch()) {
      yield compute();
    }
  }

  /// Lista de conversas (uma por `peerNumber`), mais recente primeiro.
  Stream<List<ConversationSummary>> watchConversations() async* {
    List<ConversationSummary> compute() =>
        _groupIntoConversations(_allMessages());

    yield compute();
    await for (final _ in localDb.messagesBox.watch()) {
      yield compute();
    }
  }

  List<ConversationSummary> _groupIntoConversations(
    List<LocalMessage> allMessages,
  ) {
    final sorted = [...allMessages]
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt));

    final lastByPeer = <String, LocalMessage>{};
    final unreadByPeer = <String, int>{};

    for (final message in sorted) {
      lastByPeer.putIfAbsent(message.peerNumber, () => message);
      if (!message.outgoing && !message.read) {
        unreadByPeer.update(
          message.peerNumber,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }

    final summaries = lastByPeer.values.map((message) {
      return ConversationSummary(
        peerNumber: message.peerNumber,
        peerUserId: message.peerUserId,
        lastMessage: message.content,
        lastMessageAt: message.sentAt,
        unreadCount: unreadByPeer[message.peerNumber] ?? 0,
      );
    }).toList();

    summaries.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return summaries;
  }

  Future<void> markThreadRead(String peerNumber) async {
    final unread = _allMessages().where(
      (m) => m.peerNumber == peerNumber && !m.read,
    );

    for (final message in unread) {
      await localDb.messagesBox.put(
        message.remoteId,
        message.copyWith(read: true).toMap(),
      );
    }
  }
}
