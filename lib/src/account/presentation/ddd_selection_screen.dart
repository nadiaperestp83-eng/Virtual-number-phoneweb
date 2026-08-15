import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Lista simplificada de DDDs brasileiros. Em produção, mova para um
/// arquivo de dados próprio (ex: assets/ddd_brasil.json) agrupado por
/// estado/região.
const List<Map<String, String>> kDddOptions = [
  {'ddd': '11', 'label': 'São Paulo (11)'},
  {'ddd': '21', 'label': 'Rio de Janeiro (21)'},
  {'ddd': '31', 'label': 'Belo Horizonte (31)'},
  {'ddd': '35', 'label': 'Sul de Minas (35)'},
  {'ddd': '41', 'label': 'Curitiba (41)'},
  {'ddd': '51', 'label': 'Porto Alegre (51)'},
  {'ddd': '61', 'label': 'Brasília (61)'},
  {'ddd': '71', 'label': 'Salvador (71)'},
  {'ddd': '81', 'label': 'Recife (81)'},
  {'ddd': '85', 'label': 'Fortaleza (85)'},
];

class DddSelectionScreen extends StatelessWidget {
  const DddSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escolha seu DDD')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: kDddOptions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final option = kDddOptions[index];
          return Card(
            child: ListTile(
              title: Text(option['label']!),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/onboarding/numbers/${option['ddd']}'),
            ),
          );
        },
      ),
    );
  }
}
