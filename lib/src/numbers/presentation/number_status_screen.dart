import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/number_providers.dart';
import '../domain/local_virtual_number.dart';

class NumberStatusScreen extends ConsumerWidget {
  const NumberStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final numberAsync = ref.watch(activeNumberProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Minha Conta')),
      body: numberAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Erro: $err')),
        data: (number) {
          if (number == null) {
            return const Center(
              child: Text('Nenhum número virtual ativo neste aparelho.'),
            );
          }
          return _AccountDetails(number: number);
        },
      ),
    );
  }
}

class _AccountDetails extends StatelessWidget {
  const _AccountDetails({required this.number});

  final LocalVirtualNumber number;

  @override
  Widget build(BuildContext context) {
    final daysSinceInteraction =
        DateTime.now().difference(number.lastInteractionAt).inDays;
    final daysLeft = 7 - daysSinceInteraction;
    final expiring = daysLeft <= 2;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Número virtual',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  number.formatted,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Chip(label: Text('DDD ${number.ddd}')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: expiring
              ? Theme.of(context).colorScheme.errorContainer
              : null,
          child: ListTile(
            leading: Icon(expiring ? Icons.warning_amber : Icons.check_circle),
            title: Text(
              daysLeft > 0
                  ? 'Expira em $daysLeft dia(s) sem uso'
                  : 'Número em processo de expiração',
            ),
            subtitle: const Text(
              'Faça ou receba uma chamada/mensagem para renovar '
              'automaticamente por mais 7 dias.',
            ),
          ),
        ),
      ],
    );
  }
}
