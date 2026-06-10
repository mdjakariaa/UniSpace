import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fixed UniSpace study/booking slots shared with the slot availability system.
class StudyTimeSlot {
  final String label;
  final String startTime;
  final String endTime;

  const StudyTimeSlot({
    required this.label,
    required this.startTime,
    required this.endTime,
  });
}

const List<StudyTimeSlot> fixedStudyTimeSlots = [
  StudyTimeSlot(label: '08:00 AM – 09:00 AM', startTime: '08:00:00', endTime: '09:00:00'),
  StudyTimeSlot(label: '09:00 AM – 10:00 AM', startTime: '09:00:00', endTime: '10:00:00'),
  StudyTimeSlot(label: '10:00 AM – 11:00 AM', startTime: '10:00:00', endTime: '11:00:00'),
  StudyTimeSlot(label: '11:00 AM – 12:00 PM', startTime: '11:00:00', endTime: '12:00:00'),
  StudyTimeSlot(label: '12:00 PM – 01:00 PM', startTime: '12:00:00', endTime: '13:00:00'),
  StudyTimeSlot(label: '01:00 PM – 02:00 PM', startTime: '13:00:00', endTime: '14:00:00'),
  StudyTimeSlot(label: '02:00 PM – 03:00 PM', startTime: '14:00:00', endTime: '15:00:00'),
  StudyTimeSlot(label: '03:00 PM – 04:00 PM', startTime: '15:00:00', endTime: '16:00:00'),
];

/// Query key for room/date based slot availability.
class RoomSlotAvailabilityQuery {
  final String roomId;
  final DateTime date;

  const RoomSlotAvailabilityQuery({required this.roomId, required this.date});

  String get dateString => date.toIso8601String().split('T').first;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomSlotAvailabilityQuery &&
          runtimeType == other.runtimeType &&
          roomId == other.roomId &&
          dateString == other.dateString;

  @override
  int get hashCode => Object.hash(roomId, dateString);
}

/// A slot row returned by get_room_slot_availability().
class RoomSlotAvailabilityEntity {
  final String slotKey;
  final String timeSlot;
  final int totalSeats;
  final int bookedSeats;
  final int availableSeats;
  final String slotStatus;
  final String? teacherName;
  final String? teacherEmail;
  final String? teacherBookingId;

  const RoomSlotAvailabilityEntity({
    required this.slotKey,
    required this.timeSlot,
    required this.totalSeats,
    required this.bookedSeats,
    required this.availableSeats,
    required this.slotStatus,
    this.teacherName,
    this.teacherEmail,
    this.teacherBookingId,
  });

  factory RoomSlotAvailabilityEntity.fromJson(Map<String, dynamic> json) {
    return RoomSlotAvailabilityEntity(
      slotKey: json['slot_key']?.toString() ?? '',
      timeSlot: json['time_slot']?.toString() ?? '',
      totalSeats: json['total_seats'] as int? ?? 0,
      bookedSeats: json['booked_seats'] as int? ?? 0,
      availableSeats: json['available_seats'] as int? ?? 0,
      slotStatus: json['slot_status']?.toString() ?? 'available',
      teacherName: json['teacher_name']?.toString(),
      teacherEmail: json['teacher_email']?.toString(),
      teacherBookingId: json['teacher_booking_id']?.toString(),
    );
  }

  bool get isTeacherBlocked => slotStatus == 'blocked_by_admin' || slotStatus == 'cancellation_pending';
  bool get isFullyBooked => slotStatus == 'fully_booked';
  bool get isSelectable => !isTeacherBlocked && !isFullyBooked;

  String get statusLabel {
    if (slotStatus == 'blocked_by_admin') {
      return teacherName == null || teacherName!.trim().isEmpty ? 'Blocked by Teacher' : 'Blocked: $teacherName';
    }
    if (slotStatus == 'cancellation_pending') return 'Teacher Cancellation Pending';
    if (slotStatus == 'fully_booked') return 'Fully booked';
    if (slotStatus == 'partially_booked') return '$availableSeats seats available';
    return 'Available';
  }
}

