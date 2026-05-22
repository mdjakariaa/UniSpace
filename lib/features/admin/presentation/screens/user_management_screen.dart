import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:unispace/app/theme/app_colors.dart';
import 'package:unispace/app/theme/app_text_styles.dart';
import 'package:unispace/core/widgets/glass_card.dart';
import 'package:unispace/core/constants/app_constants.dart';
import 'package:unispace/features/admin/presentation/providers/admin_provider.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});
  @override
  ConsumerState<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  String _searchQuery = '';
  String _roleFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0.3, -0.5), radius: 1.8,
            colors: [Color(0xFF1A0A30), AppColors.background]),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(children: [
                  IconButton(onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.textPrimary, size: 20)),
                  const SizedBox(width: 8),
                  Text('User Management', style: AppTextStyles.h2),
                ]),
              ).animate().fadeIn().slideX(begin: -0.1),
              const SizedBox(height: 20),
              // Search
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  decoration: BoxDecoration(color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.glassBorder)),
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                    decoration: InputDecoration(hintText: 'Search users...', prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
                      border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                  ),
                ),
              ).animate(delay: 100.ms).fadeIn(),
              const SizedBox(height: 14),
              // Filter chips
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(children: [
                  _chip('All', 'all', AppColors.primary),
                  const SizedBox(width: 8),
                  _chip('Students', 'student', AppColors.primary),
                  const SizedBox(width: 8),
                  _chip('Teachers', 'teacher', AppColors.accent),
                  const SizedBox(width: 8),
                  _chip('Admins', 'admin', AppColors.warning),
                ]),
              ).animate(delay: 200.ms).fadeIn(),
              const SizedBox(height: 16),
              Expanded(
                child: usersAsync.when(
                  data: (users) {
                    var filtered = users.toList();
                    if (_roleFilter != 'all') filtered = filtered.where((u) => u.role.name == _roleFilter).toList();
                    if (_searchQuery.isNotEmpty) filtered = filtered.where((u) =>
                      u.fullName.toLowerCase().contains(_searchQuery) || u.email.toLowerCase().contains(_searchQuery)).toList();
                    if (filtered.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.people_outline_rounded, size: 64, color: AppColors.textHint.withOpacity(0.4)),
                      const SizedBox(height: 16), Text('No users found', style: AppTextStyles.bodyMedium)]));
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final u = filtered[i];
                        final c = u.role == UserRole.student ? AppColors.primary : u.role == UserRole.teacher ? AppColors.accent : AppColors.warning;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassCard(padding: const EdgeInsets.all(16), child: Row(children: [
                            Container(width: 48, height: 48, decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [c.withOpacity(0.6), c]), borderRadius: BorderRadius.circular(14)),
                              child: Center(child: Text(u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : '?',
                                style: AppTextStyles.h3.copyWith(color: Colors.white)))),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(u.fullName, style: AppTextStyles.labelLarge, overflow: TextOverflow.ellipsis),
                              Text(u.email, style: AppTextStyles.caption, overflow: TextOverflow.ellipsis)])),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                              child: Text(u.role.displayName, style: AppTextStyles.caption.copyWith(color: c, fontWeight: FontWeight.w600))),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, color: AppColors.textHint, size: 20),
                              color: AppColors.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'role', child: Text('Change Role')),
                                const PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                              onSelected: (v) {
                                if (v == 'role') _showRoleDialog(u.id, u.role);
                                if (v == 'delete') ref.read(adminServiceProvider).deleteUser(u.id);
                              }),
                          ])),
                        ).animate(delay: Duration(milliseconds: 80 * i)).fadeIn().slideX(begin: 0.05);
                      });
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

  Widget _chip(String label, String value, Color color) {
    final sel = _roleFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _roleFilter = value),
      child: AnimatedContainer(duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: sel ? color.withOpacity(0.2) : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? color : AppColors.glassBorder)),
        child: Text(label, style: AppTextStyles.labelMedium.copyWith(color: sel ? color : AppColors.textSecondary))),
    );
  }

  void _showRoleDialog(String userId, UserRole currentRole) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Change Role', style: AppTextStyles.h3),
      content: Column(mainAxisSize: MainAxisSize.min, children: UserRole.values.map((role) => ListTile(
        leading: Icon(role == currentRole ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: role == currentRole ? AppColors.primary : AppColors.textHint),
        title: Text(role.displayName, style: AppTextStyles.bodyLarge),
        onTap: () { Navigator.pop(ctx); if (role != currentRole) ref.read(adminServiceProvider).updateUserRole(userId, role.name); },
      )).toList()),
    ));
  }
}
