import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:unispace/features/auth/data/models/user_model.dart';
import 'package:unispace/features/auth/domain/entities/app_user.dart';

/// All users stream (admin view)
final allUsersProvider = StreamProvider<List<AppUser>>((ref) {
  final client = Supabase.instance.client;
  return client
      .from('profiles')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map((r) => UserModel.fromJson(r)).toList());
});

/// Room requests stream (admin approval panel)
final roomRequestsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final client = Supabase.instance.client;
  return client
      .from('room_requests')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false);
});

/// Pending requests only
final pendingRequestsProvider = Provider<AsyncValue<List<Map<String, dynamic>>>>((ref) {
  final allRequests = ref.watch(roomRequestsProvider);
  return allRequests.whenData(
    (requests) => requests.where((r) => r['status'] == 'pending').toList(),
  );
});

/// Admin service for management operations
class AdminService {
  final SupabaseClient _client;
  AdminService(this._client);

  /// Update a user's role
  Future<void> updateUserRole(String userId, String newRole) async {
    await _client.from('profiles').update({
      'role': newRole,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Delete a user
  Future<void> deleteUser(String userId) async {
    await _client.from('profiles').delete().eq('id', userId);
  }

  /// Approve a room request
  Future<void> approveRequest(String requestId, String roomId) async {
    final adminId = _client.auth.currentUser!.id;

    await _client.from('room_requests').update({
      'status': 'approved',
      'reviewed_by': adminId,
      'reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', requestId);

    // Make room available
    await _client.from('rooms').update({
      'status': 'available',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', roomId);

    // Create notification for requester
    final request = await _client
        .from('room_requests')
        .select('requested_by')
        .eq('id', requestId)
        .single();

    await _client.from('notifications').insert({
      'user_id': request['requested_by'],
      'title': 'Request Approved',
      'body': 'Your room release request has been approved by admin.',
      'type': 'request_approved',
      'data': {'request_id': requestId, 'room_id': roomId},
    });
  }

  /// Reject a room request
  Future<void> rejectRequest(String requestId, String roomId) async {
    final adminId = _client.auth.currentUser!.id;

    await _client.from('room_requests').update({
      'status': 'rejected',
      'reviewed_by': adminId,
      'reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', requestId);

    // Keep room unavailable
    await _client.from('rooms').update({
      'status': 'unavailable',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', roomId);

    // Notify requester
    final request = await _client
        .from('room_requests')
        .select('requested_by')
        .eq('id', requestId)
        .single();

    await _client.from('notifications').insert({
      'user_id': request['requested_by'],
      'title': 'Request Rejected',
      'body': 'Your room release request has been rejected by admin.',
      'type': 'request_rejected',
      'data': {'request_id': requestId, 'room_id': roomId},
    });
  }

  /// Get system analytics
  Future<Map<String, int>> getAnalytics() async {
    final users = await _client.from('profiles').select('id').count(CountOption.exact);
    final rooms = await _client.from('rooms').select('id').count(CountOption.exact);
    final bookings = await _client.from('bookings').select('id').count(CountOption.exact);
    final pending = await _client
        .from('room_requests')
        .select('id')
        .eq('status', 'pending')
        .count(CountOption.exact);

    return {
      'users': users.count,
      'rooms': rooms.count,
      'bookings': bookings.count,
      'pending_requests': pending.count,
    };
  }
}

final adminServiceProvider = Provider<AdminService>((ref) {
  return AdminService(Supabase.instance.client);
});
