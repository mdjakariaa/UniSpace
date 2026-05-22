import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:unispace/app/theme/app_colors.dart';
import 'package:unispace/app/theme/app_text_styles.dart';
import 'package:unispace/core/widgets/glass_card.dart';
import 'package:unispace/features/auth/presentation/providers/auth_provider.dart';
import 'package:unispace/features/rooms/presentation/providers/room_provider.dart';

/// Student home screen — browse rooms, search, quick stats
class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final roomsAsync = ref.watch(roomsProvider);
    final userName = authState.user?.fullName.split(' ').first ?? 'Student';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.8, -0.6),
            radius: 1.8,
            colors: [Color(0xFF1A1040), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello, $userName 👋',
                                style: AppTextStyles.h2,
                              ).animate().fadeIn(duration: 500.ms).slideX(begin: -0.1),
                              const SizedBox(height: 4),
                              Text(
                                'Find your perfect study space',
                                style: AppTextStyles.bodyMedium,
                              ).animate(delay: 200.ms).fadeIn(),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => context.go('/profile'),
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: Text(
                                  userName[0].toUpperCase(),
                                  style: GoogleFonts.outfit(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ).animate().fadeIn(duration: 500.ms).scale(
                                begin: const Offset(0.8, 0.8),
                                curve: Curves.easeOutBack,
                              ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Search bar
                      GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        borderRadius: 16,
                        child: TextField(
                          onChanged: (query) {
                            ref.read(roomSearchQueryProvider.notifier).state = query;
                          },
                          style: AppTextStyles.bodyLarge,
                          decoration: InputDecoration(
                            hintText: 'Search rooms, buildings...',
                            hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
                            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                          ),
                        ),
                      ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.1),
                    ],
                  ),
                ),
              ),

              // Quick stats
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _QuickStatCard(
                          icon: Icons.meeting_room_rounded,
                          label: 'Available',
                          value: roomsAsync.when(
                            data: (rooms) => rooms.where((r) => r.status == 'available').length.toString(),
                            loading: () => '...',
                            error: (_, __) => '0',
                          ),
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickStatCard(
                          icon: Icons.event_seat_rounded,
                          label: 'Total Seats',
                          value: roomsAsync.when(
                            data: (rooms) => rooms.fold<int>(0, (sum, r) => sum + (r.availableSeats)).toString(),
                            loading: () => '...',
                            error: (_, __) => '0',
                          ),
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickStatCard(
                          icon: Icons.bookmark_rounded,
                          label: 'My Bookings',
                          value: '0',
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.1),
                ),
              ),

              // Section header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Available Rooms', style: AppTextStyles.h3),
                      TextButton(
                        onPressed: () {},
                        child: Text(
                          'See All',
                          style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary),
                        ),
                      ),
                    ],
                  ).animate(delay: 500.ms).fadeIn(),
                ),
              ),

              // Room list
              roomsAsync.when(
                data: (rooms) {
                  final searchQuery = ref.watch(roomSearchQueryProvider).toLowerCase();
                  final filtered = searchQuery.isEmpty
                      ? rooms
                      : rooms.where((r) =>
                          r.name.toLowerCase().contains(searchQuery) ||
                          r.building.toLowerCase().contains(searchQuery)).toList();

                  if (filtered.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(48),
                          child: Column(
                            children: [
                              Icon(Icons.search_off_rounded, size: 64, color: AppColors.textHint),
                              const SizedBox(height: 16),
                              Text('No rooms found', style: AppTextStyles.bodyMedium),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final room = filtered[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _RoomCard(room: room)
                                .animate(delay: Duration(milliseconds: 100 * index))
                                .fadeIn()
                                .slideY(begin: 0.1),
                          );
                        },
                        childCount: filtered.length,
                      ),
                    ),
                  );
                },
                loading: () => SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(48),
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  ),
                ),
                error: (error, _) => SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(48),
                      child: Text('Error: $error', style: AppTextStyles.bodyMedium),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _QuickStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 16,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final RoomEntity room;

  const _RoomCard({required this.room});

  @override
  Widget build(BuildContext context) {
    final isAvailable = room.status == 'available';
    final occupancyPercent = room.totalSeats > 0
        ? ((room.totalSeats - room.availableSeats) / room.totalSeats * 100).round()
        : 0;

    return GlassCard(
      onTap: () => context.push('/room/${room.id}'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Room icon
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: isAvailable ? AppColors.primaryGradient : LinearGradient(
                    colors: [Colors.grey.shade700, Colors.grey.shade800],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.meeting_room_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(room.name, style: AppTextStyles.h4),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 14, color: AppColors.textHint),
                        const SizedBox(width: 4),
                        Text(
                          '${room.building} • Floor ${room.floor}',
                          style: AppTextStyles.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (isAvailable ? AppColors.success : AppColors.error).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isAvailable ? 'Available' : 'Full',
                  style: AppTextStyles.caption.copyWith(
                    color: isAvailable ? AppColors.success : AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Seat progress bar
          Row(
            children: [
              Icon(Icons.event_seat_rounded, size: 16, color: AppColors.textHint),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${room.availableSeats} of ${room.totalSeats} seats available',
                          style: AppTextStyles.caption,
                        ),
                        Text(
                          '$occupancyPercent% occupied',
                          style: AppTextStyles.caption.copyWith(
                            color: occupancyPercent > 80
                                ? AppColors.error
                                : occupancyPercent > 50
                                    ? AppColors.warning
                                    : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: room.totalSeats > 0
                            ? (room.totalSeats - room.availableSeats) / room.totalSeats
                            : 0,
                        backgroundColor: AppColors.glassBorder,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          occupancyPercent > 80
                              ? AppColors.error
                              : occupancyPercent > 50
                                  ? AppColors.warning
                                  : AppColors.success,
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Facilities chips
          if (room.facilities.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: room.facilities.take(4).map((facility) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    facility,
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
