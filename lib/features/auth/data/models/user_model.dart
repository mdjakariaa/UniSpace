import 'package:unispace/core/constants/app_constants.dart';
import 'package:unispace/features/auth/domain/entities/app_user.dart';

/// Data model that maps between Supabase JSON and the AppUser entity
class UserModel extends AppUser {
  const UserModel({
    required super.id,
    required super.email,
    required super.fullName,
    required super.role,
    super.avatarUrl,
    super.phone,
    super.department,
    super.profileId,
    required super.createdAt,
  });

  /// Create from Supabase profiles table row
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String? ?? '',
      role: _parseRole(json['role'] as String? ?? 'student'),
      avatarUrl: json['avatar_url'] as String?,
      phone: json['phone'] as String?,
      department: json['department'] as String?,
      profileId: json['profile_id'] as String?,
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  /// Convert to JSON for Supabase upsert
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'role': role.name,
      'avatar_url': avatarUrl,
      'phone': phone,
      'department': department,
      'profile_id': profileId,
    };
  }

  static UserRole _parseRole(String role) {
    switch (role) {
      case 'student':
        return UserRole.student;
      case 'teacher':
        return UserRole.teacher;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.student;
    }
  }
}
