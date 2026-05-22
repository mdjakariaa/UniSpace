import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:unispace/app/theme/app_colors.dart';
import 'package:unispace/app/theme/app_text_styles.dart';
import 'package:unispace/core/widgets/glass_card.dart';
import 'package:unispace/features/rooms/presentation/providers/room_provider.dart';

class RoomManagementScreen extends ConsumerStatefulWidget {
  const RoomManagementScreen({super.key});
  @override
  ConsumerState<RoomManagementScreen> createState() => _RoomManagementScreenState();
}

class _RoomManagementScreenState extends ConsumerState<RoomManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(roomsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () => _showAddRoomDialog(),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(-0.3, -0.5), radius: 1.8,
            colors: [Color(0xFF0A1A30), AppColors.background]),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(children: [
                  IconButton(onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.textPrimary, size: 20)),
                  const SizedBox(width: 8),
                  Text('Room Management', style: AppTextStyles.h2),
                ]),
              ).animate().fadeIn().slideX(begin: -0.1),
              const SizedBox(height: 20),
              // Room list
              Expanded(
                child: roomsAsync.when(
                  data: (rooms) {
                    if (rooms.isEmpty) {
                      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.meeting_room_outlined, size: 64, color: AppColors.textHint.withOpacity(0.4)),
                        const SizedBox(height: 16),
                        Text('No rooms yet', style: AppTextStyles.bodyMedium),
                        const SizedBox(height: 8),
                        Text('Tap + to add a room', style: AppTextStyles.caption),
                      ]));
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: rooms.length,
                      itemBuilder: (context, i) {
                        final room = rooms[i];
                        final statusColor = room.status == 'available' ? AppColors.success
                            : room.status == 'fully_booked' ? AppColors.error
                            : room.status == 'pending_approval' ? AppColors.warning
                            : AppColors.textHint;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.accent.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12)),
                                    child: const Icon(Icons.meeting_room_rounded, color: AppColors.accent, size: 24),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(room.name, style: AppTextStyles.labelLarge),
                                      Text('${room.building} • Floor ${room.floor}', style: AppTextStyles.caption),
                                    ],
                                  )),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8)),
                                    child: Text(room.status.replaceAll('_', ' ').toUpperCase(),
                                      style: AppTextStyles.caption.copyWith(color: statusColor, fontWeight: FontWeight.w600, fontSize: 9)),
                                  ),
                                ]),
                                const SizedBox(height: 12),
                                // Seats info
                                Row(children: [
                                  _InfoChip(icon: Icons.event_seat_rounded, label: '${room.availableSeats}/${room.totalSeats} seats'),
                                  const SizedBox(width: 8),
                                  if (room.rating > 0)
                                    _InfoChip(icon: Icons.star_rounded, label: room.rating.toStringAsFixed(1)),
                                  const Spacer(),
                                  // Edit button
                                  IconButton(
                                    onPressed: () => _showEditRoomDialog(room),
                                    icon: const Icon(Icons.edit_rounded, color: AppColors.primary, size: 20),
                                    tooltip: 'Edit',
                                  ),
                                  // Delete button
                                  IconButton(
                                    onPressed: () => _confirmDelete(room.id, room.name),
                                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                                    tooltip: 'Delete',
                                  ),
                                ]),
                                // Facilities
                                if (room.facilities.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(spacing: 6, runSpacing: 6, children: room.facilities.map((f) =>
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceLight,
                                        borderRadius: BorderRadius.circular(6)),
                                      child: Text(f, style: AppTextStyles.caption.copyWith(fontSize: 10)),
                                    )).toList()),
                                ],
                              ],
                            ),
                          ),
                        ).animate(delay: Duration(milliseconds: 80 * i)).fadeIn().slideY(begin: 0.05);
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  error: (e, _) => Center(child: Text('Error: $e')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddRoomDialog() {
    final nameCtrl = TextEditingController();
    final buildingCtrl = TextEditingController();
    final floorCtrl = TextEditingController(text: '1');
    final seatsCtrl = TextEditingController(text: '20');
    final facilitiesCtrl = TextEditingController();

    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Add Room', style: AppTextStyles.h3),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _dialogField(nameCtrl, 'Room Name', Icons.meeting_room_rounded),
        const SizedBox(height: 12),
        _dialogField(buildingCtrl, 'Building', Icons.apartment_rounded),
        const SizedBox(height: 12),
        _dialogField(floorCtrl, 'Floor', Icons.layers_rounded, isNumber: true),
        const SizedBox(height: 12),
        _dialogField(seatsCtrl, 'Total Seats', Icons.event_seat_rounded, isNumber: true),
        const SizedBox(height: 12),
        _dialogField(facilitiesCtrl, 'Facilities (comma separated)', Icons.wifi_rounded),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () {
            if (nameCtrl.text.isEmpty || buildingCtrl.text.isEmpty) return;
            final facilities = facilitiesCtrl.text.isNotEmpty
                ? facilitiesCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
                : <String>[];
            ref.read(roomServiceProvider).addRoom(
              name: nameCtrl.text.trim(),
              building: buildingCtrl.text.trim(),
              floor: int.tryParse(floorCtrl.text) ?? 1,
              totalSeats: int.tryParse(seatsCtrl.text) ?? 20,
              facilities: facilities,
            );
            Navigator.pop(ctx);
          },
          child: const Text('Add'),
        ),
      ],
    ));
  }

  void _showEditRoomDialog(RoomEntity room) {
    final nameCtrl = TextEditingController(text: room.name);
    final buildingCtrl = TextEditingController(text: room.building);
    final floorCtrl = TextEditingController(text: room.floor.toString());
    final seatsCtrl = TextEditingController(text: room.totalSeats.toString());
    final facilitiesCtrl = TextEditingController(text: room.facilities.join(', '));

    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Edit Room', style: AppTextStyles.h3),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _dialogField(nameCtrl, 'Room Name', Icons.meeting_room_rounded),
        const SizedBox(height: 12),
        _dialogField(buildingCtrl, 'Building', Icons.apartment_rounded),
        const SizedBox(height: 12),
        _dialogField(floorCtrl, 'Floor', Icons.layers_rounded, isNumber: true),
        const SizedBox(height: 12),
        _dialogField(seatsCtrl, 'Total Seats', Icons.event_seat_rounded, isNumber: true),
        const SizedBox(height: 12),
        _dialogField(facilitiesCtrl, 'Facilities (comma separated)', Icons.wifi_rounded),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () {
            final newTotal = int.tryParse(seatsCtrl.text) ?? room.totalSeats;
            final seatDiff = newTotal - room.totalSeats;
            final facilities = facilitiesCtrl.text.isNotEmpty
                ? facilitiesCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
                : <String>[];
            ref.read(roomServiceProvider).updateRoom(room.id, {
              'name': nameCtrl.text.trim(),
              'building': buildingCtrl.text.trim(),
              'floor': int.tryParse(floorCtrl.text) ?? room.floor,
              'total_seats': newTotal,
              'available_seats': (room.availableSeats + seatDiff).clamp(0, newTotal),
              'facilities': facilities,
            });
            Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ],
    ));
  }

  Widget _dialogField(TextEditingController ctrl, String hint, IconData icon, {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint, prefixIcon: Icon(icon, size: 20, color: AppColors.textHint),
        filled: true, fillColor: AppColors.surfaceLight,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  void _confirmDelete(String roomId, String name) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Delete Room', style: AppTextStyles.h3),
      content: Text('Delete "$name"? This cannot be undone.', style: AppTextStyles.bodyMedium),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary))),
        TextButton(onPressed: () { Navigator.pop(ctx); ref.read(roomServiceProvider).deleteRoom(roomId); },
          child: Text('Delete', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error))),
      ],
    ));
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(label, style: AppTextStyles.caption),
      ]),
    );
  }
}
