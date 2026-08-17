import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/call_history_record.dart';

/// Cria/atualiza linhas em `calls` e aciona a Edge Function que dispara
/// o push de "chamada recebida". NÃO faz a sinalização WebRTC (SDP/ICE)
/// — isso é o próximo passo, depois que a UI de chamada nativa estiver
/// funcionando ponta a ponta.
class CallSignalingRepository {
  CallSignalingRepository({required this.supabase});

  final SupabaseClient supabase;

  /// Usuário A ligando para o Usuário B. Cria a chamada e já dispara o
  /// push (chamada direta à Edge Function, do próprio app de quem liga
  /// — como combinado, sem trigger no banco).
  Future<String> placeCall({
    required String callerNumber,
    required String callerName,
    required String calleeUserId,
    required String calleeNumber,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Usuário não autenticado');
    }

    final row = await supabase
        .from('calls')
        .insert({
          'caller_id': userId,
          'caller_number': callerNumber,
          'caller_name': callerName,
          'callee_id': calleeUserId,
          'callee_number': calleeNumber,
          'status': 'ringing',
        })
        .select('id')
        .single();

    final callId = row['id'] as String;

    // O push é "melhor esforço": se a Edge Function falhar (fora do
    // ar, sem token FCM cadastrado, etc.), a CHAMADA em si não pode
    // morrer por causa disso — a linha em `calls` já existe e quem
    // ligou já está esperando na tela "Chamando...", observando o
    // status via Realtime. Callee sem push só não recebe o card nativo
    // (mas ainda pode ver a chamada se o app dele estiver aberto).
    try {
      await supabase.functions.invoke(
        'trigger-call-push',
        body: {'call_id': callId},
      );
    } catch (error) {
      // ignore: intencional — ver comentário acima.
    }

    return callId;
  }

  Future<void> updateStatus({
    required String callId,
    required String status,
  }) async {
    final updates = <String, dynamic>{'status': status};
    if (status == 'accepted') {
      updates['answered_at'] = DateTime.now().toIso8601String();
    }
    if (status == 'ended' || status == 'declined' || status == 'missed') {
      updates['ended_at'] = DateTime.now().toIso8601String();
    }

    await supabase.from('calls').update(updates).eq('id', callId);
  }

  /// Observa o status de UMA chamada em tempo real — usado por quem
  /// LIGOU, para saber quando o outro lado aceitou/recusou.
  Stream<Map<String, dynamic>> watchCall(String callId) {
    return supabase
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('id', callId)
        .map((rows) => rows.isEmpty ? <String, dynamic>{} : rows.first);
  }

  /// Histórico real de chamadas (feitas e recebidas), lido direto da
  /// tabela `calls` — substitui o histórico antigo baseado em SIP
  /// (`_callHistory`/`_voip`), que nunca era populado pelas chamadas
  /// WebRTC app2app reais deste app.
  Future<List<CallHistoryRecord>> fetchMyCallHistory() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final rows = await supabase
        .from('calls')
        .select()
        .or('caller_id.eq.$userId,callee_id.eq.$userId')
        .order('created_at', ascending: false)
        .limit(100);

    return (rows as List<dynamic>)
        .map(
          (row) =>
              CallHistoryRecord.fromMap(row as Map<String, dynamic>, userId),
        )
        .toList();
  }
}
