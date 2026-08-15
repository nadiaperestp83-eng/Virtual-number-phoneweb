import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../phoneweb_app.dart' show MobileEmptyTab;
import '../../numbers/application/number_providers.dart';
import '../../numbers/domain/number_formatter.dart';
import '../application/chat_providers.dart';
import '../data/chat_repository.dart';
import '../domain/conversation_summary.dart';
import 'chat_thread_screen.dart';

/// Substitui o `MessagesPanel` (placeholder vazio) dentro de
/// `MobileMessagesView`, no fork. Estilo inspirado no app Mensagens da
/// Apple: lista de conversas com avatar circular, prévia da última
/// mensagem e indicador de não lidas.
class ConversationsListView extends ConsumerWidget {
  const ConversationsListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(conversationsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Mensagens',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              IconButton(
                icon: const Icon(Icons.edit_square_outlined),
                tooltip: 'Nova conversa',
                onPressed: () => _openNewConversationDialog(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: conversationsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                Center(child: Text('Erro ao carregar conversas: $error')),
            data: (conversations) {
              if (conversations.isEmpty) {
                return const MobileEmptyTab(
                  icon: Icons.chat_bubble_outline,
                  title: 'Nenhuma conversa ainda',
                  message:
                      'Toque no ícone de nova conversa e digite o número '
                      'virtual de alguém da rede para começar.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.only(top: 4),
                itemCount: conversations.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 74),
                itemBuilder: (context, index) {
                  final conversation = conversations[index];
                  return _ConversationTile(
                    conversation: conversation,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatThreadScreen(
                          peerNumber: conversation.peerNumber,
                          peerUserId: conversation.peerUserId,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openNewConversationDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController();
    String? errorText;
    bool loading = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: const Text('Nova conversa'),
              content: TextField(
                controller: controller,
                keyboardType: TextInputType.phone,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Número virtual da rede',
                  hintText: '(35) 96000-1234',
                  errorText: errorText,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final raw = NumberFormatter.onlyDigits(
                            controller.text,
                          );
                          if (raw.length != 11) {
                            setState(
                              () => errorText = 'Número inválido',
                            );
                            return;
                          }
                          setState(() {
                            loading = true;
                            errorText = null;
                          });

                          final chatRepo = ref.read(chatRepositoryProvider);
                          final ownerId = await chatRepo.resolveOwnerId(raw);

                          if (!dialogContext.mounted) return;

                          if (ownerId == null) {
                            setState(() {
                              loading = false;
                              errorText = 'Esse número não está ativo';
                            });
                            return;
                          }

                          Navigator.of(dialogContext).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChatThreadScreen(
                                peerNumber: raw,
                                peerUserId: ownerId,
                              ),
                            ),
                          );
                        },
                  child: loading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Conversar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final ConversationSummary conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayNumber = NumberFormatter.toDisplay(conversation.peerNumber);
    final hasUnread = conversation.unreadCount > 0;
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: colorScheme.primaryContainer,
        child: Text(
          _initialsFromNumber(conversation.peerNumber),
          style: TextStyle(
            color: colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      // TODO Fase 3: trocar `displayNumber` pelo nome do contato quando
      // o número bater com um `PhoneContact` salvo (integração pendente,
      // combinada para depois).
      title: Text(
        displayNumber,
        style: TextStyle(
          fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        conversation.lastMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: hasUnread
              ? colorScheme.onSurface
              : colorScheme.onSurfaceVariant,
          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatConversationTime(conversation.lastMessageAt),
            style: TextStyle(
              fontSize: 12,
              color: hasUnread ? colorScheme.primary : colorScheme.outline,
              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _initialsFromNumber(String number) {
  final digits = NumberFormatter.onlyDigits(number);
  if (digits.length < 2) return '#';
  // Últimos 2 dígitos do número (ainda sem contato vinculado).
  return digits.substring(digits.length - 2);
}

String _formatConversationTime(DateTime value) {
  final now = DateTime.now();
  final sameDay =
      value.year == now.year && value.month == now.month && value.day == now.day;
  if (sameDay) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}';
}
