import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/core/env.dart';
import 'src/core/local_db.dart';
import 'src/core/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Supabase (sem login anônimo — autenticação real via LoginScreen,
  //    e-mail/senha, ver lib/src/account/presentation/login_screen.dart)
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  // 2. Banco local (Isar)
  final isar = await openLocalDb();

  runApp(
    ProviderScope(
      overrides: [
        localDbProvider.overrideWithValue(isar),
      ],
      child: const VNumeroApp(),
    ),
  );
}

class VNumeroApp extends ConsumerWidget {
  const VNumeroApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'VNumero',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
