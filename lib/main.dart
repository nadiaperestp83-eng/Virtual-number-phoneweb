import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'phoneweb_app.dart';
import 'src/account/presentation/ddd_selection_screen.dart';
import 'src/account/presentation/login_screen.dart';
import 'src/calls/application/call_providers.dart';
import 'src/chat/application/chat_providers.dart';
import 'src/core/app_theme.dart';
import 'src/core/env.dart';
import 'src/core/firebase_background_handler.dart';
import 'src/core/local_db.dart';
import 'src/core/supabase_providers.dart';
import 'src/numbers/application/number_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase (push de chamada recebida). No Android, lê o
  // google-services.json sozinho via o plugin Gradle.
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Supabase (login real e-mail/senha — sem sessão anônima).
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  // Banco local (Hive CE) — guarda o número virtual ativo e o cache
  // do chat neste aparelho.
  final localDb = await openLocalDb();

  runApp(
    ProviderScope(
      overrides: [
        localDbProvider.overrideWithValue(localDb),
      ],
      child: const VNumeroGate(),
    ),
  );
}

/// Porta de entrada do app. NÃO substitui nem reescreve `PhoneWebApp`
/// (o app real do fork, em `phoneweb_app.dart`) — apenas decide o que
/// mostrar ANTES dele:
///
///   1. Sem sessão Supabase -> LoginScreen (e-mail/senha)
///   2. Sessão ok, mas sem número virtual salvo localmente -> onboarding
///      (escolha de DDD + número)
///   3. Sessão ok + número ativo -> `PhoneWebApp()`, o app original do
///      fork, sem nenhuma alteração.
///
/// Nada aqui toca em `WebRtcAccount`/SIP — combinado que isso fica para
/// depois.
class VNumeroGate extends ConsumerWidget {
  const VNumeroGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    if (user == null) {
      return const _GateApp(home: LoginScreen());
    }

    final activeNumberAsync = ref.watch(activeNumberProvider);

    return activeNumberAsync.when(
      loading: () => const _GateApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      error: (error, _) => _GateApp(
        home: Scaffold(body: Center(child: Text('Erro: $error'))),
      ),
      data: (activeNumber) {
        if (activeNumber == null) {
          return const _GateApp(home: DddSelectionScreen());
        }
        // Usuário logado + número ativo: entra no app real do fork.
        // (efeitos colaterais: assina o Realtime de mensagens e
        // registra o token de push + listener do CallKit)
        ref.watch(chatBootstrapProvider);
        ref.watch(callsBootstrapProvider);
        return const PhoneWebApp();
      },
    );
  }
}

/// MaterialApp mínimo usado apenas nas telas de login/onboarding, antes
/// de o `PhoneWebApp` (que já define seu próprio MaterialApp/tema)
/// assumir a tela.
class _GateApp extends StatelessWidget {
  const _GateApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TALK',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: home,
    );
  }
}
