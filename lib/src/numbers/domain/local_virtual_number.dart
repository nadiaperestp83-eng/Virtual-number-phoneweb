import 'package:isar/isar.dart';

part 'local_virtual_number.g.dart';

/// Representa, localmente, o número virtual vinculado a este aparelho.
///
/// Existe no máximo 1 registro ativo por vez (id fixo = 1), já que cada
/// aparelho tem apenas um número virtual ativo por sua vez.
///
/// IMPORTANTE: [number] e [ddd] são sempre String — nunca armazenar como
/// int (ver NumberFormatter para a regra completa).
@collection
class LocalVirtualNumber {
  LocalVirtualNumber({
    required this.remoteId,
    required this.ddd,
    required this.number,
    required this.formatted,
    required this.activatedAt,
    required this.lastInteractionAt,
  });

  /// Isar exige um id numérico; usamos sempre 1 (registro único).
  Id id = 1;

  /// UUID do registro em `public.virtual_numbers` no Supabase.
  @Index(unique: true)
  late String remoteId;

  /// DDD como String (ex: "35"). Nunca int.
  late String ddd;

  /// Número bruto, somente dígitos, como String (ex: "35960001234").
  late String number;

  /// Cache do número já formatado para exibição: "(35) 96000-1234".
  late String formatted;

  late DateTime activatedAt;

  late DateTime lastInteractionAt;
}
