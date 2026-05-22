import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:unispace/app/theme/app_colors.dart';
import 'package:unispace/app/theme/app_text_styles.dart';
import 'package:unispace/core/widgets/glass_card.dart';
import 'package:unispace/core/widgets/gradient_button.dart';
import 'package:unispace/features/rooms/presentation/providers/room_provider.dart';

/// Room details screen with seat visualization
class RoomDetailsScreen extends ConsumerWidget {
  final String roomId;
  const RoomDetailsScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomAsync = ref.watch(roomByIdProvider(roomId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: roomAsync.when(
        data: (room) {
          if (room == null) {
            return const Center(child: Text('Room not found'));
          }
          final isAvailable = room.status == 'available';

          return CustomScrollView(
            slivers: [
              // App bar
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                backgroundColor: AppColors.surface,
                leading: IconButton(
                  onPressed: () => context.pop(),
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primary.withOpacity(0.3),
                          AppColors.accent.withOpacity(0.1),
                          AppColors.background,
                        ],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.meeting_room_rounded,
                        size: 80,
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Room name + status
                      Row(
                        children: [
                          Expanded(child: Text(room.name, style: AppTextStyles.h1)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: (isAvailable ? AppColors.success : AppColors.error)
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              isAvailable ? 'Available' : 'Fully Booked',
                              style: AppTextStyles.labelMedium.copyWith(
                                color: isAvailable ? AppColors.success : AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ).animate().fadeIn().slideY(begin: 0.1),

                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textHint),
                          const SizedBox(width: 6),
                          Text(
                            '${room.building} • Floor ${room.floor}',
                            style: AppTextStyles.bodyMedium,
                          ),
                        ],
                      ).animate(delay: 100.ms).fadeIn(),

                      // Rating
                      if (room.rating > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ...List.generate(5, (i) => Icon(
                              i < room.rating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                              size: 18,
                              color: AppColors.warning,
                            )),
                            const SizedBox(width: 8),
                            Text(
                              '${room.rating} (${room.totalRatings} reviews)',
                              style: AppTextStyles.bodySmall,
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 28),

                      // Seat info card
                      GlassCard(
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _SeatInfoTile(
                                  icon: Icons.event_seat_rounded,
                                  label: 'Total Seats',
                                  value: '${room.totalSeats}',
                                  color: AppColors.accent,
                                ),
                                Container(width: 1, height: 40, color: AppColors.glassBorder),
                                _SeatInfoTile(
                                  icon: Icons.check_circle_outline_rounded,
                                  label: 'Available',
                                  value: '${room.availableSeats}',
                                  color: AppColors.success,
                                ),
                                Container(width: 1, height: 40, color: AppColors.glassBorder),
                                _SeatInfoTile(
                                  icon: Icons.block_rounded,
                                  label: 'Occupied',
                                  value: '${room.totalSeats - room.availableSeats}',
                                  color: AppColors.error,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: room.totalSeats > 0
                                    ? (room.totalSeats - room.availableSeats) / room.totalSeats
                                    : 0,
                                backgroundColor: AppColors.glassBorder,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  room.availableSeats == 0 ? AppColors.error : AppColors.primary,
                                ),
                                minHeight: 6,
                              ),
                            ),
                          ],
                        ),
                      ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.1),

                      const SizedBox(height: 20),

                      // Facilities
                      if (room.facilities.isNotEmpty) ...[
                        Text('Facilities', style: AppTextStyles.h4),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: room.facilities.map((f) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.glassBorder),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_getFacilityIcon(f), size: 16, color: AppColors.accent),
                                  const SizedBox(width: 6),
                                  Text(f, style: AppTextStyles.labelMedium),
                                ],
                              ),
                            );
                          }).toList(),
                        ).animate(delay: 300.ms).fadeIn(),
                      ],

                      const SizedBox(height: 36),

                      // Book button
                      GradientButton(
                        text: isAvailable ? 'Book a Seat' : 'No Seats Available',
                        onPressed: isAvailable ? () => context.push('/book/$roomId') : null,
                        icon: Icons.bookmark_add_rounded,
                      ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.2),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  IconData _getFacilityIcon(String facility) {
    final lower = facility.toLowerCase();
    if (lower.contains('wifi')) return Icons.wifi_rounded;
    if (lower.contains('projector')) return Icons.video_camera_back_rounded;
    if (lower.contains('ac') || lower.contains('air')) return Icons.ac_unit_rounded;
    if (lower.contains('whiteboard')) return Icons.dashboard_rounded;
    if (lower.contains('power') || lower.contains('charge')) return Icons.power_rounded;
    return Icons.check_circle_outline_rounded;
  }
}

class _SeatInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SeatInfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 6),
        Text(value, style: AppTextStyles.h3.copyWith(color: color)),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }
}
