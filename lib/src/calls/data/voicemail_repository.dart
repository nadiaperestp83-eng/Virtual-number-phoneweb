import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/voicemail.dart';

class VoicemailRepository {
  VoicemailRepository({required this.supabase});

  final SupabaseClient supabase;

  static const _bucket = 'voicemails';

  /// Sobe o arquivo de áudio gravado e cria a linha de metadados.
  /// [audioFile] fica em `{calleeId}/{uuid}.m4a` no Storage — só o
  /// próprio [calleeId] consegue ler esse caminho (RLS do bucket).
  Future<void> uploadVoicemail({
    required File audioFile,
    String? callId,
    required String callerNumber,
    required String callerName,
    required String calleeUserId,
    required String calleeNumber,
    required int durationSeconds,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Usuário não autenticado');

    final fileName = '${DateTime.now().millisecondsSinceEpoch}.m4a';
    final storagePath = '$calleeUserId/$fileName';

    await supabase.storage.from(_bucket).upload(storagePath, audioFile);

    await supabase.from('voicemails').insert({
      'call_id': callId,
      'caller_id': userId,
      'caller_number': callerNumber,
      'caller_name': callerName,
      'callee_id': calleeUserId,
      'callee_number': calleeNumber,
      'storage_path': storagePath,
      'duration_seconds': durationSeconds,
    });
  }

  /// Recados recebidos por mim, mais recentes primeiro.
  Future<List<Voicemail>> fetchMyVoicemails() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final rows = await supabase
        .from('voicemails')
        .select()
        .eq('callee_id', userId)
        .order('created_at', ascending: false);

    return (rows as List<dynamic>)
        .map((row) => Voicemail.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Quantidade de recados ainda não ouvidos — usado no selo da navbar.
  Future<int> fetchUnheardCount() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return 0;

    final rows = await supabase
        .from('voicemails')
        .select('id')
        .eq('callee_id', userId)
        .eq('listened', false);

    return (rows as List<dynamic>).length;
  }

  /// URL assinada e temporária pra tocar o áudio (o bucket é privado).
  Future<String> getPlaybackUrl(String storagePath) async {
    return supabase.storage
        .from(_bucket)
        .createSignedUrl(storagePath, 60 * 10); // válida por 10 min
  }

  Future<void> markListened(String voicemailId) async {
    await supabase
        .from('voicemails')
        .update({'listened': true})
        .eq('id', voicemailId);
  }

  Future<void> delete(String voicemailId, String storagePath) async {
    await supabase.from('voicemails').delete().eq('id', voicemailId);
    // Melhor esforço: se falhar (ex: policy, arquivo já sumiu), não
    // impede o recado de já ter sumido da lista pro usuário.
    try {
      await supabase.storage.from(_bucket).remove([storagePath]);
    } catch (_) {
      // ignore: já removido do banco, é o que importa pro usuário.
    }
  }
}
