import 'package:unispace/core/constants/app_constants.dart';

/// Core user entity — pure Dart, no framework dependencies
class AppUser {
  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final String? avatarUrl;
  final String? phone;
  final String? department;
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.avatarUrl,
    this.phone,
    this.department,
    required this.createdAt,
  });

  AppUser copyWith({
    String? fullName,
    String? avatarUrl,
    String? phone,
    String? department,
  }) {
    return AppUser(
      id: id,
      email: email,
      fullName: fullName ?? this.fullName,
      role: role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phone: phone ?? this.phone,
      department: department ?? this.department,
      createdAt: createdAt,
    );
  }
}
