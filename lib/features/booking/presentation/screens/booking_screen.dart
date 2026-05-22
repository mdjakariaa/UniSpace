import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:unispace/app/theme/app_colors.dart';
import 'package:unispace/app/theme/app_text_styles.dart';
import 'package:unispace/core/widgets/glass_card.dart';
import 'package:unispace/core/widgets/gradient_button.dart';
import 'package:unispace/features/rooms/presentation/providers/room_provider.dart';
import 'package:unispace/features/booking/presentation/providers/booking_provider.dart';

/// Booking screen — pick date, time slot, and number of seats
class BookingScreen extends ConsumerStatefulWidget {
  final String roomId;
  const BookingScreen({super.key, required this.roomId});

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  DateTime _selectedDate = DateTime.now();
  int _selectedSlotIndex = -1;
  int _seatsToBook = 1;
  bool _isBooking = false;

  final List<Map<String, String>> _timeSlots = List.generate(14, (i) {
    final start = 8 + i;
    final end = start + 1;
    return {
      'start': '${start.toString().padLeft(2, '0')}:00:00',
      'end': '${end.toString().padLeft(2, '0')}:00:00',
      'label': '${start.toString().padLeft(2, '0')}:00 - ${end.toString().padLeft(2, '0')}:00',
    };
  });

  Future<void> _handleBooking() async {
    if (_selectedSlotIndex < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a time slot'), backgroundColor: AppColors.warning),
      );
      return;
    }

    setState(() => _isBooking = true);

    try {
      final slot = _timeSlots[_selectedSlotIndex];
      await ref.read(bookingServiceProvider).bookSeats(
            roomId: widget.roomId,
            seats: _seatsToBook,
            date: _selectedDate,
            startTime: slot['start']!,
            endTime: slot['end']!,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Booking confirmed!'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomAsync = ref.watch(roomByIdProvider(widget.roomId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Book a Seat'),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
      ),
      body: roomAsync.when(
        data: (room) {
          if (room == null) return const Center(child: Text('Room not found'));

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Room info card
                GlassCard(
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.meeting_room_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(room.name, style: AppTextStyles.h4),
                            Text('${room.building} • ${room.availableSeats} seats available',
                                style: AppTextStyles.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn().slideY(begin: 0.1),

                const SizedBox(height: 28),

                // Date picker
                Text('Select Date', style: AppTextStyles.h4),
                const SizedBox(height: 12),
                SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: 7,
                    itemBuilder: (context, index) {
                      final date = DateTime.now().add(Duration(days: index));
                      final isSelected = _selectedDate.day == date.day &&
                          _selectedDate.month == date.month;

                      return GestureDetector(
                        onTap: () => setState(() => _selectedDate = date),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 60,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            gradient: isSelected ? AppColors.primaryGradient : null,
                            color: isSelected ? null : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? Colors.transparent : AppColors.glassBorder,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                DateFormat('EEE').format(date),
                                style: AppTextStyles.caption.copyWith(
                                  color: isSelected ? Colors.white : AppColors.textHint,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${date.day}',
                                style: AppTextStyles.h3.copyWith(
                                  color: isSelected ? Colors.white : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ).animate(delay: 200.ms).fadeIn(),

                const SizedBox(height: 28),

                // Time slots
                Text('Select Time Slot', style: AppTextStyles.h4),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_timeSlots.length, (index) {
                    final slot = _timeSlots[index];
                    final isSelected = index == _selectedSlotIndex;
                    final isPast = _selectedDate.day == DateTime.now().day &&
                        int.parse(slot['start']!.split(':')[0]) <= DateTime.now().hour;

                    return GestureDetector(
                      onTap: isPast ? null : () => setState(() => _selectedSlotIndex = index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: isSelected ? AppColors.primaryGradient : null,
                          color: isPast
                              ? AppColors.surfaceLight.withOpacity(0.5)
                              : isSelected
                                  ? null
                                  : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? Colors.transparent : AppColors.glassBorder,
                          ),
                        ),
                        child: Text(
                          slot['label']!,
                          style: AppTextStyles.labelMedium.copyWith(
                            color: isPast
                                ? AppColors.textHint.withOpacity(0.5)
                                : isSelected
                                    ? Colors.white
                                    : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }),
                ).animate(delay: 300.ms).fadeIn(),

                const SizedBox(height: 28),

                // Seats selector
                Text('Number of Seats', style: AppTextStyles.h4),
                const SizedBox(height: 12),
                GlassCard(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: _seatsToBook > 1
                            ? () => setState(() => _seatsToBook--)
                            : null,
                        icon: Icon(
                          Icons.remove_circle_outline_rounded,
                          color: _seatsToBook > 1 ? AppColors.primary : AppColors.textHint,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Text('$_seatsToBook', style: AppTextStyles.h1),
                      const SizedBox(width: 20),
                      IconButton(
                        onPressed: _seatsToBook < room.availableSeats
                            ? () => setState(() => _seatsToBook++)
                            : null,
                        icon: Icon(
                          Icons.add_circle_outline_rounded,
                          color: _seatsToBook < room.availableSeats
                              ? AppColors.primary
                              : AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ).animate(delay: 400.ms).fadeIn(),

                const SizedBox(height: 36),

                // Confirm button
                GradientButton(
                  text: 'Confirm Booking',
                  isLoading: _isBooking,
                  onPressed: _handleBooking,
                  icon: Icons.check_circle_rounded,
                ).animate(delay: 500.ms).fadeIn().slideY(begin: 0.2),

                const SizedBox(height: 40),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
