import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local_db.dart';
import '../../core/supabase_providers.dart';
import '../data/number_repository.dart';
import '../domain/local_virtual_number.dart';

final numberRepositoryProvider = Provider<NumberRepository>((ref) {
  return NumberRepository(
    supabase: ref.watch(supabaseClientProvider),
    localDb: ref.watch(localDbProvider),
  );
});

/// Número virtual ativo do usuário neste aparelho (lido do cache local).
/// Retorna `null` enquanto carrega ou se o usuário ainda não tem número.
final activeNumberProvider = FutureProvider<LocalVirtualNumber?>((ref) async {
  final repo = ref.watch(numberRepositoryProvider);
  return repo.getActiveNumber();
});

/// Estado (loading/data/error) da busca de opções de número por DDD.
/// Uso: `ref.read(numberOptionsProvider(ddd).future)`.
final numberOptionsProvider = FutureProvider.family<List<NumberOption>, String>(
  (ref, ddd) async {
    final repo = ref.watch(numberRepositoryProvider);
    return repo.fetchAvailableNumbers(ddd: ddd);
  },
);
