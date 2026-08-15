import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// Guarda as "boxes" (equivalente a tabelas) do Hive CE já abertas.
///
/// Por que Hive CE em vez de Isar: Isar (`isar_flutter_libs`) trava
/// build em `compileSdk` mais novos do Android — problema crônico e
/// recorrente do pacote. Hive CE é ativamente mantido e não tem essa
/// exigência de plugin nativo complicado.
///
/// Por que sem geração de código (sem `TypeAdapter`/`build_runner`):
/// guardamos cada registro como `Map<String, dynamic>` simples
/// (serializado manualmente via `toMap()`/`fromMap()` em cada modelo).
/// Menos peças = menos chance de quebrar o build. Para o volume de
/// dados deste app (1 número ativo, histórico de chat local), isso é
/// mais que suficiente em performance.
class LocalDb {
  LocalDb({required this.virtualNumberBox, required this.messagesBox});

  /// 1 registro só (chave fixa `'active'`) — o número virtual deste
  /// aparelho.
  final Box<Map> virtualNumberBox;

  /// N registros, uma mensagem de chat por entrada (chave = `remoteId`,
  /// o uuid da linha em `public.messages` no Supabase).
  final Box<Map> messagesBox;
}

Future<LocalDb> openLocalDb() async {
  await Hive.initFlutter();
  final virtualNumberBox = await Hive.openBox<Map>('virtual_number');
  final messagesBox = await Hive.openBox<Map>('messages');
  return LocalDb(virtualNumberBox: virtualNumberBox, messagesBox: messagesBox);
}

/// Deve ser sobrescrito em main.dart com `overrideWithValue` após
/// `await openLocalDb()`, pois a abertura é assíncrona.
final localDbProvider = Provider<LocalDb>((ref) {
  throw UnimplementedError(
    'localDbProvider precisa ser sobrescrito em main.dart após openLocalDb()',
  );
});
