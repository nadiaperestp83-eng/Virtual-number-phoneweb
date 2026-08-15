import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../calls/application/callkit_service.dart';
import '../calls/domain/incoming_call_payload.dart';

/// OBRIGATÓRIO ser uma função top-level (ou estática) marcada com este
/// `@pragma` — o Firebase roda isso num isolate Dart separado quando o
/// app está fechado/em background, então ela não tem acesso a nenhum
/// estado do resto do app (nem Riverpod, nem Supabase client já
/// inicializado). Por isso ela reinicializa o Firebase sozinha.
///
/// Escopo atual = só Android: `Firebase.initializeApp()` sem
/// `options:` funciona porque o plugin Gradle do Google Services lê o
/// `google-services.json` automaticamente. Se/quando entrar iOS, vai
/// precisar gerar `lib/firebase_options.dart` (via `flutterfire
/// configure`) e passar `options: DefaultFirebaseOptions.currentPlatform`
/// aqui.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final payload = IncomingCallPayload.tryParse(message.data);
  if (payload == null) return;

  // Não passa por Riverpod aqui (isolate isolado) — usa o serviço
  // diretamente. `flutter_callkit_incoming` funciona em background
  // porque é uma plugin nativa (não depende do isolate Dart principal
  // pra desenhar a UI).
  await CallKitService().showIncomingCall(payload);
}
