/// Booking display status calculated in the app from the real local time.
enum BookingDisplayStatus { upcoming, completed, cancelled }

/// Booking entity — domain model
class BookingEntity {
  final String id;
  final String userId;
  final String roomId;
  final int seatsBooked;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String status;
  final DateTime createdAt;
  final String? purpose;
  final int? seatNumber;

  // Joined/enriched data
  final String? roomName;
  final String? building;
  final int? floor;
  final String? userName;

  const BookingEntity({
    required this.id,
    required this.userId,
    required this.roomId,
    required this.seatsBooked,
    required this.date,
    required this.startTime,
    required this.endTime,
    this.status = 'confirmed',
    required this.createdAt,
    this.purpose,
    this.seatNumber,
    this.roomName,
    this.building,
    this.floor,
    this.userName,
  });

  factory BookingEntity.fromJson(Map<String, dynamic> json) {
    final roomData = json['rooms'] as Map<String, dynamic>?;
    final userData = json['profiles'] as Map<String, dynamic>?;

    return BookingEntity(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      roomId: json['room_id'] as String,
      seatsBooked: _readInt(json['seats_booked']) ?? 1,
      date: _parseDateOnly(json['date']),
      startTime: json['start_time']?.toString() ?? '',
      endTime: json['end_time']?.toString() ?? '',
      status: json['status']?.toString() ?? 'confirmed',
      createdAt: DateTime.tryParse(
            json['created_at']?.toString() ?? '',
          )?.toLocal() ??
          DateTime.now(),
      purpose: json['purpose']?.toString(),
      seatNumber: _readInt(json['seat_number']),
      roomName: roomData?['name']?.toString(),
      building: roomData?['building']?.toString(),
      floor: _readInt(roomData?['floor']),
      userName: userData?['full_name']?.toString(),
    );
  }

  BookingEntity copyWith({
    String? id,
    String? userId,
    String? roomId,
    int? seatsBooked,
    DateTime? date,
    String? startTime,
    String? endTime,
    String? status,
    DateTime? createdAt,
    String? purpose,
    int? seatNumber,
    String? roomName,
    String? building,
    int? floor,
    String? userName,
  }) {
    return BookingEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      roomId: roomId ?? this.roomId,
      seatsBooked: seatsBooked ?? this.seatsBooked,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      purpose: purpose ?? this.purpose,
      seatNumber: seatNumber ?? this.seatNumber,
      roomName: roomName ?? this.roomName,
      building: building ?? this.building,
      floor: floor ?? this.floor,
      userName: userName ?? this.userName,
    );
  }

  bool get isCancelled {
    final normalized = status.toLowerCase().trim();
    return normalized == 'cancelled' || normalized == 'canceled';
  }

  DateTime get bookingStartDateTime => _combineDateAndTime(date, startTime);

  DateTime get bookingEndDateTime => _combineDateAndTime(date, endTime);

  BookingDisplayStatus getDisplayStatus(DateTime now) {
    if (isCancelled) return BookingDisplayStatus.cancelled;

    final endDateTime = bookingEndDateTime;
    if (now.isBefore(endDateTime)) {
      return BookingDisplayStatus.upcoming;
    }
    return BookingDisplayStatus.completed;
  }

  bool isUpcoming(DateTime now) =>
      getDisplayStatus(now) == BookingDisplayStatus.upcoming;

  bool isCompleted(DateTime now) =>
      getDisplayStatus(now) == BookingDisplayStatus.completed;

  String get roomDisplayName =>
      roomName?.trim().isNotEmpty == true ? roomName!.trim() : 'Room ${roomId.substring(0, roomId.length > 8 ? 8 : roomId.length)}';

  String get roomLocationLabel {
    final parts = <String>[];
    if (building?.trim().isNotEmpty == true) parts.add(building!.trim());
    if (floor != null) parts.add('Floor $floor');
    return parts.isEmpty ? 'Campus room' : parts.join(', ');
  }
}

DateTime _parseDateOnly(dynamic value) {
  if (value is DateTime) {
    return DateTime(value.year, value.month, value.day);
  }

  final raw = value?.toString() ?? '';
  final parsed = DateTime.tryParse(raw);
  if (parsed != null) {
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _combineDateAndTime(DateTime date, String timeValue) {
  final parsed = _parseTimeParts(timeValue);
  return DateTime(
    date.year,
    date.month,
    date.day,
    parsed.$1,
    parsed.$2,
    parsed.$3,
  );
}

/// Supports values from Supabase TIME columns and common UI labels:
/// 13:00:00, 13:00, 01:00 PM, 1:00 PM.
(int, int, int) _parseTimeParts(String value) {
  var raw = value.trim();
  if (raw.isEmpty) return (0, 0, 0);

  raw = raw.replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  final hasAm = raw.endsWith(' AM');
  final hasPm = raw.endsWith(' PM');
  raw = raw.replaceAll(' AM', '').replaceAll(' PM', '').trim();

  final parts = raw.split(':');
  var hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
  final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  final second = int.tryParse(parts.length > 2 ? parts[2] : '') ?? 0;

  if (hasPm && hour < 12) hour += 12;
  if (hasAm && hour == 12) hour = 0;

  hour = _clampInt(hour, 0, 23);
  return (hour, _clampInt(minute, 0, 59), _clampInt(second, 0, 59));
}

int _clampInt(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

int? _readInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
