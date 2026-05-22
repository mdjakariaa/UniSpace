import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unispace/core/constants/app_constants.dart';
import 'package:unispace/features/auth/presentation/providers/auth_provider.dart';
import 'package:unispace/features/auth/presentation/screens/login_screen.dart';
import 'package:unispace/features/auth/presentation/screens/signup_screen.dart';
import 'package:unispace/features/auth/presentation/screens/splash_screen.dart';
import 'package:unispace/features/home/presentation/screens/student_home_screen.dart';
import 'package:unispace/features/home/presentation/screens/teacher_dashboard_screen.dart';
import 'package:unispace/features/home/presentation/screens/admin_dashboard_screen.dart';
import 'package:unispace/features/home/presentation/shell/app_shell.dart';
import 'package:unispace/features/rooms/presentation/screens/room_details_screen.dart';
import 'package:unispace/features/booking/presentation/screens/booking_screen.dart';
import 'package:unispace/features/booking/presentation/screens/my_bookings_screen.dart';
import 'package:unispace/features/groups/presentation/screens/groups_screen.dart';
import 'package:unispace/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:unispace/features/profile/presentation/screens/profile_screen.dart';
import 'package:unispace/features/admin/presentation/screens/user_management_screen.dart';
import 'package:unispace/features/admin/presentation/screens/room_management_screen.dart';
import 'package:unispace/features/admin/presentation/screens/approval_panel_screen.dart';

/// Application router with role-based navigation guards
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/splash',
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final isLoading = authState.status == AuthStatus.initial ||
          authState.status == AuthStatus.loading;
      final isAuthenticated = authState.status == AuthStatus.authenticated;
      final isOnAuth = state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup';
      final isOnSplash = state.matchedLocation == '/splash';

      // Still loading — stay on splash
      if (isLoading && isOnSplash) return null;
      if (isLoading) return '/splash';

      // Not authenticated — go to login
      if (!isAuthenticated && !isOnAuth) return '/login';

      // Authenticated but on auth/splash screen — redirect to role dashboard
      if (isAuthenticated && (isOnAuth || isOnSplash)) {
        final role = authState.user?.role ?? UserRole.student;
        switch (role) {
          case UserRole.student:
            return '/home';
          case UserRole.teacher:
            return '/teacher';
          case UserRole.admin:
            return '/admin';
        }
      }

      return null;
    },
    routes: [
      // Auth routes
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),

      // Student shell with bottom nav
      ShellRoute(
        builder: (context, state, child) => AppShell(
          role: UserRole.student,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const StudentHomeScreen(),
          ),
          GoRoute(
            path: '/bookings',
            builder: (context, state) => const MyBookingsScreen(),
          ),
          GoRoute(
            path: '/groups',
            builder: (context, state) => const GroupsScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),

      // Teacher shell
      ShellRoute(
        builder: (context, state, child) => AppShell(
          role: UserRole.teacher,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/teacher',
            builder: (context, state) => const TeacherDashboardScreen(),
          ),
          GoRoute(
            path: '/teacher/notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/teacher/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),

      // Admin shell
      ShellRoute(
        builder: (context, state, child) => AppShell(
          role: UserRole.admin,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/admin',
            builder: (context, state) => const AdminDashboardScreen(),
          ),
          GoRoute(
            path: '/admin/users',
            builder: (context, state) => const UserManagementScreen(),
          ),
          GoRoute(
            path: '/admin/rooms',
            builder: (context, state) => const RoomManagementScreen(),
          ),
          GoRoute(
            path: '/admin/approvals',
            builder: (context, state) => const ApprovalPanelScreen(),
          ),
          GoRoute(
            path: '/admin/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),

      // Standalone routes (no bottom nav)
      GoRoute(
        path: '/room/:id',
        builder: (context, state) => RoomDetailsScreen(
          roomId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/book/:roomId',
        builder: (context, state) => BookingScreen(
          roomId: state.pathParameters['roomId']!,
        ),
      ),
    ],
  );
});
