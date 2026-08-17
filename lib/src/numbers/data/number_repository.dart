import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/local_db.dart';
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
  NumberRepository({required this.supabase, required this.localDb});

  final SupabaseClient supabase;
  final LocalDb localDb;

  static const _activeKey = 'active';

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
  /// no cache local (Hive) para acesso offline instantâneo.
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

    await localDb.virtualNumberBox.put(_activeKey, local.toMap());
    return local;
  }

  /// Retorna o número ativo do usuário. FONTE DE VERDADE = Supabase,
  /// sempre consultado primeiro (não é "cache que a gente confia" —
  /// é a identidade real da conta, e precisa refletir a regra dos 7
  /// dias de expiração corretamente). O Hive só entra como fallback de
  /// LEITURA quando não há rede — nunca decide sozinho que o usuário
  /// tem um número.
  Future<LocalVirtualNumber?> getActiveNumber() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final rows = await supabase
          .from('virtual_numbers')
          .select(
            'id, ddd, number, formatted, activated_at, last_interaction_at',
          )
          .eq('owner_id', userId)
          .eq('status', 'active')
          .limit(1);

      if (rows.isEmpty) {
        // Servidor confirma: esta conta não tem número ativo agora
        // (nunca teve, ou expirou pela regra dos 7 dias). Limpa
        // qualquer cache local desatualizado — estado vira "Sem Conta"
        // de verdade, não erro de cache.
        await localDb.virtualNumberBox.delete(_activeKey);
        return null;
      }

      final row = rows.first as Map<String, dynamic>;
      final fromServer = LocalVirtualNumber(
        remoteId: row['id'] as String,
        ddd: row['ddd'] as String,
        number: row['number'] as String,
        formatted: row['formatted'] as String,
        activatedAt: DateTime.parse(row['activated_at'] as String),
        lastInteractionAt: DateTime.parse(
          row['last_interaction_at'] as String,
        ),
      );

      await localDb.virtualNumberBox.put(_activeKey, fromServer.toMap());
      return fromServer;
    } catch (error) {
      // Sem rede / Supabase indisponível no momento: cai pro cache
      // local só para não travar o app offline. Assim que a rede
      // voltar, a próxima chamada revalida contra o servidor de novo.
      //
      // IMPORTANTE: isso também "engole" erros de permissão (ex: GRANT
      // faltando na tabela) — se isso acontecer, o log abaixo é o
      // único jeito de perceber, porque o efeito colateral (cai pro
      // cache vazio num reinstall) parece só "esqueceu meu número".
      // ignore: avoid_print
      print('[VNumero:getActiveNumber] falhou, usando cache local. Erro: $error');
      final raw = localDb.virtualNumberBox.get(_activeKey);
      if (raw == null) return null;
      return LocalVirtualNumber.fromMap(Map<String, dynamic>.from(raw));
    }
  }

  /// Deve ser chamado sempre que o usuário envia/recebe chamada ou
  /// mensagem: reseta a contagem dos 7 dias de inatividade no backend
  /// e atualiza o timestamp local.
  Future<void> markInteraction() async {
    await supabase.rpc('touch_my_number');

    final current = await getActiveNumber();
    if (current != null) {
      final updated = current.copyWith(lastInteractionAt: DateTime.now());
      await localDb.virtualNumberBox.put(_activeKey, updated.toMap());
    }
  }

  /// Troca de número: só funciona se o número atual já estiver ativo
  /// há 7 dias ou mais (o servidor valida e recusa se for cedo demais
  /// — mensagem de erro do Postgres já vem pronta pra mostrar ao
  /// usuário). Depois de liberar, limpa o cache local — a próxima
  /// leitura de `activeNumberProvider` vai dar null e mandar o app
  /// pro onboarding de escolha de novo número.
  Future<void> releaseMyNumberForChange() async {
    await supabase.rpc('release_my_number_for_change');
    await localDb.virtualNumberBox.delete(_activeKey);
  }

  /// Desativa a conta: libera o número IMEDIATAMENTE (sem esperar os
  /// 7 dias), sem apagar o login do Supabase Auth. Quem chama isso
  /// (AccountSettingsScreen) é responsável por deslogar em seguida.
  Future<void> deactivateAccount() async {
    await supabase.rpc('deactivate_my_account');
    await localDb.virtualNumberBox.delete(_activeKey);
  }
}
