import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:unispace/core/constants/app_constants.dart';
import 'package:unispace/core/errors/exceptions.dart';
import 'package:unispace/features/auth/data/models/user_model.dart';

/// Remote data source that interacts directly with Supabase
class AuthRemoteDataSource {
  final SupabaseClient _client;

  AuthRemoteDataSource(this._client);

  /// Get the current user's profile from the profiles table
  Future<UserModel?> getCurrentUser() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return null;

      final response = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (response == null) return null;
      return UserModel.fromJson(response);
    } catch (e) {
      throw ServerException('Failed to get current user: $e');
    }
  }

  /// Sign in with email and password
  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw AppAuthException('Sign in failed: no user returned');
      }

      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', response.user!.id)
          .single();

      return UserModel.fromJson(profile);
    } on AuthApiException catch (e) {
      throw AppAuthException(e.message);
    } on AppAuthException {
      rethrow;
    } catch (e) {
      throw ServerException('Sign in failed: $e');
    }
  }

  /// Sign up with email, password, and full name
  Future<UserModel> signUp({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
    required String department,
    required String profileId,
    required String phone,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'role': role.name,
          'department': department,
          'profile_id': profileId,
          'phone': phone,
        },
      );

      if (response.user == null) {
        throw AppAuthException('Sign up failed: no user returned');
      }

      // Wait briefly for the trigger to create the profile
      await Future.delayed(const Duration(milliseconds: 500));

      await _client.from('profiles').upsert({
        'id': response.user!.id,
        'email': email,
        'full_name': fullName,
        'role': role.name,
        'department': department,
        'profile_id': profileId,
        'phone': phone,
        'status': 'active',
      });

      // Fetch the profile created by the database trigger or upsert
      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', response.user!.id)
          .maybeSingle();

      if (profile != null) {
        return UserModel.fromJson(profile);
      }

      return UserModel(
        id: response.user!.id,
        email: email,
        fullName: fullName,
        role: role,
        phone: phone,
        department: department,
        profileId: profileId,
        createdAt: DateTime.now(),
      );
    } on AuthApiException catch (e) {
      throw AppAuthException(e.message);
    } on AppAuthException {
      rethrow;
    } catch (e) {
      throw ServerException('Sign up failed: $e');
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      throw ServerException('Sign out failed: $e');
    }
  }

  /// Stream auth state changes
  Stream<UserModel?> authStateChanges() {
    return _client.auth.onAuthStateChange.asyncMap((event) async {
      if (event.session?.user == null) return null;

      try {
        final profile = await _client
            .from('profiles')
            .select()
            .eq('id', event.session!.user.id)
            .maybeSingle();

        if (profile == null) return null;
        return UserModel.fromJson(profile);
      } catch (_) {
        return null;
      }
    });
  }

  /// Update user profile
  Future<UserModel> updateProfile({
    required String userId,
    String? fullName,
    String? phone,
    String? department,
    String? profileId,
    String? avatarUrl,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (fullName != null) updates['full_name'] = fullName;
      if (phone != null) updates['phone'] = phone;
      if (department != null) updates['department'] = department;
      if (profileId != null) updates['profile_id'] = profileId;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

      await _client.from('profiles').update(updates).eq('id', userId);

      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      return UserModel.fromJson(profile);
    } catch (e) {
      throw ServerException('Failed to update profile: $e');
    }
  }
}
