import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Registra o token FCM deste aparelho em `device_push_tokens`, para que
/// a Edge Function `trigger-call-push` consiga encontrar pra onde
/// mandar o push de chamada recebida.
class PushTokenRepository {
  PushTokenRepository({required this.supabase, required this.messaging});

  final SupabaseClient supabase;
  final FirebaseMessaging messaging;

  /// Pede permissão de notificação (Android 13+ exige isso
  /// explicitamente) e salva o token atual + assina atualizações
  /// futuras (o token pode mudar ao longo da vida do app).
  Future<void> registerAndKeepInSync({required String userId}) async {
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    final token = await messaging.getToken();
    if (token != null) {
      await _saveToken(userId: userId, token: token);
    }

    messaging.onTokenRefresh.listen((newToken) {
      _saveToken(userId: userId, token: newToken);
    });
  }

  Future<void> _saveToken({required String userId, required String token}) async {
    await supabase.from('device_push_tokens').upsert({
      'fcm_token': token,
      'user_id': userId,
      'platform': 'android',
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Chamar no logout, para não continuar recebendo push de chamada
  /// destinado a uma conta que não é mais a logada neste aparelho.
  Future<void> removeCurrentToken() async {
    final token = await messaging.getToken();
    if (token == null) return;
    await supabase.from('device_push_tokens').delete().eq('fcm_token', token);
  }
}
