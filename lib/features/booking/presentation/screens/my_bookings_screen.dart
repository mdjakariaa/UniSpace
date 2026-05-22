import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:unispace/app/theme/app_colors.dart';
import 'package:unispace/app/theme/app_text_styles.dart';
import 'package:unispace/core/widgets/glass_card.dart';
import 'package:unispace/features/booking/presentation/providers/booking_provider.dart';

/// Student My Bookings screen with live real-time status calculation.
///
/// Upcoming / Completed are not read from the database status. They are
/// calculated from DateTime.now() and each booking's local end date-time.
class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen> {
  BookingFilter _selectedFilter = BookingFilter.all;
  late DateTime _now;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _statusTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(userBookingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.35, -0.95),
            radius: 1.4,
            colors: [Color(0xFF171241), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: bookingsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
            error: (error, _) => _ErrorState(message: error.toString()),
            data: (bookings) => _buildContent(bookings),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(List<BookingEntity> bookings) {
    final counts = _BookingCounts.fromBookings(bookings, _now);
    final visibleBookings = _filterBookings(bookings);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Bookings', style: AppTextStyles.h1.copyWith(fontSize: 30))
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .slideX(begin: -0.08),
                const SizedBox(height: 6),
                Text(
                  'Track your upcoming and past room reservations',
                  style: AppTextStyles.bodyMedium,
                ),
                const SizedBox(height: 16),
                _LiveTimePill(now: _now),
                const SizedBox(height: 16),
                _SummaryGrid(counts: counts),
                const SizedBox(height: 18),
                _FilterChips(
                  selected: _selectedFilter,
                  counts: counts,
                  onChanged: (filter) => setState(() {
                    _now = DateTime.now();
                    _selectedFilter = filter;
                  }),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
        if (bookings.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              icon: Icons.event_available_rounded,
              title: 'No bookings yet',
              message: 'Book a study room to see your reservations here.',
            ),
          )
        else if (visibleBookings.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              icon: _emptyIcon(_selectedFilter),
              title: _emptyTitle(_selectedFilter),
              message: _emptyMessage(_selectedFilter),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 110),
            sliver: SliverList.builder(
              itemCount: visibleBookings.length,
              itemBuilder: (context, index) {
                final booking = visibleBookings[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _BookingCard(
                    booking: booking,
                    now: _now,
                    onCancel: booking.isUpcoming(_now)
                        ? () => _showCancelConfirmation(booking)
                        : null,
                  )
                      .animate(delay: Duration(milliseconds: 55 * index))
                      .fadeIn(duration: 260.ms)
                      .slideY(begin: 0.06),
                );
              },
            ),
          ),
      ],
    );
  }

  List<BookingEntity> _filterBookings(List<BookingEntity> bookings) {
    final filtered = bookings.where((booking) {
      final status = booking.getDisplayStatus(_now);
      switch (_selectedFilter) {
        case BookingFilter.all:
          return true;
        case BookingFilter.upcoming:
          return status == BookingDisplayStatus.upcoming;
        case BookingFilter.completed:
          return status == BookingDisplayStatus.completed;
        case BookingFilter.cancelled:
          return status == BookingDisplayStatus.cancelled;
      }
    }).toList();

    filtered.sort((a, b) {
      if (_selectedFilter == BookingFilter.upcoming) {
        return a.bookingStartDateTime.compareTo(b.bookingStartDateTime);
      }
      return b.bookingStartDateTime.compareTo(a.bookingStartDateTime);
    });
    return filtered;
  }

  Future<void> _showCancelConfirmation(BookingEntity booking) async {
    final shouldCancel = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _CancelBookingSheet(booking: booking),
    );

    if (shouldCancel != true || !mounted) return;

    try {
      await ref.read(bookingServiceProvider).cancelBooking(booking.id);
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking cancelled successfully'),
          backgroundColor: AppColors.warning,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  IconData _emptyIcon(BookingFilter filter) {
    switch (filter) {
      case BookingFilter.all:
        return Icons.event_available_rounded;
      case BookingFilter.upcoming:
        return Icons.upcoming_rounded;
      case BookingFilter.completed:
        return Icons.task_alt_rounded;
      case BookingFilter.cancelled:
        return Icons.event_busy_rounded;
    }
  }

  String _emptyTitle(BookingFilter filter) {
    switch (filter) {
      case BookingFilter.all:
        return 'No bookings yet';
      case BookingFilter.upcoming:
        return 'No upcoming bookings';
      case BookingFilter.completed:
        return 'No completed bookings';
      case BookingFilter.cancelled:
        return 'No cancelled bookings';
    }
  }

  String _emptyMessage(BookingFilter filter) {
    switch (filter) {
      case BookingFilter.all:
        return 'Book a study room to get started.';
      case BookingFilter.upcoming:
        return 'Your future and currently running bookings will appear here.';
      case BookingFilter.completed:
        return 'Bookings move here automatically after the slot end time passes.';
      case BookingFilter.cancelled:
        return 'Cancelled bookings will appear here.';
    }
  }
}

