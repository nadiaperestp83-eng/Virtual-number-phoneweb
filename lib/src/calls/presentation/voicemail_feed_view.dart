import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../numbers/domain/number_formatter.dart';
import '../application/voicemail_providers.dart';
import '../domain/voicemail.dart';

/// Feed de recados de voz — cards para ouvir/apagar. Vive dentro da
/// aba Histórico, atrás do filtro "Caixa postal" (ver
/// `_MobileHistoryViewState` em phoneweb_app.dart).
class VoicemailFeedView extends ConsumerWidget {
  const VoicemailFeedView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voicemailsAsync = ref.watch(voicemailsProvider);

    return voicemailsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Erro: $error')),
      data: (voicemails) {
        if (voicemails.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.voicemail_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'Nenhum recado ainda',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Recados de chamadas não atendidas aparecem aqui.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: voicemails.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) =>
              _VoicemailCard(voicemail: voicemails[index]),
        );
      },
    );
  }
}

class _VoicemailCard extends ConsumerStatefulWidget {
  const _VoicemailCard({required this.voicemail});

  final Voicemail voicemail;

  @override
  ConsumerState<_VoicemailCard> createState() => _VoicemailCardState();
}

class _VoicemailCardState extends ConsumerState<_VoicemailCard> {
  final _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
      return;
    }

    setState(() => _loading = true);
    try {
      final repo = ref.read(voicemailRepositoryProvider);
      final url = await repo.getPlaybackUrl(widget.voicemail.storagePath);
      await _player.play(UrlSource(url));
      setState(() {
        _playing = true;
        _loading = false;
      });

      if (!widget.voicemail.listened) {
        await repo.markListened(widget.voicemail.id);
        ref.invalidate(voicemailsProvider);
        ref.invalidate(unheardVoicemailCountProvider);
      }

      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao tocar: $e')));
      }
    }
  }

  Future<void> _delete() async {
    final repo = ref.read(voicemailRepositoryProvider);
    await repo.delete(widget.voicemail.id, widget.voicemail.storagePath);
    ref.invalidate(voicemailsProvider);
    ref.invalidate(unheardVoicemailCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.voicemail;
    final colorScheme = Theme.of(context).colorScheme;
    final minutes = (v.durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (v.durationSeconds % 60).toString().padLeft(2, '0');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: v.listened
              ? colorScheme.surfaceContainerHighest
              : colorScheme.primaryContainer,
          child: Icon(
            Icons.voicemail,
            color: v.listened ? colorScheme.onSurfaceVariant : colorScheme.primary,
          ),
        ),
        title: Text(
          v.callerName?.isNotEmpty == true
              ? v.callerName!
              : NumberFormatter.toDisplay(v.callerNumber),
          style: TextStyle(
            fontWeight: v.listened ? FontWeight.w400 : FontWeight.w700,
          ),
        ),
        subtitle: Text('$minutes:$seconds'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
              iconSize: 32,
              color: colorScheme.primary,
              onPressed: _loading ? null : _togglePlay,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          ],
        ),
      ),
    );
  }
}
