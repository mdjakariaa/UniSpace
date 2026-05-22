import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:unispace/features/rooms/domain/entities/room.dart';

export 'package:unispace/features/rooms/domain/entities/room.dart';

/// Search query state
final roomSearchQueryProvider = StateProvider<String>((ref) => '');

/// Rooms data provider — fetches from Supabase with real-time updates
final roomsProvider = StreamProvider<List<RoomEntity>>((ref) {
  final client = Supabase.instance.client;
  return client
      .from('rooms')
      .stream(primaryKey: ['id'])
      .order('name')
      .map((rows) => rows.map((r) => RoomEntity.fromJson(r)).toList());
});

/// Single room provider
final roomByIdProvider = FutureProvider.family<RoomEntity?, String>((ref, id) async {
  final client = Supabase.instance.client;
  final response = await client.from('rooms').select().eq('id', id).maybeSingle();
  if (response == null) return null;
  return RoomEntity.fromJson(response);
});

/// Room management operations (for admin)
class RoomService {
  final SupabaseClient _client;
  RoomService(this._client);

  Future<void> addRoom({
    required String name,
    required String building,
    required int floor,
    required int totalSeats,
    required List<String> facilities,
  }) async {
    await _client.from('rooms').insert({
      'name': name,
      'building': building,
      'floor': floor,
      'total_seats': totalSeats,
      'available_seats': totalSeats,
      'facilities': facilities,
      'status': 'available',
    });
  }

  Future<void> updateRoom(String id, Map<String, dynamic> updates) async {
    updates['updated_at'] = DateTime.now().toIso8601String();
    await _client.from('rooms').update(updates).eq('id', id);
  }

  Future<void> deleteRoom(String id) async {
    await _client.from('rooms').delete().eq('id', id);
  }
}

final roomServiceProvider = Provider<RoomService>((ref) {
  return RoomService(Supabase.instance.client);
});
