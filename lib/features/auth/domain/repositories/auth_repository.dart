import 'package:unispace/features/auth/domain/entities/app_user.dart';

/// Abstract auth repository — domain layer contract
abstract class AuthRepository {
  /// Get the currently authenticated user profile, or null
  Future<AppUser?> getCurrentUser();

  /// Sign in with email and password
  Future<AppUser> signIn({
    required String email,
    required String password,
  });

  /// Sign up with email, password, and full name
  Future<AppUser> signUp({
    required String email,
    required String password,
    required String fullName,
  });

  /// Sign out the current user
  Future<void> signOut();

  /// Stream of auth state changes
  Stream<AppUser?> authStateChanges();

  /// Update user profile
  Future<AppUser> updateProfile({
    String? fullName,
    String? phone,
    String? department,
    String? avatarUrl,
  });
}
