import 'package:unispace/core/errors/exceptions.dart';
import 'package:unispace/core/errors/failures.dart';
import 'package:unispace/core/constants/app_constants.dart';
import 'package:unispace/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:unispace/features/auth/domain/entities/app_user.dart';
import 'package:unispace/features/auth/domain/repositories/auth_repository.dart';

/// Concrete implementation of AuthRepository using Supabase
class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;

  AuthRepositoryImpl(this._remoteDataSource);

  @override
  Future<AppUser?> getCurrentUser() async {
    try {
      return await _remoteDataSource.getCurrentUser();
    } on ServerException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _remoteDataSource.signIn(email: email, password: password);
    } on AppAuthException catch (e) {
      throw AuthFailure(e.message);
    } on ServerException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<AppUser> signUp({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
    required String department,
    required String profileId,
    required String phone,
  }) async {
    try {
      return await _remoteDataSource.signUp(
        email: email,
        password: password,
        fullName: fullName,
        role: role,
        department: department,
        profileId: profileId,
        phone: phone,
      );
    } on AppAuthException catch (e) {
      throw AuthFailure(e.message);
    } on ServerException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _remoteDataSource.signOut();
    } on ServerException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Stream<AppUser?> authStateChanges() {
    return _remoteDataSource.authStateChanges();
  }

  @override
  Future<AppUser> updateProfile({
    String? fullName,
    String? phone,
    String? department,
    String? profileId,
    String? avatarUrl,
  }) async {
    try {
      final currentUser = await _remoteDataSource.getCurrentUser();
      if (currentUser == null) {
        throw const AuthFailure('No authenticated user');
      }
      return await _remoteDataSource.updateProfile(
        userId: currentUser.id,
        fullName: fullName,
        phone: phone,
        department: department,
        profileId: profileId,
        avatarUrl: avatarUrl,
      );
    } on AppAuthException catch (e) {
      throw AuthFailure(e.message);
    } on ServerException catch (e) {
      throw ServerFailure(e.message);
    }
  }
}
