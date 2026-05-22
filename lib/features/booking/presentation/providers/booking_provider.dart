import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:unispace/features/booking/domain/entities/booking.dart';

export 'package:unispace/features/booking/domain/entities/booking.dart';

/// User's bookings stream provider.
///
/// Supabase realtime streams return booking rows only, so room details are
/// loaded separately and merged into the BookingEntity. This keeps the My
/// Bookings page readable without changing the database schema.
final userBookingsProvider = StreamProvider<List<BookingEntity>>((ref) {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return Stream.value([]);

  return client
      .from('bookings')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .order('date', ascending: false)
      .asyncMap((rows) => _hydrateBookings(client, rows));
});

/// All bookings (admin view)
final allBookingsProvider = StreamProvider<List<BookingEntity>>((ref) {
  final client = Supabase.instance.client;
  return client
      .from('bookings')
      .stream(primaryKey: ['id'])
      .order('date', ascending: false)
      .asyncMap((rows) => _hydrateBookings(client, rows));
});

Future<List<BookingEntity>> _hydrateBookings(
  SupabaseClient client,
  List<Map<String, dynamic>> rows,
) async {
  final bookings = rows.map(BookingEntity.fromJson).toList();
  if (bookings.isEmpty) return bookings;

  final roomIds = bookings.map((booking) => booking.roomId).toSet().toList();
  final roomRows = await client
      .from('rooms')
      .select('id, name, building, floor')
      .inFilter('id', roomIds);

  final roomsById = <String, Map<String, dynamic>>{
    for (final row in List<Map<String, dynamic>>.from(roomRows))
      row['id'].toString(): row,
  };

  return bookings.map((booking) {
    final room = roomsById[booking.roomId];
    if (room == null) return booking;
    return booking.copyWith(
      roomName: room['name']?.toString(),
      building: room['building']?.toString(),
      floor: _readInt(room['floor']),
    );
  }).toList();
}

/// Booking service for creating/cancelling bookings
class BookingService {
  final SupabaseClient _client;
  BookingService(this._client);

  /// Book seats using the RPC function for atomicity
  Future<String> bookSeats({
    required String roomId,
    required int seats,
    required DateTime date,
    required String startTime,
    required String endTime,
  }) async {
    final userId = _client.auth.currentUser!.id;

    try {
      // Try the atomic RPC function first
      final result = await _client.rpc('book_seats', params: {
        'p_room_id': roomId,
        'p_user_id': userId,
        'p_seats': seats,
        'p_date': date.toIso8601String().split('T').first,
        'p_start': startTime,
        'p_end': endTime,
      });
      return result as String;
    } catch (e) {
      // Fallback: manual insert + seat update
      // 1. Check availability
      final room = await _client
          .from('rooms')
          .select('available_seats, total_seats')
          .eq('id', roomId)
          .single();

      final available = room['available_seats'] as int;
      if (available < seats) {
        throw Exception('Not enough seats available ($available remaining)');
      }

      // 2. Insert booking
      final response = await _client.from('bookings').insert({
        'user_id': userId,
        'room_id': roomId,
        'seats_booked': seats,
        'date': date.toIso8601String().split('T').first,
        'start_time': startTime,
        'end_time': endTime,
        'status': 'confirmed',
      }).select('id').single();

      // 3. Update room available seats
      final newAvailable = available - seats;
      await _client.from('rooms').update({
        'available_seats': newAvailable,
        'status': newAvailable == 0 ? 'fully_booked' : 'available',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', roomId);

      // 4. Create notification
      await _client.from('notifications').insert({
        'user_id': userId,
        'title': 'Booking Confirmed',
        'body': 'Your seat booking has been confirmed for ${date.toIso8601String().split('T').first}.',
        'type': 'booking_confirmed',
        'data': {'booking_id': response['id'], 'room_id': roomId},
      });

      return response['id'] as String;
    }
  }

  /// Cancel a booking and restore seats
  Future<void> cancelBooking(String bookingId) async {
    // 1. Get booking details
    final booking = await _client
        .from('bookings')
        .select()
        .eq('id', bookingId)
        .single();

    // 2. Mark as cancelled
    await _client
        .from('bookings')
        .update({'status': 'cancelled'})
        .eq('id', bookingId);

    // 3. Restore seats
    final roomId = booking['room_id'] as String;
    final seatsBooked = booking['seats_booked'] as int;
    final room = await _client
        .from('rooms')
        .select('available_seats, total_seats')
        .eq('id', roomId)
        .single();

    final newAvailable = ((room['available_seats'] as int) + seatsBooked)
        .clamp(0, room['total_seats'] as int);

    await _client.from('rooms').update({
      'available_seats': newAvailable,
      'status': 'available',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', roomId);

    // 4. Notification
    await _client.from('notifications').insert({
      'user_id': booking['user_id'],
      'title': 'Booking Cancelled',
      'body': 'Your booking has been cancelled. Seats have been released.',
      'type': 'booking_cancelled',
      'data': {'booking_id': bookingId, 'room_id': roomId},
    });
  }
}

final bookingServiceProvider = Provider<BookingService>((ref) {
  return BookingService(Supabase.instance.client);
});

int? _readInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