/// Study group entity shown to every signed-in student.
class StudyGroupEntity {
  final String id;
  final String name;
  final String? description;
  final String? roomId;
  final String? roomName;
  final String? bookingId;
  final String createdBy;
  final String? creatorName;
  final int maxMembers;
  final DateTime? date;
  final String? startTime;
  final String? endTime;
  final String? timeSlot;
  final String status;
  final DateTime createdAt;
  final int memberCount;

  const StudyGroupEntity({
    required this.id,
    required this.name,
    this.description,
    this.roomId,
    this.roomName,
    this.bookingId,
    required this.createdBy,
    this.creatorName,
    this.maxMembers = 10,
    this.date,
    this.startTime,
    this.endTime,
    this.timeSlot,
    this.status = 'active',
    required this.createdAt,
    this.memberCount = 0,
  });

  factory StudyGroupEntity.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? creatorProfile,
    Map<String, dynamic>? room,
  }) {
    final start = json['start_time']?.toString();
    final end = json['end_time']?.toString();
    return StudyGroupEntity(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled Group',
      description: json['description'] as String?,
      roomId: json['room_id'] as String?,
      roomName: room?['name']?.toString(),
      bookingId: json['booking_id'] as String?,
      createdBy: json['created_by'] as String,
      creatorName: creatorProfile?['full_name']?.toString(),
      maxMembers: json['max_members'] as int? ?? 10,
      date: json['date'] != null ? DateTime.tryParse(json['date'].toString()) : null,
      startTime: start,
      endTime: end,
      timeSlot: (json['time_slot']?.toString().trim().isNotEmpty ?? false)
          ? json['time_slot'].toString()
          : _slotLabelFromTimes(start, end),
      status: json['status'] as String? ?? 'active',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      memberCount: json['member_count'] as int? ?? 0,
    );
  }

  bool get isFull => memberCount >= maxMembers;
}

class GroupMemberEntity {
  final String id;
  final String groupId;
  final String userId;
  final String role;
  final String name;
  final String contactNumber;
  final String batch;
  final String department;
  final String? email;
  final DateTime joinedAt;

  const GroupMemberEntity({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.role,
    required this.name,
    required this.contactNumber,
    required this.batch,
    required this.department,
    this.email,
    required this.joinedAt,
  });

