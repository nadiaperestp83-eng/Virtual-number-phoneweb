/// Representa, localmente, o número virtual vinculado a este aparelho.
///
/// Guardado no Hive como `Map<String, dynamic>` puro — sem
/// `TypeAdapter` gerado, ver `local_db.dart` para o porquê.
///
/// IMPORTANTE: [number] e [ddd] são sempre String — nunca armazenar
/// como int (ver NumberFormatter para a regra completa).
class LocalVirtualNumber {
  const LocalVirtualNumber({
    required this.remoteId,
    required this.ddd,
    required this.number,
    required this.formatted,
    required this.activatedAt,
    required this.lastInteractionAt,
  });

  /// UUID do registro em `public.virtual_numbers` no Supabase.
  final String remoteId;

  /// DDD como String (ex: "35"). Nunca int.
  final String ddd;

  /// Número bruto, somente dígitos, como String (ex: "35960001234").
  final String number;

  /// Cache do número já formatado para exibição: "(35) 96000-1234".
  final String formatted;

  final DateTime activatedAt;

  final DateTime lastInteractionAt;

  LocalVirtualNumber copyWith({DateTime? lastInteractionAt}) {
    return LocalVirtualNumber(
      remoteId: remoteId,
      ddd: ddd,
      number: number,
      formatted: formatted,
      activatedAt: activatedAt,
      lastInteractionAt: lastInteractionAt ?? this.lastInteractionAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'remoteId': remoteId,
      'ddd': ddd,
      'number': number,
      'formatted': formatted,
      'activatedAt': activatedAt.toIso8601String(),
      'lastInteractionAt': lastInteractionAt.toIso8601String(),
    };
  }

  factory LocalVirtualNumber.fromMap(Map<String, dynamic> map) {
    return LocalVirtualNumber(
      remoteId: map['remoteId'] as String,
      ddd: map['ddd'] as String,
      number: map['number'] as String,
      formatted: map['formatted'] as String,
      activatedAt: DateTime.parse(map['activatedAt'] as String),
      lastInteractionAt: DateTime.parse(map['lastInteractionAt'] as String),
    );
  }
}
