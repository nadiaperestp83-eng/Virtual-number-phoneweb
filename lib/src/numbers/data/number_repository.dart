import 'package:isar/isar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/local_virtual_number.dart';
import '../domain/number_formatter.dart';

/// Representa uma opção de número disponível, vinda do pool remoto,
/// antes de o usuário escolher (ainda não é "dele").
class NumberOption {
  const NumberOption({
    required this.id,
    required this.ddd,
    required this.number,
    required this.formatted,
  });

  final String id; // uuid da linha em virtual_numbers
  final String ddd;
  final String number;
  final String formatted;

  factory NumberOption.fromMap(Map<String, dynamic> map) {
    return NumberOption(
      id: map['id'] as String,
      ddd: map['ddd'] as String,
      number: map['number'] as String,
      formatted: map['formatted'] as String,
    );
  }
}

class NumberRepository {
  NumberRepository({required this.supabase, required this.isar});

  final SupabaseClient supabase;
  final Isar isar;

  /// Busca 3-4 opções de número disponíveis para o DDD escolhido,
  /// via a função `list_available_numbers` (RPC) do Supabase.
  Future<List<NumberOption>> fetchAvailableNumbers({
    required String ddd,
    int limit = 4,
  }) async {
    final response = await supabase.rpc(
      'list_available_numbers',
      params: {'p_ddd': ddd, 'p_limit': limit},
    ) as List<dynamic>;

    return response
        .map((row) => NumberOption.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Reivindica (ativa) um número escolhido pelo usuário, de forma
  /// atômica no backend (`claim_virtual_number`), e grava o resultado
  /// no cache local (Isar) para acesso offline instantâneo.
  Future<LocalVirtualNumber> claimNumber(String numberOptionId) async {
    final response = await supabase.rpc(
      'claim_virtual_number',
      params: {'p_number_id': numberOptionId},
    );

    final row = response as Map<String, dynamic>;

    final local = LocalVirtualNumber(
      remoteId: row['id'] as String,
      ddd: row['ddd'] as String,
      number: row['number'] as String,
      formatted:
          (row['formatted'] as String?) ??
          NumberFormatter.toDisplay(row['number'] as String),
      activatedAt: DateTime.parse(row['activated_at'] as String),
      lastInteractionAt: DateTime.parse(row['last_interaction_at'] as String),
    );

    await isar.writeTxn(() async {
      await isar.localVirtualNumbers.put(local);
    });

    return local;
  }

  /// Retorna o número ativo salvo localmente (ou null se não houver).
  Future<LocalVirtualNumber?> getLocalActiveNumber() {
    return isar.localVirtualNumbers.get(1);
  }

  /// Deve ser chamado sempre que o usuário envia/recebe chamada ou
  /// mensagem: reseta a contagem dos 7 dias de inatividade no backend
  /// e atualiza o timestamp local.
  Future<void> markInteraction() async {
    await supabase.rpc('touch_my_number');

    final current = await getLocalActiveNumber();
    if (current != null) {
      current.lastInteractionAt = DateTime.now();
      await isar.writeTxn(() async {
        await isar.localVirtualNumbers.put(current);
      });
    }
  }
}
