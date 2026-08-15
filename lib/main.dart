import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'phoneweb_app.dart';
import 'src/account/presentation/ddd_selection_screen.dart';
import 'src/account/presentation/login_screen.dart';
import 'src/chat/application/chat_providers.dart';
import 'src/core/env.dart';
import 'src/core/local_db.dart';
import 'src/core/supabase_providers.dart';
import 'src/numbers/application/number_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Supabase (login real e-mail/senha — sem sessão anônima).
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  // Banco local (Isar) — guarda o número virtual ativo neste aparelho.
  final isar = await openLocalDb();

  runApp(
    ProviderScope(
      overrides: [
        localDbProvider.overrideWithValue(isar),
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
        // (efeito colateral: assina o Realtime de mensagens — ver
        // chatBootstrapProvider)
        ref.watch(chatBootstrapProvider);
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
      title: 'VNumero',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: home,
    );
  }
}
