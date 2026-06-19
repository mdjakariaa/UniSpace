import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:unispace/app/theme/app_colors.dart';
import 'package:unispace/app/theme/app_text_styles.dart';
import 'package:unispace/core/widgets/glass_card.dart';
import 'package:unispace/features/auth/presentation/providers/auth_provider.dart';

/// Profile screen — user info, settings, sign out
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.5),
            radius: 1.5,
            colors: [Color(0xFF1A1040), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 20),

                // Avatar
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      user?.fullName.isNotEmpty == true
                          ? user!.fullName[0].toUpperCase()
                          : '?',
                      style: GoogleFonts.outfit(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ).animate().fadeIn().scale(
                  begin: const Offset(0.8, 0.8),
                  curve: Curves.easeOutBack,
                ),

                const SizedBox(height: 16),
                Text(
                  user?.fullName ?? 'Unknown',
                  style: AppTextStyles.h2,
                ).animate(delay: 200.ms).fadeIn(),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? '',
                  style: AppTextStyles.bodyMedium,
                ).animate(delay: 300.ms).fadeIn(),
                const SizedBox(height: 8),

                // Role badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    user?.role.displayName ?? 'Student',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ).animate(delay: 400.ms).fadeIn(),

                const SizedBox(height: 32),

                // Info cards
                GlassCard(
                  child: Column(
                    children: [
                      _ProfileRow(
                        icon: Icons.email_outlined,
                        label: 'Email',
                        value: user?.email ?? '-',
                      ),
                      const Divider(color: AppColors.glassBorder, height: 20),
                      _ProfileRow(
                        icon: Icons.work_outline_rounded,
                        label: 'Designation',
                        value: user?.role.displayName ?? '-',
                      ),
                      const Divider(color: AppColors.glassBorder, height: 20),
                      _ProfileRow(
                        icon: Icons.phone_outlined,
                        label: 'Phone',
                        value: user?.phone ?? 'Not set',
                      ),
                      const Divider(color: AppColors.glassBorder, height: 20),
                      _ProfileRow(
                        icon: Icons.school_outlined,
                        label: 'Department',
                        value: user?.department ?? 'Not set',
                      ),
                      const Divider(color: AppColors.glassBorder, height: 20),
                      _ProfileRow(
                        icon: Icons.badge_outlined,
                        label: 'ID',
                        value: user?.profileId ?? 'Not set',
                      ),
                      const Divider(color: AppColors.glassBorder, height: 20),
                      _ProfileRow(
                        icon: Icons.calendar_today_outlined,
                        label: 'Joined',
                        value: user?.createdAt.toString().split(' ')[0] ?? '-',
                      ),
                    ],
                  ),
                ).animate(delay: 500.ms).fadeIn().slideY(begin: 0.1),

                const SizedBox(height: 24),

                // Sign out button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => ref.read(authProvider.notifier).signOut(),
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: AppColors.error,
                    ),
                    label: Text(
                      'Sign Out',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ).animate(delay: 600.ms).fadeIn(),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textHint),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption),
            Text(value, style: AppTextStyles.bodyLarge),
          ],
        ),
      ],
    );
  }
}
