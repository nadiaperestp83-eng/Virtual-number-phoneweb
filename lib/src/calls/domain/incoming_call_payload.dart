/// Payload que vem no push data-only (FCM) quando alguém está ligando.
/// Espelha exatamente o `data:` enviado pela Edge Function
/// `trigger-call-push` — ver `supabase/functions/trigger-call-push/index.ts`.
class IncomingCallPayload {
  const IncomingCallPayload({
    required this.callId,
    required this.callerId,
    required this.callerNumber,
    required this.callerName,
  });

  final String callId;
  final String callerId;
  final String callerNumber;
  final String callerName;

  static IncomingCallPayload? tryParse(Map<String, dynamic> data) {
    if (data['type'] != 'incoming_call') return null;
    final callId = data['call_id'] as String?;
    final callerId = data['caller_id'] as String?;
    final callerNumber = data['caller_number'] as String?;
    if (callId == null || callerId == null || callerNumber == null) {
      return null;
    }
    return IncomingCallPayload(
      callId: callId,
      callerId: callerId,
      callerNumber: callerNumber,
      callerName: (data['caller_name'] as String?) ?? callerNumber,
    );
  }
}
