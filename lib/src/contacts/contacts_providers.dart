import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'native_contacts_repository.dart';
import 'phone_contact.dart';

/// Ponte entre os módulos novos (VNumero) e a agenda do fork.
///
/// Reaproveita `NativeContactsRepository` (classe original do fork) em
/// vez de recriar leitura de contatos. Como combinado: é uma leitura
/// INDEPENDENTE do estado `_contacts` dentro de `PhoneWebHomePage`
/// (zero risco de mexer lá), então:
///   - Contatos SINCRONIZADOS DO DISPOSITIVO aparecem aqui normalmente.
///   - Contatos MANUAIS criados dentro do app (salvos via
///     `StandalonePhoneWebStore`, que não foi integrado aqui) NÃO
///     aparecem nesta lista — só na aba Contatos original.
///   - Se isso incomodar, o próximo passo é unificar as duas fontes.
final nativeContactsRepositoryProvider = Provider<NativeContactsRepository>((
  ref,
) {
  return NativeContactsRepository();
});

final deviceContactsProvider = FutureProvider<List<PhoneContact>>((ref) async {
  final repo = ref.watch(nativeContactsRepositoryProvider);
  final result = await repo.loadContacts();
  if (result.status == NativeContactsStatus.loaded) {
    return result.contacts;
  }
  return const [];
});

/// Resolve o nome salvo (se houver) para um número virtual, comparando
/// pelos últimos 8 dígitos — tolera diferenças de DDI/formatação entre
/// o número virtual (String, formato interno da rede) e o número salvo
/// na agenda do aparelho.
String? resolveContactName(List<PhoneContact> contacts, String rawNumber) {
  final digits = rawNumber.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 8) return null;
  final suffix = digits.substring(digits.length - 8);

  for (final contact in contacts) {
    final contactDigits = contact.number.replaceAll(RegExp(r'[^0-9]'), '');
    if (contactDigits.length >= 8 &&
        contactDigits.substring(contactDigits.length - 8) == suffix) {
      return contact.name;
    }
  }
  return null;
}
