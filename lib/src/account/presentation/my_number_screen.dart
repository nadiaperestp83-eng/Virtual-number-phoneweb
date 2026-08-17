import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../numbers/application/number_providers.dart';

class MyNumberScreen extends ConsumerWidget {
  const MyNumberScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final numberAsync = ref.watch(activeNumberProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Meus Números')),
      body: numberAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erro: $error')),
        data: (number) {
          if (number == null) {
            return const Center(child: Text('Nenhum número ativo.'));
          }

          final daysActive = DateTime.now().difference(number.activatedAt).inDays;
          final daysLeft = (7 - daysActive).clamp(0, 7);
          final eligible = daysLeft == 0;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Número atual',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        number.formatted,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ativo desde ${_formatDate(number.activatedAt)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                eligible
                    ? 'Você já pode trocar de número quando quiser.'
                    : 'Só é possível trocar de número após 7 dias de uso do número atual — faltam $daysLeft dia(s).',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: eligible ? () => _confirmChange(context, ref) : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Trocar número'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _confirmChange(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Trocar de número?'),
        content: const Text(
          'Seu número atual será liberado para outras pessoas e você vai '
          'escolher um novo. Isso não pode ser desfeito.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Trocar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(numberRepositoryProvider).releaseMyNumberForChange();
      ref.invalidate(activeNumberProvider);
      // Não navega manualmente: VNumeroGate observa activeNumberProvider
      // e manda pro onboarding de escolha de número sozinho assim que
      // detectar que não há mais número ativo.
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Não foi possível trocar: $e')));
      }
    }
  }
}
