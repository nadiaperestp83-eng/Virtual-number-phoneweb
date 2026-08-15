import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../chat/domain/local_message.dart';
import '../numbers/domain/local_virtual_number.dart';

/// Instância única do Isar, aberta em main.dart e exposta via provider.
///
/// Coleções atuais:
///   - LocalVirtualNumber (número virtual ativo no aparelho)
///   - LocalMessage (cache do chat)
///
/// Próximas fases adicionam aqui: LocalContact, LocalCallLogEntry.
Future<Isar> openLocalDb() async {
  final dir = await getApplicationDocumentsDirectory();
  return Isar.open(
    [LocalVirtualNumberSchema, LocalMessageSchema],
    directory: dir.path,
    name: 'vnumero_local',
  );
}

/// Deve ser sobrescrito em main.dart com `overrideWithValue` após
/// `await openLocalDb()`, pois a abertura é assíncrona.
final localDbProvider = Provider<Isar>((ref) {
  throw UnimplementedError(
    'localDbProvider precisa ser sobrescrito em main.dart após openLocalDb()',
  );
});
