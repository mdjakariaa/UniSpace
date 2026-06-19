/// Application-wide constants and enumerations
class AppConstants {
  AppConstants._();

  static const String appName = 'UniSpace';
  static const String appTagline = 'Smart Study Spaces';

  // Time slot configuration
  static const int slotDurationMinutes = 60;
  static const int startHour = 8;
  static const int endHour = 22;

  // Group limits
  static const int maxGroupMembers = 10;
}

/// User roles in the system
enum UserRole {
  student,
  teacher,
  admin;

  String get displayName {
    switch (this) {
      case UserRole.student:
        return 'Student';
      case UserRole.teacher:
        return 'Teacher';
      case UserRole.admin:
        return 'Admin';
    }
  }
}

/// Room status states
enum RoomStatus {
  available,
  fullyBooked,
  pendingApproval,
  unavailable;

  String get displayName {
    switch (this) {
      case RoomStatus.available:
        return 'Available';
      case RoomStatus.fullyBooked:
        return 'Fully Booked';
      case RoomStatus.pendingApproval:
        return 'Pending Approval';
      case RoomStatus.unavailable:
        return 'Unavailable';
    }
  }

  String get value {
    switch (this) {
      case RoomStatus.available:
        return 'available';
      case RoomStatus.fullyBooked:
        return 'fully_booked';
      case RoomStatus.pendingApproval:
        return 'pending_approval';
      case RoomStatus.unavailable:
        return 'unavailable';
    }
  }

  static RoomStatus fromString(String value) {
    switch (value) {
      case 'available':
        return RoomStatus.available;
      case 'fully_booked':
        return RoomStatus.fullyBooked;
      case 'pending_approval':
        return RoomStatus.pendingApproval;
      case 'unavailable':
        return RoomStatus.unavailable;
      default:
        return RoomStatus.available;
    }
  }
}

/// Booking status states
enum BookingStatus {
  confirmed,
  cancelled,
  completed,
  pending;

  String get displayName {
    switch (this) {
      case BookingStatus.confirmed:
        return 'Confirmed';
      case BookingStatus.cancelled:
        return 'Cancelled';
      case BookingStatus.completed:
        return 'Completed';
      case BookingStatus.pending:
        return 'Pending';
    }
  }
}

/// Notification types
enum NotificationType {
  bookingConfirmed,
  bookingCancelled,
  groupInvite,
  requestApproved,
  requestRejected,
  reminder,
  system;

  String get value {
    switch (this) {
      case NotificationType.bookingConfirmed:
        return 'booking_confirmed';
      case NotificationType.bookingCancelled:
        return 'booking_cancelled';
      case NotificationType.groupInvite:
        return 'group_invite';
      case NotificationType.requestApproved:
        return 'request_approved';
      case NotificationType.requestRejected:
        return 'request_rejected';
      case NotificationType.reminder:
        return 'reminder';
      case NotificationType.system:
        return 'system';
    }
  }
}
