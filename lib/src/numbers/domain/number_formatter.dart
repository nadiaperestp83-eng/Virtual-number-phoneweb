/// Utilitário central para formatação de números virtuais.
///
/// REGRA DE OURO: número de telefone é SEMPRE String. Nunca convertemos
/// para int/double em nenhum ponto do app — isso evita perda de zeros à
/// esquerda e formatação quebrada.
///
/// Formato de exibição: (DDD) 9XXXX-XXXX
/// Formato bruto (armazenado): apenas dígitos, ex: "11960001234"
class NumberFormatter {
  NumberFormatter._();

  /// Prefixo dedicado que identifica um número como pertencente à rede
  /// virtual do app (assinatura visual: "6000").
  static const String networkPrefix = '6000';

  /// Recebe um número bruto (somente dígitos, ex: "11960001234")
  /// e retorna o formato de exibição "(11) 96000-1234".
  static String toDisplay(String raw) {
    final digits = onlyDigits(raw);
    if (digits.length != 11) {
      // Fallback defensivo: devolve como veio, sem tentar "consertar".
      return raw;
    }
    final ddd = digits.substring(0, 2);
    final firstPart = digits.substring(2, 7); // "9" + "6000"
    final lastPart = digits.substring(7, 11); // "XXXX"
    return '($ddd) $firstPart-$lastPart';
  }

  /// Remove qualquer caractere que não seja dígito. Sempre retorna String.
  static String onlyDigits(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Extrai o DDD (2 primeiros dígitos) de um número bruto.
  static String extractDdd(String raw) {
    final digits = onlyDigits(raw);
    if (digits.length < 2) return '';
    return digits.substring(0, 2);
  }

  /// Valida se um número bruto segue o padrão da rede virtual:
  /// DDD (2) + 9 + 6000 (prefixo fixo) + 4 dígitos = 11 dígitos.
  static bool isValidVirtualNumber(String raw) {
    final digits = onlyDigits(raw);
    if (digits.length != 11) return false;
    final marker = digits.substring(3, 7); // posições do "6000"
    return digits[2] == '9' && marker == networkPrefix;
  }
}
