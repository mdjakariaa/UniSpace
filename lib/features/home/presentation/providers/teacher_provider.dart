import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Teacher's room requests stream
final teacherRequestsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return Stream.value([]);

  return client
      .from('room_requests')
      .stream(primaryKey: ['id'])
      .eq('requested_by', userId)
      .order('created_at', ascending: false);
});

/// Teacher service for cancellation requests
class TeacherService {
  final SupabaseClient _client;
  TeacherService(this._client);

  /// Submit a room cancellation/release request
  Future<void> submitCancelRequest({
    required String roomId,
    required String reason,
  }) async {
    final userId = _client.auth.currentUser!.id;

    // Create room request
    await _client.from('room_requests').insert({
      'room_id': roomId,
      'requested_by': userId,
      'request_type': 'cancel',
      'reason': reason,
      'status': 'pending',
    });

    // Set room to pending approval
    await _client.from('rooms').update({
      'status': 'pending_approval',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', roomId);

    // Notify all admins
    final admins = await _client
        .from('profiles')
        .select('id')
        .eq('role', 'admin');

    for (final admin in admins) {
      await _client.from('notifications').insert({
        'user_id': admin['id'],
        'title': 'New Cancellation Request',
        'body': 'A teacher has requested to release a room. Please review.',
        'type': 'system',
        'data': {'room_id': roomId},
      });
    }
  }
}

final teacherServiceProvider = Provider<TeacherService>((ref) {
  return TeacherService(Supabase.instance.client);
});
