import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../numbers/domain/number_formatter.dart';
import '../application/call_providers.dart';
import '../domain/call_history_record.dart';

/// Histórico de chamadas real, lido da tabela `calls` (Supabase) —
/// substitui `widget.entries` (histórico antigo, baseado em SIP, que
/// nunca é populado pelas chamadas WebRTC app2app deste app).
class CallHistoryListView extends ConsumerWidget {
  const CallHistoryListView({required this.onDial, super.key});

  final ValueChanged<String> onDial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(callHistoryProvider);

    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Erro: $error')),
      data: (records) {
        if (records.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'Histórico vazio',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'As chamadas realizadas e recebidas aparecerão aqui.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          itemCount: records.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) =>
              _CallHistoryTile(record: records[index], onDial: onDial),
        );
      },
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  const _CallHistoryTile({required this.record, required this.onDial});

  final CallHistoryRecord record;
  final ValueChanged<String> onDial;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMissed = record.status == 'missed' || record.status == 'declined';
    final directionIcon = record.direction == CallDirection.outgoing
        ? Icons.call_made
        : Icons.call_received;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isMissed
              ? Colors.red.withValues(alpha: 0.12)
              : colorScheme.primaryContainer,
          child: Icon(
            directionIcon,
            size: 18,
            color: isMissed ? Colors.red : colorScheme.primary,
          ),
        ),
        title: Text(NumberFormatter.toDisplay(record.peerNumber)),
        subtitle: Text(_statusLabel(record)),
        trailing: IconButton(
          icon: Icon(Icons.call_outlined, color: colorScheme.primary),
          onPressed: () => onDial(record.peerNumber),
        ),
      ),
    );
  }

  String _statusLabel(CallHistoryRecord record) {
    final time =
        '${record.createdAt.hour.toString().padLeft(2, '0')}:${record.createdAt.minute.toString().padLeft(2, '0')}';
    switch (record.status) {
      case 'missed':
        return 'Não atendida · $time';
      case 'declined':
        return 'Recusada · $time';
      case 'ringing':
        return 'Chamando... · $time';
      case 'accepted':
        return 'Em chamada · $time';
      case 'ended':
        final minutes = (record.durationSeconds ~/ 60).toString().padLeft(2, '0');
        final seconds = (record.durationSeconds % 60).toString().padLeft(2, '0');
        return 'Encerrada ($minutes:$seconds) · $time';
      default:
        return time;
    }
  }
}