  factory GroupMemberEntity.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? profile,
  }) {
    return GroupMemberEntity(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String? ?? 'member',
      name: _firstNonEmpty([
        json['name'],
        profile?['full_name'],
        profile?['email'],
        'Student',
      ]),
      contactNumber: _firstNonEmpty([json['contact_number'], profile?['phone'], 'Not provided']),
      batch: _firstNonEmpty([json['batch'], 'Not provided']),
      department: _firstNonEmpty([json['department'], profile?['department'], 'Not provided']),
      email: profile?['email']?.toString(),
      joinedAt: DateTime.tryParse(json['joined_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  bool get isAdmin => role == 'admin';
}

class GroupJoinRequestEntity {
  final String id;
  final String groupId;
  final String studentId;
  final String name;
  final String contactNumber;
  final String batch;
  final String department;
  final String status;
  final DateTime requestedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;

  const GroupJoinRequestEntity({
    required this.id,
    required this.groupId,
    required this.studentId,
    required this.name,
    required this.contactNumber,
    required this.batch,
    required this.department,
    required this.status,
    required this.requestedAt,
    this.reviewedBy,
    this.reviewedAt,
  });

  factory GroupJoinRequestEntity.fromJson(Map<String, dynamic> json) {
    return GroupJoinRequestEntity(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      studentId: json['student_id'] as String,
      name: json['name'] as String? ?? 'Student',
      contactNumber: json['contact_number'] as String? ?? 'Not provided',
      batch: json['batch'] as String? ?? 'Not provided',
      department: json['department'] as String? ?? 'Not provided',
      status: json['status'] as String? ?? 'pending',
      requestedAt: DateTime.tryParse(json['requested_at']?.toString() ?? '') ?? DateTime.now(),
      reviewedBy: json['reviewed_by'] as String?,
      reviewedAt: json['reviewed_at'] != null ? DateTime.tryParse(json['reviewed_at'].toString()) : null,
    );
  }
}

enum GroupUserStatus { none, pending, member, admin }

/// All active study groups. The stream reacts to Supabase Realtime updates.
final allStudyGroupsProvider = StreamProvider.autoDispose<List<StudyGroupEntity>>((ref) async* {
  final client = Supabase.instance.client;
  if (client.auth.currentUser == null) {
    yield <StudyGroupEntity>[];
    return;
  }

  final groupStream = client
      .from('study_groups')
      .stream(primaryKey: ['id'])
      .eq('status', 'active')
      .order('created_at', ascending: false);

  await for (final rows in groupStream) {
    yield await _hydrateGroups(client, rows);
  }
});

/// Backward compatible alias for older screens/imports.
final userGroupsProvider = allStudyGroupsProvider;

final groupMembersProvider = StreamProvider.autoDispose
    .family<List<GroupMemberEntity>, String>((ref, groupId) async* {
  final client = Supabase.instance.client;
  if (client.auth.currentUser == null) {
    yield <GroupMemberEntity>[];
    return;
  }

  final memberStream = client
      .from('group_members')
      .stream(primaryKey: ['id'])
      .eq('group_id', groupId)
      .order('joined_at', ascending: true);

  await for (final rows in memberStream) {
    final profileMap = await _loadProfiles(
      client,
      rows.map((row) => row['user_id']?.toString()).whereType<String>().toSet(),
    );
    yield rows
        .map((row) => GroupMemberEntity.fromJson(row, profile: profileMap[row['user_id']?.toString()]))
        .toList();
  }
});

final groupJoinRequestsProvider = StreamProvider.autoDispose
    .family<List<GroupJoinRequestEntity>, String>((ref, groupId) {
  final client = Supabase.instance.client;
  if (client.auth.currentUser == null) return Stream.value(<GroupJoinRequestEntity>[]);

  return client
      .from('group_join_requests')
      .stream(primaryKey: ['id'])
      .eq('group_id', groupId)
      .order('requested_at', ascending: false)
      .map((rows) => rows.map((row) => GroupJoinRequestEntity.fromJson(row)).toList());
});

/// Room/date slot availability used by Study Group create/edit dialogs.
final groupRoomSlotAvailabilityProvider = StreamProvider.autoDispose
    .family<List<RoomSlotAvailabilityEntity>, RoomSlotAvailabilityQuery>((ref, query) async* {
  final client = Supabase.instance.client;
  if (client.auth.currentUser == null || query.roomId.trim().isEmpty) {
    yield <RoomSlotAvailabilityEntity>[];
    return;
  }

  final service = GroupService(client);

  Future<List<RoomSlotAvailabilityEntity>> load() => service.getRoomSlotAvailability(
        roomId: query.roomId,
        date: query.date,
      );

  yield await load();

  final bookingStream = client
      .from('bookings')
      .stream(primaryKey: ['id'])
      .eq('room_id', query.roomId);

  await for (final _ in bookingStream) {
    yield await load();
  }
});

/// Current user's status for a group. It updates when member or join request rows change.
final currentUserGroupStatusProvider = StreamProvider.autoDispose
    .family<GroupUserStatus, String>((ref, groupId) async* {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) {
    yield GroupUserStatus.none;
    return;
  }

  Future<GroupUserStatus> loadStatus() => GroupService(client).checkCurrentUserGroupStatus(groupId);

  yield await loadStatus();

  final members = client.from('group_members').stream(primaryKey: ['id']).eq('group_id', groupId);
  final requests = client.from('group_join_requests').stream(primaryKey: ['id']).eq('group_id', groupId);
  final controller = StreamController<GroupUserStatus>();
  ref.onDispose(controller.close);

  void refresh() async {
    if (controller.isClosed) return;
    controller.add(await loadStatus());
  }

  final sub1 = members.listen((_) => refresh());
  final sub2 = requests.listen((_) => refresh());
  ref.onDispose(() {
    sub1.cancel();
    sub2.cancel();
  });

  await for (final status in controller.stream) {
    yield status;
  }
});

/// Group service for all Study Group operations.
class GroupService {
  final SupabaseClient _client;
  GroupService(this._client);

  Future<String> createGroup({
    required String name,
    String? description,
    String? roomId,
    int maxMembers = 10,
    required DateTime date,
    required String startTime,
    required String endTime,
  }) async {
    final result = await _client.rpc('create_study_group_with_admin', params: {
      'p_name': name,
      'p_description': description,
      'p_date': date.toIso8601String().split('T').first,
      'p_start_time': startTime,
      'p_end_time': endTime,
      'p_max_members': maxMembers,
      'p_room_id': roomId,
    });
    return result as String;
  }

  Future<void> updateStudyGroup({
    required String groupId,
    required String name,
    String? description,
    String? roomId,
    required int maxMembers,
    required DateTime date,
    required String startTime,
    required String endTime,
  }) async {
    await _client.rpc('update_study_group_details', params: {
      'p_group_id': groupId,
      'p_name': name,
      'p_description': description,
      'p_date': date.toIso8601String().split('T').first,
      'p_start_time': startTime,
      'p_end_time': endTime,
      'p_max_members': maxMembers,
      'p_room_id': roomId,
    });
  }

  Future<void> deleteStudyGroup(String groupId) async {
    await _client.rpc('cancel_study_group_by_admin', params: {'p_group_id': groupId});
  }

  Future<void> requestToJoinGroup({
    required String groupId,
    required String name,
    required String contactNumber,
    required String batch,
    required String department,
  }) async {
    await _client.rpc('request_to_join_group', params: {
      'p_group_id': groupId,
      'p_name': name,
      'p_contact_number': contactNumber,
      'p_batch': batch,
      'p_department': department,
    });
  }

  Future<void> approveJoinRequest(String requestId) async {
    await _client.rpc('approve_group_join_request', params: {'p_request_id': requestId});
  }

  Future<void> rejectJoinRequest(String requestId) async {
    await _client.rpc('reject_group_join_request', params: {'p_request_id': requestId});
  }

  Future<void> removeGroupMember({
    required String groupId,
    required String memberUserId,
  }) async {
    await _client.rpc('remove_group_member', params: {
      'p_group_id': groupId,
      'p_member_id': memberUserId,
    });
  }

  Future<List<RoomSlotAvailabilityEntity>> getRoomSlotAvailability({
    required String roomId,
    required DateTime date,
  }) async {
    if (roomId.trim().isEmpty) return <RoomSlotAvailabilityEntity>[];
    final rows = await _client.rpc('get_room_slot_availability', params: {
      'p_room_id': roomId,
      'p_date': date.toIso8601String().split('T').first,
    });
    return List<Map<String, dynamic>>.from(rows)
        .map((row) => RoomSlotAvailabilityEntity.fromJson(row))
        .toList();
  }

  Future<List<GroupMemberEntity>> getGroupMembers(String groupId) async {
    final rows = await _client
        .from('group_members')
        .select()
        .eq('group_id', groupId)
        .order('joined_at', ascending: true);
    final list = List<Map<String, dynamic>>.from(rows);
    final profileMap = await _loadProfiles(
      _client,
      list.map((row) => row['user_id']?.toString()).whereType<String>().toSet(),
    );
    return list
        .map((row) => GroupMemberEntity.fromJson(row, profile: profileMap[row['user_id']?.toString()]))
        .toList();
  }

  Future<List<GroupJoinRequestEntity>> getGroupJoinRequests(String groupId) async {
    final rows = await _client
        .from('group_join_requests')
        .select()
        .eq('group_id', groupId)
        .order('requested_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows)
        .map((row) => GroupJoinRequestEntity.fromJson(row))
        .toList();
  }

  Future<GroupUserStatus> checkCurrentUserGroupStatus(String groupId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return GroupUserStatus.none;

    final member = await _client
        .from('group_members')
        .select('role')
        .eq('group_id', groupId)
        .eq('user_id', userId)
        .maybeSingle();

    if (member != null) {
      return member['role'] == 'admin' ? GroupUserStatus.admin : GroupUserStatus.member;
    }

    final pending = await _client
        .from('group_join_requests')
        .select('id')
        .eq('group_id', groupId)
        .eq('student_id', userId)
        .eq('status', 'pending')
        .maybeSingle();

    if (pending != null) return GroupUserStatus.pending;
    return GroupUserStatus.none;
  }
}

final groupServiceProvider = Provider<GroupService>((ref) {
  return GroupService(Supabase.instance.client);
});

Future<List<StudyGroupEntity>> _hydrateGroups(
  SupabaseClient client,
  List<Map<String, dynamic>> rows,
) async {
  if (rows.isEmpty) return <StudyGroupEntity>[];

  final creatorIds = rows.map((row) => row['created_by']?.toString()).whereType<String>().toSet();
  final roomIds = rows.map((row) => row['room_id']?.toString()).whereType<String>().toSet();

  final profiles = await _loadProfiles(client, creatorIds);
  final rooms = await _loadRooms(client, roomIds);

  return rows
      .map((row) => StudyGroupEntity.fromJson(
            row,
            creatorProfile: profiles[row['created_by']?.toString()],
            room: rooms[row['room_id']?.toString()],
          ))
      .toList();
}

Future<Map<String, Map<String, dynamic>>> _loadProfiles(
  SupabaseClient client,
  Set<String> ids,
) async {
  if (ids.isEmpty) return <String, Map<String, dynamic>>{};
  final rows = await client
      .from('profiles')
      .select('id, full_name, email, phone, department')
      .inFilter('id', ids.toList());
  return {
    for (final row in List<Map<String, dynamic>>.from(rows)) row['id'].toString(): row,
  };
}

Future<Map<String, Map<String, dynamic>>> _loadRooms(
  SupabaseClient client,
  Set<String> ids,
) async {
  if (ids.isEmpty) return <String, Map<String, dynamic>>{};
  final rows = await client.from('rooms').select('id, name, building, floor').inFilter('id', ids.toList());
  return {
    for (final row in List<Map<String, dynamic>>.from(rows)) row['id'].toString(): row,
  };
}

String? _slotLabelFromTimes(String? start, String? end) {
  if (start == null || end == null) return null;
  for (final slot in fixedStudyTimeSlots) {
    if (_normalizeTime(start) == _normalizeTime(slot.startTime) &&
        _normalizeTime(end) == _normalizeTime(slot.endTime)) {
      return slot.label;
    }
  }
  return '$start – $end';
}

String _normalizeTime(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return value;
  return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}:00';
}

String _slotKeyFromSlot(StudyTimeSlot slot) {
  String compact(String value) {
    final parts = value.split(':');
    return '${parts[0].padLeft(2, '0')}:${parts.length > 1 ? parts[1].padLeft(2, '0') : '00'}';
  }
  return '${compact(slot.startTime)}|${compact(slot.endTime)}';
}

RoomSlotAvailabilityEntity? availabilityForSlot(
  List<RoomSlotAvailabilityEntity> availability,
  StudyTimeSlot slot,
) {
  final key = _slotKeyFromSlot(slot);
  for (final item in availability) {
    if (item.slotKey == key || item.timeSlot == slot.label) return item;
  }
  return null;
}

String _firstNonEmpty(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
  }
  return '';
}
