import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:unispace/app/theme/app_colors.dart';
import 'package:unispace/app/theme/app_text_styles.dart';
import 'package:unispace/core/widgets/glass_card.dart';
import 'package:unispace/features/auth/presentation/providers/auth_provider.dart';
import 'package:unispace/features/rooms/presentation/providers/room_provider.dart';

/// Admin dashboard with analytics and management shortcuts
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final roomsAsync = ref.watch(roomsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.3, -0.6),
            radius: 1.8,
            colors: [Color(0xFF200A30), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [AppColors.error, AppColors.warning]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Admin Panel', style: AppTextStyles.h2),
                        Text('Welcome, ${user?.fullName.split(' ').first ?? 'Admin'}', style: AppTextStyles.bodySmall),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => ref.read(authProvider.notifier).signOut(),
                      icon: const Icon(Icons.logout_rounded, color: AppColors.error),
                    ),
                  ],
                ).animate().fadeIn().slideX(begin: -0.1),

                const SizedBox(height: 28),

                // Stats grid
                Text('System Overview', style: AppTextStyles.h4).animate(delay: 200.ms).fadeIn(),
                const SizedBox(height: 14),

                roomsAsync.when(
                  data: (rooms) {
                    final totalRooms = rooms.length;
                    final available = rooms.where((r) => r.status == 'available').length;
                    final totalSeats = rooms.fold<int>(0, (s, r) => s + r.totalSeats);
                    final availableSeats = rooms.fold<int>(0, (s, r) => s + r.availableSeats);

                    return GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.3,
                      children: [
                        _StatCard(icon: Icons.meeting_room_rounded, label: 'Total Rooms', value: '$totalRooms', color: AppColors.primary),
                        _StatCard(icon: Icons.check_circle_rounded, label: 'Available', value: '$available', color: AppColors.success),
                        _StatCard(icon: Icons.event_seat_rounded, label: 'Total Seats', value: '$totalSeats', color: AppColors.accent),
                        _StatCard(icon: Icons.chair_rounded, label: 'Free Seats', value: '$availableSeats', color: AppColors.warning),
                      ],
                    ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.1);
                  },
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  error: (e, _) => Text('Error: $e'),
                ),

                const SizedBox(height: 28),

                // Management shortcuts
                Text('Management', style: AppTextStyles.h4).animate(delay: 400.ms).fadeIn(),
                const SizedBox(height: 14),

                _ManagementTile(
                  icon: Icons.people_rounded,
                  title: 'User Management',
                  subtitle: 'Manage students & teachers',
                  color: AppColors.primary,
                  onTap: () => context.go('/admin/users'),
                ).animate(delay: 500.ms).fadeIn().slideX(begin: -0.05),

                const SizedBox(height: 12),

                _ManagementTile(
                  icon: Icons.meeting_room_rounded,
                  title: 'Room Management',
                  subtitle: 'Add, edit, delete rooms',
                  color: AppColors.accent,
                  onTap: () => context.go('/admin/rooms'),
                ).animate(delay: 600.ms).fadeIn().slideX(begin: -0.05),

                const SizedBox(height: 12),

                _ManagementTile(
                  icon: Icons.approval_rounded,
                  title: 'Approval Panel',
                  subtitle: 'Review pending requests',
                  color: AppColors.warning,
                  onTap: () => context.go('/admin/approvals'),
                ).animate(delay: 700.ms).fadeIn().slideX(begin: -0.05),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(value, style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

class _ManagementTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ManagementTile({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.h4),
                Text(subtitle, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textHint),
        ],
      ),
    );
  }
}