enum BookingFilter { all, upcoming, completed, cancelled }

extension BookingFilterLabel on BookingFilter {
  String get label {
    switch (this) {
      case BookingFilter.all:
        return 'All';
      case BookingFilter.upcoming:
        return 'Upcoming';
      case BookingFilter.completed:
        return 'Completed';
      case BookingFilter.cancelled:
        return 'Cancelled';
    }
  }
}

class _BookingCounts {
  final int all;
  final int upcoming;
  final int completed;
  final int cancelled;

  const _BookingCounts({
    required this.all,
    required this.upcoming,
    required this.completed,
    required this.cancelled,
  });

  factory _BookingCounts.fromBookings(List<BookingEntity> bookings, DateTime now) {
    var upcoming = 0;
    var completed = 0;
    var cancelled = 0;

    for (final booking in bookings) {
      switch (booking.getDisplayStatus(now)) {
        case BookingDisplayStatus.upcoming:
          upcoming++;
          break;
        case BookingDisplayStatus.completed:
          completed++;
          break;
        case BookingDisplayStatus.cancelled:
          cancelled++;
          break;
      }
    }

    return _BookingCounts(
      all: bookings.length,
      upcoming: upcoming,
      completed: completed,
      cancelled: cancelled,
    );
  }

  int countFor(BookingFilter filter) {
    switch (filter) {
      case BookingFilter.all:
        return all;
      case BookingFilter.upcoming:
        return upcoming;
      case BookingFilter.completed:
        return completed;
      case BookingFilter.cancelled:
        return cancelled;
    }
  }
}

class _LiveTimePill extends StatelessWidget {
  final DateTime now;

  const _LiveTimePill({required this.now});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Live time: ${DateFormat('MMM d, yyyy • h:mm a').format(now)}',
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final _BookingCounts counts;

