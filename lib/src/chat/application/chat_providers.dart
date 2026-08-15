import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local_db.dart';
import '../../core/supabase_providers.dart';
import '../../numbers/application/number_providers.dart';
import '../data/chat_repository.dart';
import '../domain/conversation_summary.dart';
import '../domain/local_message.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(
    supabase: ref.watch(supabaseClientProvider),
    isar: ref.watch(localDbProvider),
    numberRepository: ref.watch(numberRepositoryProvider),
  );
});

final conversationsProvider = StreamProvider<List<ConversationSummary>>((ref) {
  final repo = ref.watch(chatRepositoryProvider);
  return repo.watchConversations();
});

final threadMessagesProvider = StreamProvider.family<List<LocalMessage>, String>(
  (ref, peerNumber) {
    final repo = ref.watch(chatRepositoryProvider);
    return repo.watchThread(peerNumber);
  },
);

/// Efeito colateral: assina o Realtime assim que houver usuário logado.
/// Observado uma vez em `main.dart`, logo antes de mostrar `PhoneWebApp`.
///
/// LIMITAÇÃO CONHECIDA (ok para esta fase): não cancela a assinatura no
/// logout. Antes de ir para produção, ligar isso a um listener de
/// `authStateChangesProvider` que chama `stopListening()` no signOut.
final chatBootstrapProvider = FutureProvider<void>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return;
  final repo = ref.watch(chatRepositoryProvider);
  await repo.startListening(myUserId: user.id);
});
