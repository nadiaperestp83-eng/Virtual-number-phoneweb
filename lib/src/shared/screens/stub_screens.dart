import 'package:flutter/material.dart';

/// Telas placeholder desta fase (estrutura + navegação prontas).
/// TODO Fase 3 (VoIP): substituir por teclado numérico real +
///      integração flutter_webrtc + sinalização via Supabase Realtime.
class KeypadScreen extends StatelessWidget {
  const KeypadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderScaffold(
      title: 'Discador',
      icon: Icons.dialpad,
      message: 'Teclado numérico e chamadas WebRTC entram na Fase 3.',
    );
  }
}

/// TODO Fase 2 (Chat): substituir por lista de conversas + chat em
///      tempo real usando Supabase Realtime (tabela `messages`) com
///      cache local em Isar (LocalMessage).
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderScaffold(
      title: 'Mensagens',
      icon: Icons.chat_bubble,
      message: 'Chat em tempo real (SMS interno) entra na Fase 2.',
    );
  }
}

/// TODO Fase 3: preencher a partir dos eventos de chamada salvos
///      localmente em Isar (LocalCallLogEntry).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderScaffold(
      title: 'Histórico',
      icon: Icons.history,
      message: 'Histórico de chamadas entra junto com a Fase 3 (VoIP).',
    );
  }
}

/// TODO Fase 2/3: agenda interna com números virtuais salvos
///      (LocalContact no Isar), com opção de sync com contatos nativos.
class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderScaffold(
      title: 'Contatos',
      icon: Icons.contacts,
      message: 'Agenda interna entra nas próximas fases.',
    );
  }
}

class _PlaceholderScaffold extends StatelessWidget {
  const _PlaceholderScaffold({
    required this.title,
    required this.icon,
    required this.message,
  });

  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: Theme.of(context).disabledColor),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
