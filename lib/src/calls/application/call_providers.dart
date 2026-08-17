import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';
import '../data/call_signaling_repository.dart';
import '../data/push_token_repository.dart';
import '../domain/call_history_record.dart';
import '../domain/incoming_call_payload.dart';
import 'callkit_service.dart';

final firebaseMessagingProvider = Provider<FirebaseMessaging>((ref) {
  return FirebaseMessaging.instance;
});

final pushTokenRepositoryProvider = Provider<PushTokenRepository>((ref) {
  return PushTokenRepository(
    supabase: ref.watch(supabaseClientProvider),
    messaging: ref.watch(firebaseMessagingProvider),
  );
});

final callSignalingRepositoryProvider = Provider<CallSignalingRepository>((
  ref,
) {
  return CallSignalingRepository(supabase: ref.watch(supabaseClientProvider));
});

final callHistoryProvider = FutureProvider<List<CallHistoryRecord>>((
  ref,
) async {
  final repo = ref.watch(callSignalingRepositoryProvider);
  return repo.fetchMyCallHistory();
});

/// Única instância do serviço de CallKit para todo o app.
final callKitServiceProvider = Provider<CallKitService>((ref) {
  return CallKitService();
});

/// Efeito colateral: registra o token de push + liga o listener de
/// eventos do CallKit (atender/recusar -> atualiza `calls` no
/// Supabase). Observado uma vez em `main.dart`.
final callsBootstrapProvider = FutureProvider<void>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return;

  final pushTokenRepo = ref.watch(pushTokenRepositoryProvider);
  await pushTokenRepo.registerAndKeepInSync(userId: user.id);

  final callKit = ref.watch(callKitServiceProvider);
  final callRepo = ref.watch(callSignalingRepositoryProvider);

  callKit.events.listen((event) {
    if (event.supabaseCallId.isEmpty) return;
    switch (event.action) {
      case CallKitAction.accepted:
        callRepo.updateStatus(callId: event.supabaseCallId, status: 'accepted');
        // TODO Fase 3.2 (WebRTC): a partir daqui entra a troca de SDP
        // offer/answer via Realtime Broadcast e a abertura do
        // RTCPeerConnection — combinado que isso é o próximo passo.
        break;
      case CallKitAction.declined:
        callRepo.updateStatus(callId: event.supabaseCallId, status: 'declined');
        break;
      case CallKitAction.missed:
        callRepo.updateStatus(callId: event.supabaseCallId, status: 'missed');
        break;
      case CallKitAction.ended:
        callRepo.updateStatus(callId: event.supabaseCallId, status: 'ended');
        break;
      case CallKitAction.other:
        break;
    }
    ref.invalidate(callHistoryProvider);
  });

  // Mensagem de chamada chegando com o APP ABERTO (foreground). Em
  // background, quem trata é `firebaseMessagingBackgroundHandler`
  // (função top-level, registrada em main.dart antes do runApp).
  FirebaseMessaging.onMessage.listen((message) {
    final payload = IncomingCallPayload.tryParse(message.data);
    if (payload != null) {
      callKit.showIncomingCall(payload);
    }
  });
});
