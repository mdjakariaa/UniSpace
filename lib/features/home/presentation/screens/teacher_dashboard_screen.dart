import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:unispace/app/theme/app_colors.dart';
import 'package:unispace/app/theme/app_text_styles.dart';
import 'package:unispace/core/widgets/glass_card.dart';
import 'package:unispace/features/auth/presentation/providers/auth_provider.dart';

/// Teacher dashboard screen
class TeacherDashboardScreen extends ConsumerWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.5, -0.6),
            radius: 1.8,
            colors: [Color(0xFF1A2040), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        gradient: AppColors.warningGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          user?.fullName.isNotEmpty == true ? user!.fullName[0].toUpperCase() : 'T',
                          style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hello, ${user?.fullName.split(' ').first ?? 'Teacher'} 👋', style: AppTextStyles.h3),
                        Text('Teacher Dashboard', style: AppTextStyles.bodySmall),
                      ],
                    ),
                  ],
                ).animate().fadeIn().slideX(begin: -0.1),

                const SizedBox(height: 28),

                // Quick actions
                Text('Quick Actions', style: AppTextStyles.h4).animate(delay: 200.ms).fadeIn(),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.cancel_outlined,
                        label: 'Cancel\nBooking',
                        color: AppColors.error,
                        onTap: () {
                          // TODO: Navigate to cancel booking
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.send_rounded,
                        label: 'Send\nRequest',
                        color: AppColors.warning,
                        onTap: () {
                          // TODO: Navigate to send request
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.meeting_room_rounded,
                        label: 'View\nRooms',
                        color: AppColors.accent,
                        onTap: () {
                          // TODO: Navigate to rooms
                        },
                      ),
                    ),
                  ],
                ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.1),

                const SizedBox(height: 28),

                Text('Room Usage Summary', style: AppTextStyles.h4).animate(delay: 400.ms).fadeIn(),
                const SizedBox(height: 14),

                GlassCard(
                  child: Column(
                    children: [
                      _SummaryRow(label: 'Active Bookings', value: '0', icon: Icons.event_available_rounded, color: AppColors.success),
                      const Divider(color: AppColors.glassBorder, height: 24),
                      _SummaryRow(label: 'Pending Requests', value: '0', icon: Icons.pending_actions_rounded, color: AppColors.warning),
                      const Divider(color: AppColors.glassBorder, height: 24),
                      _SummaryRow(label: 'Cancelled Today', value: '0', icon: Icons.cancel_rounded, color: AppColors.error),
                    ],
                  ),
                ).animate(delay: 500.ms).fadeIn().slideY(begin: 0.1),

                const SizedBox(height: 28),

                // Sign out
                Center(
                  child: TextButton.icon(
                    onPressed: () => ref.read(authProvider.notifier).signOut(),
                    icon: const Icon(Icons.logout_rounded, color: AppColors.error),
                    label: Text('Sign Out', style: AppTextStyles.labelLarge.copyWith(color: AppColors.error)),
                  ),
                ).animate(delay: 600.ms).fadeIn(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 10),
          Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryRow({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style: AppTextStyles.bodyLarge)),
        Text(value, style: AppTextStyles.h3.copyWith(color: color)),
      ],
    );
  }
}
