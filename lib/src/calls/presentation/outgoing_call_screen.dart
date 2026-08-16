import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../numbers/domain/number_formatter.dart';
import '../application/call_providers.dart';
import '../application/ringback_player.dart';

/// Tela de chamada saindo — "Chamando...". Toca o ringback em loop
/// (som local de "tut... tut...") enquanto aguarda o outro lado
/// atender/recusar, observando `calls.status` em tempo real via
/// Supabase Realtime.
///
/// O áudio real da chamada (voz) NÃO está implementado aqui ainda —
/// isso é sinalização + feedback de UI, ver nota em `ringback_player.dart`.
class OutgoingCallScreen extends ConsumerStatefulWidget {
  const OutgoingCallScreen({
    required this.callId,
    required this.calleeLabel,
    super.key,
  });

  final String callId;
  final String calleeLabel;

  @override
  ConsumerState<OutgoingCallScreen> createState() =>
      _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends ConsumerState<OutgoingCallScreen> {
  final _ringback = RingbackPlayer();
  String _status = 'ringing';

  @override
  void initState() {
    super.initState();
    _ringback.start();
  }

  @override
  void dispose() {
    _ringback.stop();
    _ringback.dispose();
    super.dispose();
  }

  Future<void> _endCall() async {
    await ref
        .read(callSignalingRepositoryProvider)
        .updateStatus(callId: widget.callId, status: 'ended');
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final callRepo = ref.watch(callSignalingRepositoryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF1D1D1F),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: callRepo.watchCall(widget.callId),
        builder: (context, snapshot) {
          final status = snapshot.data?['status'] as String? ?? _status;
          _status = status;

          if (status != 'ringing') {
            _ringback.stop();
          }

          // Chamada terminou de algum jeito sem o áudio real estar
          // implementado ainda — volta pro discador automaticamente.
          if (status == 'declined' ||
              status == 'missed' ||
              status == 'ended') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) Navigator.of(context).pop();
            });
          }

          final label = status == 'accepted' ? 'Em chamada' : 'Chamando...';

          return SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                CircleAvatar(
                  radius: 56,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  child: Text(
                    _initials(widget.calleeLabel),
                    style: const TextStyle(
                      fontSize: 32,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  NumberFormatter.toDisplay(widget.calleeLabel),
                  style: const TextStyle(
                    fontSize: 24,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const Spacer(flex: 3),
                SizedBox(
                  width: 72,
                  height: 72,
                  child: FilledButton(
                    onPressed: _endCall,
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      backgroundColor: const Color(0xFFFF3B30),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Icon(
                      Icons.call_end,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          );
        },
      ),
    );
  }

  String _initials(String raw) {
    final digits = NumberFormatter.onlyDigits(raw);
    if (digits.length < 2) return '#';
    return digits.substring(digits.length - 2);
  }
}
