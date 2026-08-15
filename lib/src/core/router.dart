import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../account/presentation/ddd_selection_screen.dart';
import '../account/presentation/login_screen.dart';
import '../account/presentation/number_choice_screen.dart';
import '../numbers/application/number_providers.dart';
import '../numbers/presentation/number_status_screen.dart';
import '../shared/screens/stub_screens.dart';
import '../shared/widgets/app_shell.dart';
import 'supabase_providers.dart';

/// Faz o go_router reavaliar `redirect` sempre que o estado de
/// autenticação do Supabase mudar (login, logout, expiração de sessão).
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final supabase = ref.watch(supabaseClientProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: GoRouterRefreshStream(
      supabase.auth.onAuthStateChange,
    ),
    redirect: (context, state) async {
      final loggedIn = supabase.auth.currentSession != null;
      final goingToLogin = state.matchedLocation == '/login';

      // Não autenticado: só pode estar na tela de login.
      if (!loggedIn) {
        return goingToLogin ? null : '/login';
      }

      // Autenticado e ainda na tela de login: decide para onde ir
      // com base em já existir (ou não) um número virtual salvo
      // localmente neste aparelho.
      if (goingToLogin) {
        final repo = ref.read(numberRepositoryProvider);
        final active = await repo.getLocalActiveNumber();
        return active != null ? '/app' : '/onboarding';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const DddSelectionScreen(),
      ),
      GoRoute(
        path: '/onboarding/numbers/:ddd',
        builder: (context, state) => NumberChoiceScreen(
          ddd: state.pathParameters['ddd']!,
        ),
      ),
      GoRoute(
        path: '/app',
        builder: (context, state) => const AppShell(
          tabs: [
            KeypadScreen(),
            MessagesScreen(),
            NumberStatusScreen(),
            HistoryScreen(),
            ContactsScreen(),
          ],
        ),
      ),
    ],
  );
});
