import 'package:audioplayers/audioplayers.dart';

/// Toca o tom de "chamando" (ringback) em loop, localmente, enquanto o
/// outro lado ainda não atendeu/recusou.
///
/// IMPORTANTE: isso é só o TOM DE CHAMANDO local (feedback pro quem
/// está ligando) — não é o áudio da chamada em si. O áudio real
/// (RTCPeerConnection, SDP/ICE) ainda não está implementado — ver
/// `TODO Fase 3.2` em `call_providers.dart`. Este player para
/// automaticamente assim que a chamada sai do estado "ringing"
/// (aceita, recusada, perdida ou encerrada).
///
/// Requer o arquivo `assets/audio/ringback_tone.mp3` declarado em
/// `pubspec.yaml`. Esse arquivo de áudio precisa ser adicionado
/// manualmente ao projeto — não é algo que eu (Claude) consigo gerar.
class RingbackPlayer {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  Future<void> start() async {
    if (_playing) return;
    _playing = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('audio/ringback_tone.mp3'));
    } catch (_) {
      // Se o asset não existir ainda (arquivo não adicionado ao
      // projeto), falha silenciosamente em vez de derrubar a tela de
      // chamada — a chamada em si continua funcionando sem o tom.
      _playing = false;
    }
  }

  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