  const _SummaryGrid({required this.counts});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 2.55,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: [
        _SummaryTile(
          title: 'Total',
          value: counts.all,
          icon: Icons.dashboard_rounded,
          color: AppColors.primary,
        ),
        _SummaryTile(
          title: 'Upcoming',
          value: counts.upcoming,
          icon: Icons.schedule_rounded,
          color: AppColors.info,
        ),
        _SummaryTile(
          title: 'Completed',
          value: counts.completed,
          icon: Icons.task_alt_rounded,
          color: AppColors.accent,
        ),
        _SummaryTile(
          title: 'Cancelled',
          value: counts.cancelled,
          icon: Icons.cancel_rounded,
          color: AppColors.error,
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String title;
  final int value;
  final IconData icon;
  final Color color;

  const _SummaryTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$value',
                  style: AppTextStyles.h3.copyWith(fontSize: 19),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  final BookingFilter selected;
  final _BookingCounts counts;
  final ValueChanged<BookingFilter> onChanged;

  const _FilterChips({
    required this.selected,
    required this.counts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: BookingFilter.values.map((filter) {
          final isSelected = selected == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onChanged(filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.2)
                      : Colors.white.withOpacity(0.055),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.accent
                        : Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      filter.label,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: isSelected
                            ? AppColors.accentLight
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(isSelected ? 0.16 : 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${counts.countFor(filter)}',
                        style: AppTextStyles.caption.copyWith(
                          color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final BookingEntity booking;
  final DateTime now;
  final VoidCallback? onCancel;

  const _BookingCard({
    required this.booking,
    required this.now,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final displayStatus = booking.getDisplayStatus(now);
    final statusColor = _statusColor(displayStatus);
    final statusLabel = _statusLabel(displayStatus);
    final timeRange = _formatTimeRange(booking);
    final dateLabel = DateFormat('MMM d, yyyy').format(booking.date);

    return GlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      fillColor: const Color(0xFF12172A).withOpacity(0.72),
      borderColor: statusColor.withOpacity(0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [statusColor.withOpacity(0.28), statusColor.withOpacity(0.08)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(_statusIcon(displayStatus), color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.roomDisplayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.h4.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      booking.roomLocationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _StatusBadge(label: statusLabel, color: statusColor),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoPill(
                icon: Icons.calendar_today_rounded,
                label: dateLabel,
              ),
              _InfoPill(
                icon: Icons.access_time_rounded,
                label: timeRange,
              ),
              _InfoPill(
                icon: Icons.event_seat_rounded,
                label: '${booking.seatsBooked} seat${booking.seatsBooked == 1 ? '' : 's'}',
              ),
              if (booking.purpose?.trim().isNotEmpty == true)
                _InfoPill(
                  icon: Icons.notes_rounded,
                  label: booking.purpose!.trim(),
                ),
              if (booking.seatNumber != null)
                _InfoPill(
                  icon: Icons.confirmation_number_rounded,
                  label: 'Seat #${booking.seatNumber}',
                ),
            ],
          ),
          if (displayStatus == BookingDisplayStatus.completed) ...[
            const SizedBox(height: 14),
            _HintStrip(
              icon: Icons.check_circle_outline_rounded,
              message: 'This booking ended at ${DateFormat('h:mm a').format(booking.bookingEndDateTime)} and is now completed.',
              color: AppColors.accent,
            ),
          ],
          if (displayStatus == BookingDisplayStatus.upcoming) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _HintStrip(
                    icon: Icons.timer_rounded,
                    message: _upcomingMessage(booking, now),
                    color: AppColors.info,
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  onPressed: onCancel,
                  tooltip: 'Cancel booking',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.error.withOpacity(0.13),
                    foregroundColor: AppColors.error,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(BookingDisplayStatus status) {
    switch (status) {
      case BookingDisplayStatus.upcoming:
        return AppColors.info;
      case BookingDisplayStatus.completed:
        return AppColors.accent;
      case BookingDisplayStatus.cancelled:
        return AppColors.error;
    }
  }

  String _statusLabel(BookingDisplayStatus status) {
    switch (status) {
      case BookingDisplayStatus.upcoming:
        return 'Upcoming';
      case BookingDisplayStatus.completed:
        return 'Completed';
      case BookingDisplayStatus.cancelled:
        return 'Cancelled';
    }
  }

  IconData _statusIcon(BookingDisplayStatus status) {
    switch (status) {
      case BookingDisplayStatus.upcoming:
        return Icons.upcoming_rounded;
      case BookingDisplayStatus.completed:
        return Icons.task_alt_rounded;
      case BookingDisplayStatus.cancelled:
        return Icons.event_busy_rounded;
    }
  }

  String _formatTimeRange(BookingEntity booking) {
    final start = booking.bookingStartDateTime;
    final end = booking.bookingEndDateTime;
    return '${DateFormat('h:mm a').format(start)} – ${DateFormat('h:mm a').format(end)}';
  }

  String _upcomingMessage(BookingEntity booking, DateTime now) {
    final start = booking.bookingStartDateTime;
    final end = booking.bookingEndDateTime;
    if (now.isBefore(start)) {
      return 'Starts ${DateFormat('MMM d, h:mm a').format(start)}';
    }
    return 'Running now • ends at ${DateFormat('h:mm a').format(end)}';
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _HintStrip extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;

  const _HintStrip({
    required this.icon,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _CancelBookingSheet extends StatelessWidget {
  final BookingEntity booking;

  const _CancelBookingSheet({required this.booking});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.event_busy_rounded, color: AppColors.error),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Cancel this booking?',
                  style: AppTextStyles.h3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${booking.roomDisplayName}\n${DateFormat('MMM d, yyyy').format(booking.date)} • ${DateFormat('h:mm a').format(booking.bookingStartDateTime)} – ${DateFormat('h:mm a').format(booking.bookingEndDateTime)}',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: BorderSide(color: Colors.white.withOpacity(0.12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Keep Booking'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Cancel Booking'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 42, color: AppColors.primaryLight),
            ),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: AppTextStyles.h3),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 46),
              const SizedBox(height: 12),
              Text('Could not load bookings', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
