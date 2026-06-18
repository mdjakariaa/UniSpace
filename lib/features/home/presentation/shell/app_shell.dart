import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unispace/app/theme/app_colors.dart';
import 'package:unispace/core/constants/app_constants.dart';

/// App shell with glassmorphic bottom navigation bar
class AppShell extends ConsumerStatefulWidget {
  final UserRole role;
  final Widget child;

  const AppShell({super.key, required this.role, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;

  List<_NavItem> get _navItems {
    switch (widget.role) {
      case UserRole.student:
        return [
          _NavItem(Icons.home_rounded, 'Home', '/home'),
          _NavItem(Icons.bookmark_rounded, 'Bookings', '/bookings'),
          _NavItem(Icons.group_rounded, 'Groups', '/groups'),
          _NavItem(Icons.notifications_rounded, 'Alerts', '/notifications'),
          _NavItem(Icons.person_rounded, 'Profile', '/profile'),
        ];
      case UserRole.teacher:
        return [
          _NavItem(Icons.dashboard_rounded, 'Dashboard', '/teacher'),
          _NavItem(Icons.notifications_rounded, 'Alerts', '/teacher/notifications'),
          _NavItem(Icons.person_rounded, 'Profile', '/teacher/profile'),
        ];
      case UserRole.admin:
        return [
          _NavItem(Icons.dashboard_rounded, 'Dashboard', '/admin'),
          _NavItem(Icons.people_rounded, 'Users', '/admin/users'),
          _NavItem(Icons.meeting_room_rounded, 'Rooms', '/admin/rooms'),
          _NavItem(Icons.person_rounded, 'Profile', '/admin/profile'),
        ];
    }
  }

  void _onItemTapped(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    context.go(_navItems[index].path);
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync index with current route
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _navItems.indexWhere((item) => item.path == location);
    if (idx != -1 && idx != _currentIndex) {
      setState(() => _currentIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: widget.child,
      extendBody: true,
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.85),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.glassBorder, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(_navItems.length, (index) {
                  final item = _navItems[index];
                  final isSelected = index == _currentIndex;
                  return GestureDetector(
                    onTap: () => _onItemTapped(index),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      padding: EdgeInsets.symmetric(
                        horizontal: isSelected ? 16 : 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withOpacity(0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            child: Icon(
                              item.icon,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textHint,
                              size: isSelected ? 26 : 24,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.label,
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textHint,
                              fontSize: 10,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String path;
  _NavItem(this.icon, this.label, this.path);
}
