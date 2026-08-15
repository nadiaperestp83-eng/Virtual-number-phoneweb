import 'dart:async';

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:uuid/uuid.dart';

import '../domain/incoming_call_payload.dart';

/// Fininho em cima do `flutter_callkit_incoming`: mostra o card nativo
/// (igual ao print "Incoming Call · Matthew") e expõe um Stream com as
/// ações do usuário (atendeu, recusou, encerrou).
class CallKitService {
  final _uuid = const Uuid();

  /// UUID interno do CallKit para a chamada atualmente exibida — não é
  /// o mesmo id da linha em `calls` no Supabase (guardamos os dois:
  /// `_activeCallKitId` -> `callId` do Supabase).
  String? _activeCallKitId;
  String? _activeSupabaseCallId;

  String? get activeSupabaseCallId => _activeSupabaseCallId;

  Future<void> showIncomingCall(IncomingCallPayload payload) async {
    final callKitId = _uuid.v4();
    _activeCallKitId = callKitId;
    _activeSupabaseCallId = payload.callId;

    final params = CallKitParams(
      id: callKitId,
      nameCaller: payload.callerName,
      handle: payload.callerNumber,
      type: 0, // 0 = chamada de voz
      duration: 30000, // encerra sozinho se ninguém responder em 30s
      textAccept: 'Atender',
      textDecline: 'Recusar',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Chamada perdida',
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0D1B2A',
        actionColor: '#4CAF50',
        incomingCallNotificationChannelName: 'Chamadas recebidas',
        isShowFullLockedScreen: true,
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  Future<void> endActiveCall() async {
    if (_activeCallKitId == null) return;
    await FlutterCallkitIncoming.endCall(_activeCallKitId!);
    _activeCallKitId = null;
    _activeSupabaseCallId = null;
  }

  /// Stream normalizado das ações do usuário no card nativo.
  /// Ver `CallKitAction` abaixo para o significado de cada valor.
  Stream<CallKitEvent> get events {
    return FlutterCallkitIncoming.onEvent
        .where((event) => event != null)
        .map((event) => _mapEvent(event!));
  }

  CallKitEvent _mapEvent(CallEvent event) {
    final supabaseCallId = _activeSupabaseCallId ?? '';

    switch (event.event) {
      case Event.actionCallAccept:
        return CallKitEvent(CallKitAction.accepted, supabaseCallId);
      case Event.actionCallDecline:
        _activeCallKitId = null;
        _activeSupabaseCallId = null;
        return CallKitEvent(CallKitAction.declined, supabaseCallId);
      case Event.actionCallTimeout:
        _activeCallKitId = null;
        _activeSupabaseCallId = null;
        return CallKitEvent(CallKitAction.missed, supabaseCallId);
      case Event.actionCallEnded:
        _activeCallKitId = null;
        _activeSupabaseCallId = null;
        return CallKitEvent(CallKitAction.ended, supabaseCallId);
      default:
        return CallKitEvent(CallKitAction.other, supabaseCallId);
    }
  }
}

enum CallKitAction { accepted, declined, missed, ended, other }

class CallKitEvent {
  const CallKitEvent(this.action, this.supabaseCallId);

  final CallKitAction action;
  final String supabaseCallId;
}
