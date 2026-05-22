import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:unispace/app/theme/app_colors.dart';
import 'package:unispace/app/theme/app_text_styles.dart';
import 'package:unispace/core/widgets/glass_card.dart';
import 'package:unispace/features/admin/presentation/providers/admin_provider.dart';

class ApprovalPanelScreen extends ConsumerWidget {
  const ApprovalPanelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(roomRequestsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0.2, -0.4), radius: 1.8,
            colors: [Color(0xFF1A1A00), AppColors.background]),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(children: [
                  IconButton(onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.textPrimary, size: 20)),
                  const SizedBox(width: 8),
                  Text('Approval Panel', style: AppTextStyles.h2),
                ]),
              ).animate().fadeIn().slideX(begin: -0.1),
              const SizedBox(height: 20),
              // Requests list
              Expanded(
                child: requestsAsync.when(
                  data: (requests) {
                    if (requests.isEmpty) {
                      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_circle_outline_rounded, size: 64, color: AppColors.success.withOpacity(0.4)),
                        const SizedBox(height: 16),
                        Text('No requests', style: AppTextStyles.bodyMedium),
                        const SizedBox(height: 4),
                        Text('All caught up!', style: AppTextStyles.caption),
                      ]));
                    }
                    // Sort: pending first
                    final sorted = List<Map<String, dynamic>>.from(requests);
                    sorted.sort((a, b) {
                      if (a['status'] == 'pending' && b['status'] != 'pending') return -1;
                      if (a['status'] != 'pending' && b['status'] == 'pending') return 1;
                      return 0;
                    });
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: sorted.length,
                      itemBuilder: (context, i) {
                        final req = sorted[i];
                        final isPending = req['status'] == 'pending';
                        final isApproved = req['status'] == 'approved';
                        final statusColor = isPending ? AppColors.warning
                            : isApproved ? AppColors.success : AppColors.error;
                        final statusText = isPending ? 'PENDING'
                            : isApproved ? 'APPROVED' : 'REJECTED';
                        final createdAt = DateTime.tryParse(req['created_at'] ?? '');
                        final timeAgoStr = createdAt != null ? timeago.format(createdAt) : '';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12)),
                                    child: Icon(
                                      isPending ? Icons.hourglass_top_rounded
                                          : isApproved ? Icons.check_circle_rounded
                                          : Icons.cancel_rounded,
                                      color: statusColor, size: 22),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Room ${req['request_type'] ?? 'Release'} Request',
                                        style: AppTextStyles.labelLarge),
                                      if (timeAgoStr.isNotEmpty)
                                        Text(timeAgoStr, style: AppTextStyles.caption),
                                    ],
                                  )),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8)),
                                    child: Text(statusText,
                                      style: AppTextStyles.caption.copyWith(
                                        color: statusColor, fontWeight: FontWeight.w700, fontSize: 10)),
                                  ),
                                ]),
                                if (req['reason'] != null && (req['reason'] as String).isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceLight,
                                      borderRadius: BorderRadius.circular(10)),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Reason', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 4),
                                        Text(req['reason'] as String, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                                      ],
                                    ),
                                  ),
                                ],
                                // Action buttons for pending
                                if (isPending) ...[
                                  const SizedBox(height: 14),
                                  Row(children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => ref.read(adminServiceProvider)
                                            .rejectRequest(req['id'], req['room_id']),
                                        icon: const Icon(Icons.close_rounded, size: 18),
                                        label: const Text('Reject'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.error,
                                          side: const BorderSide(color: AppColors.error),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => ref.read(adminServiceProvider)
                                            .approveRequest(req['id'], req['room_id']),
                                        icon: const Icon(Icons.check_rounded, size: 18),
                                        label: const Text('Approve'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.success,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                        ),
                                      ),
                                    ),
                                  ]),
                                ],
                              ],
                            ),
                          ),
                        ).animate(delay: Duration(milliseconds: 80 * i)).fadeIn().slideY(begin: 0.05);
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  error: (e, _) => Center(child: Text('Error: $e')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
