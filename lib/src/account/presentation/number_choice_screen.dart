import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../numbers/application/number_providers.dart';
import '../../numbers/data/number_repository.dart';

class NumberChoiceScreen extends ConsumerWidget {
  const NumberChoiceScreen({required this.ddd, super.key});

  final String ddd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optionsAsync = ref.watch(numberOptionsProvider(ddd));

    return Scaffold(
      appBar: AppBar(title: Text('Números disponíveis · DDD $ddd')),
      body: optionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Erro ao buscar números: $err'),
          ),
        ),
        data: (options) {
          if (options.isEmpty) {
            return const Center(
              child: Text('Nenhum número disponível para este DDD no momento.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: options.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final option = options[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.smartphone),
                  title: Text(
                    option.formatted,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: FilledButton(
                    onPressed: () => _claim(context, ref, option),
                    child: const Text('Escolher'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _claim(
    BuildContext context,
    WidgetRef ref,
    NumberOption option,
  ) async {
    final repo = ref.read(numberRepositoryProvider);
    try {
      await repo.claimNumber(option.id);
      // Não navegamos manualmente: VNumeroGate (main.dart) observa
      // activeNumberProvider e troca a tela inteira para o PhoneWebApp
      // original assim que o número ativo aparece no cache local.
      ref.invalidate(activeNumberProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Esse número acabou de ser escolhido por outra pessoa. '
              'Tente outro. ($e)',
            ),
          ),
        );
        ref.invalidate(numberOptionsProvider(ddd));
      }
    }
  }
}
