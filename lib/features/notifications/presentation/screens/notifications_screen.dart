import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:unispace/app/theme/app_colors.dart';
import 'package:unispace/app/theme/app_text_styles.dart';
import 'package:unispace/features/notifications/presentation/providers/notification_provider.dart';

/// Notifications screen — renders live Supabase notifications.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final unreadAsync = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.8),
            radius: 1.5,
            colors: [Color(0xFF1A1040), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Notifications', style: AppTextStyles.h1).animate().fadeIn().slideX(begin: -0.1),
                          const SizedBox(height: 6),
                          unreadAsync.when(
                            data: (count) => Text(
                              count == 0 ? "You're all caught up!" : '$count unread notification${count == 1 ? '' : 's'}',
                              style: AppTextStyles.bodyMedium,
                            ),
                            loading: () => Text('Loading notifications...', style: AppTextStyles.bodyMedium),
                            error: (_, __) => Text('Could not load unread count.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.warning)),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          await ref.read(notificationServiceProvider).markAllAsRead();
                          ref.invalidate(notificationsProvider);
                        } catch (_) {
                          if (context.mounted) _showSnack(context, 'Could not mark notifications as read.', isError: true);
                        }
                      },
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: const Text('Mark all read'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: notificationsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _NotificationsError(
                    message: error.toString().replaceFirst('Exception: ', ''),
                    onRetry: () => ref.invalidate(notificationsProvider),
                  ),
                  data: (notifications) {
                    if (notifications.isEmpty) return const _EmptyNotifications();
                    return RefreshIndicator(
                      backgroundColor: AppColors.surface,
                      color: AppColors.accent,
                      onRefresh: () async => ref.invalidate(notificationsProvider),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 110),
                        itemCount: notifications.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _NotificationTile(
                          notification: notifications[index],
                          onTap: () async {
                            if (!notifications[index].isRead) {
                              await ref.read(notificationServiceProvider).markAsRead(notifications[index].id);
                              ref.invalidate(notificationsProvider);
                            }
                            if (context.mounted && notifications[index].type == 'group_join_request') {
                              _showSnack(context, 'Open Study Groups to review this join request.');
                            }
                          },
                          onDelete: () async {
                            await ref.read(notificationServiceProvider).deleteNotification(notifications[index].id);
                            ref.invalidate(notificationsProvider);
                          },
                        ).animate(delay: (45 * index).ms).fadeIn().slideY(begin: 0.08),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationEntity notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotificationTile({required this.notification, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(notification.type);
    final icon = _typeIcon(notification.type);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: notification.isRead ? AppColors.surface.withOpacity(0.74) : color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: notification.isRead ? AppColors.glassBorder : color.withOpacity(0.45)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: color.withOpacity(0.16), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(notification.title, style: AppTextStyles.labelLarge)),
                      if (!notification.isRead)
                        Container(width: 9, height: 9, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(notification.body, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(DateFormat('dd MMM yyyy, h:mm a').format(notification.createdAt), style: AppTextStyles.caption),
                      if (notification.type == 'group_join_request')
                        _MiniBadge(label: 'Study Group Request', color: AppColors.warning),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Delete notification',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textHint),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(99), border: Border.all(color: color.withOpacity(0.3))),
      child: Text(label, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_off_outlined, size: 72, color: AppColors.textHint.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text('No notifications', style: AppTextStyles.h4),
          const SizedBox(height: 8),
          Text("You're all caught up!", style: AppTextStyles.bodyMedium),
        ],
      ).animate(delay: 300.ms).fadeIn(),
    );
  }
}

class _NotificationsError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _NotificationsError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 64, color: AppColors.error),
            const SizedBox(height: 14),
            Text('Could not load notifications', style: AppTextStyles.h4),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: AppTextStyles.bodyMedium),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

Color _typeColor(String type) {
  switch (type) {
    case 'group_join_request':
      return AppColors.warning;
    case 'request_approved':
    case 'booking_confirmed':
      return AppColors.success;
    case 'request_rejected':
    case 'booking_cancelled':
      return AppColors.error;
    case 'teacher_room_assigned':
      return AppColors.info;
    default:
      return AppColors.accent;
  }
}

IconData _typeIcon(String type) {
  switch (type) {
    case 'group_join_request':
      return Icons.group_add_rounded;
    case 'request_approved':
      return Icons.verified_rounded;
    case 'request_rejected':
      return Icons.cancel_rounded;
    case 'booking_confirmed':
      return Icons.event_available_rounded;
    case 'booking_cancelled':
      return Icons.event_busy_rounded;
    case 'teacher_room_assigned':
      return Icons.school_rounded;
    default:
      return Icons.notifications_active_rounded;
  }
}

void _showSnack(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
