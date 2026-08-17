import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/supabase_providers.dart';
import '../../numbers/application/number_providers.dart';
import '../../numbers/domain/number_formatter.dart';
import '../application/call_providers.dart';
import '../application/ringback_player.dart';
import '../application/voicemail_providers.dart';

const _ringTimeout = Duration(seconds: 30);
const _maxRecordingDuration = Duration(seconds: 60);

enum _CallPhase { ringing, recording, sending, done }

/// Tela de chamada saindo, estilo "Mi Dialer" (fundo escuro/petróleo).
/// Se ninguém atender em 30s, transiciona (fade) para a gravação de um
/// recado de voz, que é enviado como voicemail pro destinatário.
///
/// Mudo/Viva-voz/Teclado são PLACEHOLDERS visuais por enquanto — não
/// existe áudio WebRTC real ainda (Fase 3.2 pendente), então esses
/// botões só mostram "em breve" ao tocar.
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
  final _recorder = AudioRecorder();

  _CallPhase _phase = _CallPhase.ringing;
  String _callStatus = 'ringing';
  Timer? _ringElapsedTimer;
  Timer? _recordingTimer;
  int _ringSeconds = 0;
  int _recordingSeconds = 0;
  String? _recordingPath;
  final _waveform = List<double>.generate(24, (_) => 0.2);
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _ringback.start();
    _ringElapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _ringSeconds++);
      if (_ringSeconds >= _ringTimeout.inSeconds &&
          _phase == _CallPhase.ringing &&
          _callStatus == 'ringing') {
        _startRecording();
      }
    });
  }

  @override
  void dispose() {
    _ringElapsedTimer?.cancel();
    _recordingTimer?.cancel();
    _ringback.stop();
    _ringback.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!mounted) return;
    await _ringback.stop();

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      // Sem permissão de microfone: não dá pra gravar recado — só
      // encerra a chamada como perdida.
      await _finishAsMissed();
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/voicemail_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );

    if (!mounted) return;
    setState(() {
      _phase = _CallPhase.recording;
      _recordingPath = path;
      _recordingSeconds = 0;
    });

    _recordingTimer = Timer.periodic(const Duration(milliseconds: 200), (
      timer,
    ) {
      if (!mounted) return;
      setState(() {
        // Barrinhas de onda simuladas (sem análise real de amplitude
        // por enquanto) — dá o feedback visual de "gravando".
        for (var i = 0; i < _waveform.length; i++) {
          _waveform[i] = 0.15 + _random.nextDouble() * 0.85;
        }
      });
      if (timer.tick % 5 == 0) {
        setState(() => _recordingSeconds++);
        if (_recordingSeconds >= _maxRecordingDuration.inSeconds) {
          _sendRecording();
        }
      }
    });
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    await _finishAsMissed();
  }

  Future<void> _sendRecording() async {
    _recordingTimer?.cancel();
    setState(() => _phase = _CallPhase.sending);

    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    path ??= _recordingPath;

    if (path == null || _recordingSeconds < 1) {
      await _finishAsMissed();
      return;
    }

    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final myNumber = await container
          .read(numberRepositoryProvider)
          .getActiveNumber();
      final user = container.read(currentUserProvider);
      final callRepo = container.read(callSignalingRepositoryProvider);

      // Descobre o callee_id a partir da própria chamada já criada.
      final callRow = await container
          .read(supabaseClientProvider)
          .from('calls')
          .select('callee_id')
          .eq('id', widget.callId)
          .single();
      final calleeId = callRow['callee_id'] as String;

      if (myNumber != null && user != null) {
        await container.read(voicemailRepositoryProvider).uploadVoicemail(
          audioFile: File(path),
          callId: widget.callId,
          callerNumber: myNumber.number,
          callerName: myNumber.formatted,
          calleeUserId: calleeId,
          calleeNumber: widget.calleeLabel,
          durationSeconds: _recordingSeconds,
        );
      }

      await callRepo.updateStatus(callId: widget.callId, status: 'missed');
    } catch (_) {
      // Melhor esforço: mesmo se o upload falhar, a chamada já
      // encerra normalmente — não trava o usuário na tela.
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _finishAsMissed() async {
    await ref
        .read(callSignalingRepositoryProvider)
        .updateStatus(callId: widget.callId, status: 'missed');
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _endCall() async {
    if (_phase == _CallPhase.recording) {
      await _cancelRecording();
      return;
    }
    await ref
        .read(callSignalingRepositoryProvider)
        .updateStatus(callId: widget.callId, status: 'ended');
    if (mounted) Navigator.of(context).pop();
  }

  void _placeholderAction(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label: em breve.')));
  }

  @override
  Widget build(BuildContext context) {
    final callRepo = ref.watch(callSignalingRepositoryProvider);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B2027), Color(0xFF03110F)],
          ),
        ),
        child: StreamBuilder<Map<String, dynamic>>(
          stream: callRepo.watchCall(widget.callId),
          builder: (context, snapshot) {
            final status = snapshot.data?['status'] as String? ?? _callStatus;
            _callStatus = status;

            if (_phase == _CallPhase.ringing &&
                (status == 'declined' ||
                    status == 'missed' ||
                    status == 'ended')) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.of(context).pop();
              });
            }

            return SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _phase == _CallPhase.ringing
                    ? _RingingView(
                        key: const ValueKey('ringing'),
                        calleeLabel: widget.calleeLabel,
                        status: status,
                        onEndCall: _endCall,
                        onPlaceholder: _placeholderAction,
                      )
                    : _RecordingView(
                        key: const ValueKey('recording'),
                        calleeLabel: widget.calleeLabel,
                        seconds: _recordingSeconds,
                        maxSeconds: _maxRecordingDuration.inSeconds,
                        waveform: _waveform,
                        sending: _phase == _CallPhase.sending,
                        onCancel: _cancelRecording,
                        onSend: _sendRecording,
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RingingView extends StatelessWidget {
  const _RingingView({
    required this.calleeLabel,
    required this.status,
    required this.onEndCall,
    required this.onPlaceholder,
    super.key,
  });

  final String calleeLabel;
  final String status;
  final VoidCallback onEndCall;
  final ValueChanged<String> onPlaceholder;

  @override
  Widget build(BuildContext context) {
    final label = status == 'accepted' ? 'Em chamada' : 'Chamando...';

    return Column(
      key: const ValueKey('ringing-column'),
      children: [
        const Spacer(flex: 2),
        _BlurredAvatar(label: calleeLabel),
        const SizedBox(height: 24),
        Text(
          NumberFormatter.toDisplay(calleeLabel),
          style: const TextStyle(
            fontSize: 24,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.7)),
        ),
        const Spacer(flex: 3),
        _ControlsGrid(onTap: onPlaceholder),
        const SizedBox(height: 28),
        _HangUpButton(onPressed: onEndCall),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _BlurredAvatar extends StatelessWidget {
  const _BlurredAvatar({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final digits = NumberFormatter.onlyDigits(label);
    final initials = digits.length >= 2 ? digits.substring(digits.length - 2) : '#';

    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo desfocado atrás do avatar, sobre o gradiente escuro.
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          CircleAvatar(
            radius: 56,
            backgroundColor: Colors.white.withValues(alpha: 0.14),
            child: Text(
              initials,
              style: const TextStyle(
                fontSize: 32,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsGrid extends StatelessWidget {
  const _ControlsGrid({required this.onTap});

  final ValueChanged<String> onTap;

  static const _items = [
    (Icons.mic_off_outlined, 'Mudo'),
    (Icons.volume_up_outlined, 'Viva-voz'),
    (Icons.dialpad_outlined, 'Teclado'),
    (Icons.person_add_outlined, 'Contatos'),
    (Icons.add_outlined, 'Adicionar'),
    (Icons.edit_note_outlined, 'Nota'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 20,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
        children: [
          for (final (icon, label) in _items)
            _ControlButton(icon: icon, label: label, onTap: () => onTap(label)),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _HangUpButton extends StatelessWidget {
  const _HangUpButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: const CircleBorder(),
          backgroundColor: const Color(0xFFFF3B30),
          padding: EdgeInsets.zero,
        ),
        child: const Icon(Icons.call_end, color: Colors.white, size: 30),
      ),
    );
  }
}

class _RecordingView extends StatelessWidget {
  const _RecordingView({
    required this.calleeLabel,
    required this.seconds,
    required this.maxSeconds,
    required this.waveform,
    required this.sending,
    required this.onCancel,
    required this.onSend,
    super.key,
  });

  final String calleeLabel;
  final int seconds;
  final int maxSeconds;
  final List<double> waveform;
  final bool sending;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');

    return Column(
      key: const ValueKey('recording-column'),
      children: [
        const Spacer(flex: 2),
        const Icon(Icons.mic, color: Colors.white, size: 48),
        const SizedBox(height: 20),
        Text(
          'Gravando recado para\n${NumberFormatter.toDisplay(calleeLabel)}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$minutes:$secs / ${maxSeconds ~/ 60}:${(maxSeconds % 60).toString().padLeft(2, '0')}',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final level in waveform)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 3,
                  height: 8 + level * 48,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
        const Spacer(flex: 3),
        if (sending)
          const CircularProgressIndicator(color: Colors.white)
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: onCancel,
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              FilledButton.icon(
                onPressed: onSend,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0A84FF),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                icon: const Icon(Icons.send, size: 18),
                label: const Text('Enviar'),
              ),
            ],
          ),
        const SizedBox(height: 40),
      ],
    );
  }
}
