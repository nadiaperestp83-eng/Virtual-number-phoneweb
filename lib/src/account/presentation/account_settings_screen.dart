import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';
import '../../numbers/application/number_providers.dart';
import 'my_number_screen.dart';

/// Aba "Eu" — conta & configurações. Estilo Apple moderno: cards
/// arredondados, seções com título discreto, Inter (herdado do tema
/// global, ver app_theme.dart).
///
/// Escopo desta versão: só o que é real no app (Minha Conta, Meu
/// Número, Sair) + placeholders visuais para Tema/Notificações/
/// Segurança (ainda não funcionam — mostram "Em breve" ao tocar).
/// Assinatura, Chamadas e Caixa de voz ficaram de fora por não se
/// aplicarem a este app.
class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final numberAsync = ref.watch(activeNumberProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final handle = numberAsync.maybeWhen(
      data: (number) => number?.formatted ?? '—',
      orElse: () => '—',
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Cabeçalho: avatar estático + número virtual como "handle".
        Row(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(
                Icons.person_outline,
                size: 34,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    handle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user?.email ?? '',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        _SectionLabel('Conta'),
        _SettingsCard(
          children: [
            _SettingsRow(
              icon: Icons.person_outline,
              title: 'Minha Conta',
              subtitle: user?.email ?? 'Login e conta',
              onTap: () => _showComingSoon(context, 'Minha Conta'),
            ),
            _SettingsRow(
              icon: Icons.smartphone_outlined,
              title: 'Meus Números',
              subtitle: handle,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyNumberScreen()),
              ),
              isLast: true,
            ),
          ],
        ),

        const SizedBox(height: 24),
        _SectionLabel('Configurações'),
        _SettingsCard(
          children: [
            _SettingsRow(
              icon: Icons.contrast_outlined,
              title: 'Tema',
              subtitle: 'Claro (padrão)',
              onTap: () => _showComingSoon(context, 'Tema'),
            ),
            _SettingsRow(
              icon: Icons.notifications_outlined,
              title: 'Notificações',
              subtitle: 'Gerenciar alertas do app',
              onTap: () => _showComingSoon(context, 'Notificações'),
            ),
            _SettingsRow(
              icon: Icons.lock_outline,
              title: 'Segurança',
              subtitle: 'Privacidade e proteção da conta',
              onTap: () => _showComingSoon(context, 'Segurança'),
              isLast: true,
            ),
          ],
        ),

        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _confirmLogout(context, ref),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF3B30),
              side: const BorderSide(color: Color(0xFFFF3B30)),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Sair da conta'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => _confirmDeactivate(context, ref),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            child: const Text('Desativar conta'),
          ),
        ),
      ],
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature: em breve.')),
    );
  }

  Future<void> _confirmDeactivate(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desativar conta?'),
        content: const Text(
          'Seu número virtual será liberado imediatamente para outras '
          'pessoas (não precisa esperar os 7 dias de inatividade). Seu '
          'login continua existindo — você pode entrar de novo e '
          'escolher um número novo quando quiser.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Desativar',
              style: TextStyle(color: Color(0xFFFF3B30)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(numberRepositoryProvider).deactivateAccount();
      if (context.mounted) {
        await ref.read(supabaseClientProvider).auth.signOut();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Não foi possível desativar: $e')));
      }
    }
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text(
          'Você precisará entrar de novo com e-mail e senha.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Não navega manualmente: VNumeroGate (main.dart) observa
      // currentUserProvider e troca a tela sozinho assim que a sessão
      // cair, mandando de volta pro LoginScreen.
      await ref.read(supabaseClientProvider).auth.signOut();
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(children: children),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        ListTile(
          onTap: onTap,
          leading: Icon(icon, color: colorScheme.primary),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right, size: 20),
        ),
        if (!isLast) Divider(height: 1, indent: 56, color: colorScheme.outlineVariant),
      ],
    );
  }
}
