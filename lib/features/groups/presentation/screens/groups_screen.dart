import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:unispace/app/theme/app_colors.dart';
import 'package:unispace/app/theme/app_text_styles.dart';
import 'package:unispace/features/groups/presentation/providers/group_provider.dart';
import 'package:unispace/features/rooms/domain/entities/room.dart';
import 'package:unispace/features/rooms/presentation/providers/room_provider.dart';

/// Groups screen — public study group discovery, join requests, admin approval, edit/delete, and member management.
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(allStudyGroupsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.35, -0.9),
            radius: 1.55,
            colors: [Color(0xFF102040), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Study Groups', style: AppTextStyles.h1).animate().fadeIn().slideX(begin: -0.08),
                          const SizedBox(height: 6),
                          Text(
                            'Create groups, request to join, and manage members with live slot checks.',
                            style: AppTextStyles.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.28),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: IconButton(
                        tooltip: 'Create Study Group',
                        onPressed: () => _showCreateGroupDialog(context),
                        icon: const Icon(Icons.add_rounded, color: Colors.white),
                      ),
                    ).animate().fadeIn().scale(begin: const Offset(0.85, 0.85), curve: Curves.easeOutBack),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: groupsAsync.when(
                  loading: () => const _GroupsLoadingState(),
                  error: (error, _) => _GroupsErrorState(
                    message: _friendlyError(error),
                    onRetry: () => ref.invalidate(allStudyGroupsProvider),
                  ),
                  data: (groups) {
                    if (groups.isEmpty) return _EmptyGroupsState(onCreate: () => _showCreateGroupDialog(context));
                    return RefreshIndicator(
                      backgroundColor: AppColors.surface,
                      color: AppColors.accent,
                      onRefresh: () async => ref.invalidate(allStudyGroupsProvider),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 110),
                        itemCount: groups.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, index) => _StudyGroupCard(
                          group: groups[index],
                          onRequestJoin: () => _showJoinRequestDialog(context, groups[index]),
                          onViewMembers: () => _showMembersSheet(context, groups[index]),
                          onManageRequests: () => _showJoinRequestsSheet(context, groups[index]),
                          onEdit: () => _showEditGroupDialog(context, groups[index]),
                          onDelete: () => _confirmDeleteGroup(context, ref, groups[index]),
                        ).animate(delay: (60 * index).ms).fadeIn().slideY(begin: 0.08),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateGroupDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreateGroupDialog(),
    );
  }

  void _showEditGroupDialog(BuildContext context, StudyGroupEntity group) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditGroupDialog(group: group),
    );
  }

  void _showJoinRequestDialog(BuildContext context, StudyGroupEntity group) {
    showDialog(context: context, builder: (_) => _JoinRequestDialog(group: group));
  }

  void _showMembersSheet(BuildContext context, StudyGroupEntity group) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MembersBottomSheet(group: group),
    );
  }

  void _showJoinRequestsSheet(BuildContext context, StudyGroupEntity group) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JoinRequestsBottomSheet(group: group),
    );
  }

  Future<void> _confirmDeleteGroup(BuildContext context, WidgetRef ref, StudyGroupEntity group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Delete Study Group?', style: AppTextStyles.h3),
        content: Text(
          'This will remove "${group.name}" from active groups, reject pending requests, and notify approved members.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_rounded),
            label: const Text('Delete Group'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(groupServiceProvider).deleteStudyGroup(group.id);
      ref.invalidate(allStudyGroupsProvider);
      if (context.mounted) _showSnack(context, 'Study group removed successfully.');
    } catch (error) {
      if (context.mounted) _showSnack(context, _friendlyError(error), isError: true);
    }
  }
}

class _StudyGroupCard extends ConsumerWidget {
  final StudyGroupEntity group;
  final VoidCallback onRequestJoin;
  final VoidCallback onViewMembers;
  final VoidCallback onManageRequests;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _StudyGroupCard({
    required this.group,
    required this.onRequestJoin,
    required this.onViewMembers,
    required this.onManageRequests,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(currentUserGroupStatusProvider(group.id));
    final dateText = group.date == null ? 'No date selected' : DateFormat('dd MMM yyyy').format(group.date!);
    final timeText = group.timeSlot ?? 'No time slot selected';
    final open = !group.isFull && group.status == 'active';

    return Container(
      decoration: _cardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(15)),
                  child: const Icon(Icons.groups_2_rounded, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.name, style: AppTextStyles.h4),
                      const SizedBox(height: 5),
                      Text(
                        (group.description?.trim().isNotEmpty ?? false) ? group.description!.trim() : 'No description added.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                _StatusPill(
                  label: open ? 'Open' : 'Full',
                  color: open ? AppColors.success : AppColors.warning,
                  icon: open ? Icons.check_circle_rounded : Icons.lock_clock_rounded,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(icon: Icons.event_rounded, label: dateText),
                _InfoChip(icon: Icons.schedule_rounded, label: timeText),
                _InfoChip(icon: Icons.person_rounded, label: 'Admin: ${group.creatorName ?? 'Group Creator'}'),
                if (group.roomName != null) _InfoChip(icon: Icons.meeting_room_rounded, label: group.roomName!),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Members', style: AppTextStyles.labelMedium),
                          Text('${group.memberCount}/${group.maxMembers}', style: AppTextStyles.labelMedium.copyWith(color: AppColors.accent)),
                        ],
                      ),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          minHeight: 7,
                          value: group.maxMembers == 0 ? 0 : (group.memberCount / group.maxMembers).clamp(0.0, 1.0),
                          backgroundColor: AppColors.surfaceLight,
                          valueColor: AlwaysStoppedAnimation<Color>(open ? AppColors.accent : AppColors.warning),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: onViewMembers,
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text('Members'),
                  style: _outlineButtonStyle(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            statusAsync.when(
              loading: () => const SizedBox(
                height: 44,
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
              ),
              error: (_, __) => _GroupActionButton(
                label: 'Refresh Status',
                icon: Icons.refresh_rounded,
                onPressed: () => ref.invalidate(currentUserGroupStatusProvider(group.id)),
              ),
              data: (status) {
                if (status == GroupUserStatus.admin) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _GroupActionButton(label: 'Join Requests', icon: Icons.pending_actions_rounded, onPressed: onManageRequests)),
                          const SizedBox(width: 10),
                          Expanded(child: _GroupActionButton(label: 'View Members', icon: Icons.groups_rounded, onPressed: onViewMembers, secondary: true)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _GroupActionButton(label: 'Edit Group', icon: Icons.edit_calendar_rounded, onPressed: onEdit, secondary: true)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onDelete,
                              icon: const Icon(Icons.delete_outline_rounded, size: 18),
                              label: const Text('Delete Group'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.error,
                                side: BorderSide(color: AppColors.error.withOpacity(0.5)),
                                minimumSize: const Size(0, 44),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }
                if (status == GroupUserStatus.member) {
                  return _GroupActionButton(label: 'View Member List', icon: Icons.groups_rounded, onPressed: onViewMembers, secondary: true);
                }
                if (status == GroupUserStatus.pending) {
                  return const _DisabledBadge(label: 'Request Pending', icon: Icons.hourglass_top_rounded, color: AppColors.warning);
                }
                if (!open) return const _DisabledBadge(label: 'Group Full', icon: Icons.lock_rounded, color: AppColors.warning);
                return _GroupActionButton(label: 'Request to Join', icon: Icons.person_add_alt_1_rounded, onPressed: onRequestJoin);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateGroupDialog extends ConsumerStatefulWidget {
  const _CreateGroupDialog();

  @override
  ConsumerState<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends ConsumerState<_CreateGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _maxMembersController = TextEditingController(text: '10');

  DateTime _selectedDate = DateTime.now();
  StudyTimeSlot _selectedSlot = fixedStudyTimeSlots.first;
  String _selectedRoomId = '';
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _maxMembersController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GroupFormDialog(
      title: 'Create Study Group',
      submitLabel: 'Create',
      savingLabel: 'Creating...',
      formKey: _formKey,
      nameController: _nameController,
      descriptionController: _descriptionController,
      maxMembersController: _maxMembersController,
      selectedDate: _selectedDate,
      selectedSlot: _selectedSlot,
      selectedRoomId: _selectedRoomId,
      saving: _saving,
      onPickDate: _pickDate,
      onSlotChanged: (slot) => setState(() => _selectedSlot = slot),
      onRoomChanged: (roomId) => setState(() => _selectedRoomId = roomId),
      onSubmit: _createGroup,
    );
  }

  Future<void> _pickDate() async {
    final picked = await _showUniSpaceDatePicker(context, _selectedDate);
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await ref.read(groupServiceProvider).createGroup(
            name: _nameController.text.trim(),
            description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
            date: _selectedDate,
            startTime: _selectedSlot.startTime,
            endTime: _selectedSlot.endTime,
            maxMembers: int.parse(_maxMembersController.text.trim()),
            roomId: _selectedRoomId.isEmpty ? null : _selectedRoomId,
          );
      ref.invalidate(allStudyGroupsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      _showSnack(context, 'Study group created. You are the group admin.');
    } catch (error) {
      if (!mounted) return;
      _showSnack(context, _friendlyError(error), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _EditGroupDialog extends ConsumerStatefulWidget {
  final StudyGroupEntity group;
  const _EditGroupDialog({required this.group});

  @override
  ConsumerState<_EditGroupDialog> createState() => _EditGroupDialogState();
}

class _EditGroupDialogState extends ConsumerState<_EditGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _maxMembersController;
  late DateTime _selectedDate;
  late StudyTimeSlot _selectedSlot;
  late String _selectedRoomId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.name);
    _descriptionController = TextEditingController(text: widget.group.description ?? '');
    _maxMembersController = TextEditingController(text: widget.group.maxMembers.toString());
    _selectedDate = widget.group.date ?? DateTime.now();
    _selectedSlot = _slotFromGroup(widget.group) ?? fixedStudyTimeSlots.first;
    _selectedRoomId = widget.group.roomId ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _maxMembersController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GroupFormDialog(
      title: 'Edit Study Group',
      submitLabel: 'Save Changes',
      savingLabel: 'Saving...',
      formKey: _formKey,
      nameController: _nameController,
      descriptionController: _descriptionController,
      maxMembersController: _maxMembersController,
      selectedDate: _selectedDate,
      selectedSlot: _selectedSlot,
      selectedRoomId: _selectedRoomId,
      saving: _saving,
      currentMemberCount: widget.group.memberCount,
      onPickDate: _pickDate,
      onSlotChanged: (slot) => setState(() => _selectedSlot = slot),
      onRoomChanged: (roomId) => setState(() => _selectedRoomId = roomId),
      onSubmit: _updateGroup,
    );
  }

  Future<void> _pickDate() async {
    final picked = await _showUniSpaceDatePicker(context, _selectedDate);
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _updateGroup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await ref.read(groupServiceProvider).updateStudyGroup(
            groupId: widget.group.id,
            name: _nameController.text.trim(),
            description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
            date: _selectedDate,
            startTime: _selectedSlot.startTime,
            endTime: _selectedSlot.endTime,
            maxMembers: int.parse(_maxMembersController.text.trim()),
            roomId: _selectedRoomId.isEmpty ? null : _selectedRoomId,
          );
      ref.invalidate(allStudyGroupsProvider);
      ref.invalidate(groupMembersProvider(widget.group.id));
      if (!mounted) return;
      Navigator.pop(context);
      _showSnack(context, 'Study group updated successfully.');
    } catch (error) {
      if (!mounted) return;
      _showSnack(context, _friendlyError(error), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _GroupFormDialog extends ConsumerWidget {
  final String title;
  final String submitLabel;
  final String savingLabel;
  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController maxMembersController;
  final DateTime selectedDate;
  final StudyTimeSlot selectedSlot;
  final String selectedRoomId;
  final bool saving;
  final int currentMemberCount;
  final VoidCallback onPickDate;
  final ValueChanged<StudyTimeSlot> onSlotChanged;
  final ValueChanged<String> onRoomChanged;
  final VoidCallback onSubmit;

  const _GroupFormDialog({
    required this.title,
    required this.submitLabel,
    required this.savingLabel,
    required this.formKey,
    required this.nameController,
    required this.descriptionController,
    required this.maxMembersController,
    required this.selectedDate,
    required this.selectedSlot,
    required this.selectedRoomId,
    required this.saving,
    required this.onPickDate,
    required this.onSlotChanged,
    required this.onRoomChanged,
    required this.onSubmit,
    this.currentMemberCount = 2,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsAsync = ref.watch(roomsProvider);

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.groups_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: AppTextStyles.h3)),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  style: AppTextStyles.bodyLarge,
                  decoration: _inputDecoration('Group name', Icons.group_rounded),
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Enter group name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descriptionController,
                  style: AppTextStyles.bodyLarge,
                  maxLines: 2,
                  decoration: _inputDecoration('Description', Icons.description_rounded),
                ),
                const SizedBox(height: 12),
                roomsAsync.when(
                  loading: () => InputDecorator(
                    decoration: _inputDecoration('Room', Icons.meeting_room_rounded),
                    child: Text('Loading rooms...', style: AppTextStyles.bodyMedium),
                  ),
                  error: (_, __) => InputDecorator(
                    decoration: _inputDecoration('Room', Icons.meeting_room_rounded),
                    child: Text('Room list unavailable.', style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning)),
                  ),
                  data: (rooms) => DropdownButtonFormField<String>(
                    value: selectedRoomId,
                    dropdownColor: AppColors.surfaceLight,
                    decoration: _inputDecoration('Room', Icons.meeting_room_rounded),
                    items: [
                      DropdownMenuItem(value: '', child: Text('No room selected', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary))),
                      ...rooms.map((RoomEntity room) => DropdownMenuItem(
                            value: room.id,
                            child: Text('${room.name} • ${room.building} F${room.floor}', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary)),
                          )),
                    ],
                    onChanged: saving ? null : (value) => onRoomChanged(value ?? ''),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: saving ? null : onPickDate,
                  child: InputDecorator(
                    decoration: _inputDecoration('Date', Icons.event_rounded),
                    child: Text(DateFormat('dd MMM yyyy').format(selectedDate), style: AppTextStyles.bodyLarge),
                  ),
                ),
                const SizedBox(height: 14),
                _SlotAvailabilitySelector(
                  roomId: selectedRoomId,
                  date: selectedDate,
                  selectedSlot: selectedSlot,
                  onChanged: saving ? null : onSlotChanged,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: maxMembersController,
                  keyboardType: TextInputType.number,
                  style: AppTextStyles.bodyLarge,
                  decoration: _inputDecoration('Maximum members', Icons.people_alt_rounded),
                  validator: (value) {
                    final count = int.tryParse(value ?? '');
                    if (count == null || count < 2) return 'Minimum 2 members required';
                    if (count < currentMemberCount) return 'Cannot be less than current members ($currentMemberCount)';
                    if (count > 100) return 'Maximum 100 members allowed';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton.icon(
          onPressed: saving ? null : onSubmit,
          icon: saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_rounded),
          label: Text(saving ? savingLabel : submitLabel),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}

class _SlotAvailabilitySelector extends ConsumerWidget {
  final String roomId;
  final DateTime date;
  final StudyTimeSlot selectedSlot;
  final ValueChanged<StudyTimeSlot>? onChanged;

  const _SlotAvailabilitySelector({
    required this.roomId,
    required this.date,
    required this.selectedSlot,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availabilityAsync = roomId.isEmpty
        ? const AsyncValue<List<RoomSlotAvailabilityEntity>>.data(<RoomSlotAvailabilityEntity>[])
        : ref.watch(groupRoomSlotAvailabilityProvider(RoomSlotAvailabilityQuery(roomId: roomId, date: date)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.schedule_rounded, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Text('Time slot availability', style: AppTextStyles.labelLarge),
          ],
        ),
        const SizedBox(height: 8),
        if (roomId.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: _softDecoration(),
            child: Text('Select a room and date to check teacher/admin blocked slots.', style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning)),
          ),
        const SizedBox(height: 8),
        availabilityAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(14),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (error, _) => Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: _softDecoration(),
            child: Text(_friendlyError(error), style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
          ),
          data: (availability) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: fixedStudyTimeSlots.map((slot) {
              final slotAvailability = availabilityForSlot(availability, slot);
              final blocked = slotAvailability?.isTeacherBlocked ?? false;
              final full = slotAvailability?.isFullyBooked ?? false;
              final selectable = onChanged != null && !blocked && !full;
              final selected = slot.label == selectedSlot.label;
              final color = blocked ? AppColors.error : full ? AppColors.warning : selected ? AppColors.primary : AppColors.accent;
              final status = slotAvailability?.statusLabel ?? (roomId.isEmpty ? 'Not checked' : 'Available');

              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: selectable ? () => onChanged!(slot) : null,
                child: Container(
                  width: 210,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(blocked ? 0.18 : selected ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withOpacity(blocked || selected ? 0.7 : 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(slot.label, style: AppTextStyles.labelMedium.copyWith(color: AppColors.textPrimary))),
                          if (selected) const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
                          if (blocked) const Icon(Icons.block_rounded, size: 16, color: AppColors.error),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption.copyWith(color: color)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _JoinRequestDialog extends ConsumerStatefulWidget {
  final StudyGroupEntity group;
  const _JoinRequestDialog({required this.group});

  @override
  ConsumerState<_JoinRequestDialog> createState() => _JoinRequestDialogState();
}

class _JoinRequestDialogState extends ConsumerState<_JoinRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _batchController = TextEditingController();
  final _departmentController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _batchController.dispose();
    _departmentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('Request to Join', style: AppTextStyles.h3),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.group.name, style: AppTextStyles.labelLarge.copyWith(color: AppColors.accent)),
                const SizedBox(height: 14),
                TextFormField(controller: _nameController, style: AppTextStyles.bodyLarge, decoration: _inputDecoration('Name', Icons.person_rounded), validator: _required),
                const SizedBox(height: 12),
                TextFormField(controller: _contactController, keyboardType: TextInputType.phone, style: AppTextStyles.bodyLarge, decoration: _inputDecoration('Contact Number', Icons.phone_rounded), validator: _required),
                const SizedBox(height: 12),
                TextFormField(controller: _batchController, style: AppTextStyles.bodyLarge, decoration: _inputDecoration('Batch', Icons.badge_rounded), validator: _required),
                const SizedBox(height: 12),
                TextFormField(controller: _departmentController, style: AppTextStyles.bodyLarge, decoration: _inputDecoration('Department', Icons.school_rounded), validator: _required),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded),
          label: Text(_saving ? 'Sending...' : 'Send Request'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ],
    );
  }

  String? _required(String? value) => (value == null || value.trim().isEmpty) ? 'Required' : null;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await ref.read(groupServiceProvider).requestToJoinGroup(
            groupId: widget.group.id,
            name: _nameController.text.trim(),
            contactNumber: _contactController.text.trim(),
            batch: _batchController.text.trim(),
            department: _departmentController.text.trim(),
          );
      ref.invalidate(currentUserGroupStatusProvider(widget.group.id));
      if (!mounted) return;
      Navigator.pop(context);
      _showSnack(context, 'Join request sent to group admin.');
    } catch (error) {
      if (!mounted) return;
      _showSnack(context, _friendlyError(error), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _MembersBottomSheet extends ConsumerWidget {
  final StudyGroupEntity group;
  const _MembersBottomSheet({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider(group.id));
    final currentStatus = ref.watch(currentUserGroupStatusProvider(group.id)).valueOrNull;
    final canManage = currentStatus == GroupUserStatus.admin;

    return _SheetShell(
      title: 'Group Members',
      subtitle: '${group.name} • ${group.memberCount}/${group.maxMembers} joined',
      child: membersAsync.when(
        loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        error: (error, _) => _InlineError(message: _friendlyError(error), onRetry: () => ref.invalidate(groupMembersProvider(group.id))),
        data: (members) {
          if (members.isEmpty) return const _InlineEmpty(message: 'No members found yet.');
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: members.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final member = members[index];
              final canRemove = canManage && !member.isAdmin;
              return _MemberTile(
                member: member,
                trailing: canRemove
                    ? TextButton.icon(
                        onPressed: () => _removeMember(context, ref, member),
                        icon: const Icon(Icons.person_remove_rounded, size: 17),
                        label: const Text('Remove'),
                        style: TextButton.styleFrom(foregroundColor: AppColors.error),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _removeMember(BuildContext context, WidgetRef ref, GroupMemberEntity member) async {
    try {
      await ref.read(groupServiceProvider).removeGroupMember(groupId: group.id, memberUserId: member.userId);
      ref.invalidate(groupMembersProvider(group.id));
      ref.invalidate(allStudyGroupsProvider);
      if (context.mounted) _showSnack(context, '${member.name} removed from the group.');
    } catch (error) {
      if (context.mounted) _showSnack(context, _friendlyError(error), isError: true);
    }
  }
}

class _JoinRequestsBottomSheet extends ConsumerWidget {
  final StudyGroupEntity group;
  const _JoinRequestsBottomSheet({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(groupJoinRequestsProvider(group.id));

    return _SheetShell(
      title: 'Join Requests',
      subtitle: group.name,
      child: requestsAsync.when(
        loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        error: (error, _) => _InlineError(message: _friendlyError(error), onRetry: () => ref.invalidate(groupJoinRequestsProvider(group.id))),
        data: (requests) {
          final pending = requests.where((request) => request.status == 'pending').toList();
          if (pending.isEmpty) return const _InlineEmpty(message: 'No pending join requests.');
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pending.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _JoinRequestTile(
              request: pending[index],
              onApprove: () => _approve(context, ref, pending[index]),
              onReject: () => _reject(context, ref, pending[index]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref, GroupJoinRequestEntity request) async {
    try {
      await ref.read(groupServiceProvider).approveJoinRequest(request.id);
      ref.invalidate(groupJoinRequestsProvider(group.id));
      ref.invalidate(groupMembersProvider(group.id));
      ref.invalidate(allStudyGroupsProvider);
      if (context.mounted) _showSnack(context, '${request.name} approved.');
    } catch (error) {
      if (context.mounted) _showSnack(context, _friendlyError(error), isError: true);
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref, GroupJoinRequestEntity request) async {
    try {
      await ref.read(groupServiceProvider).rejectJoinRequest(request.id);
      ref.invalidate(groupJoinRequestsProvider(group.id));
      if (context.mounted) _showSnack(context, '${request.name} rejected.');
    } catch (error) {
      if (context.mounted) _showSnack(context, _friendlyError(error), isError: true);
    }
  }
}

class _SheetShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SheetShell({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: AppColors.textHint.withOpacity(0.45), borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 18),
              Text(title, style: AppTextStyles.h3),
              const SizedBox(height: 4),
              Text(subtitle, style: AppTextStyles.bodyMedium),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final GroupMemberEntity member;
  final Widget? trailing;

  const _MemberTile({required this.member, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _softDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: member.isAdmin ? AppColors.primary : AppColors.surfaceLight,
            child: Text(_initials(member.name), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(member.name, style: AppTextStyles.labelLarge)),
                    _StatusPill(label: member.isAdmin ? 'Admin' : 'Member', color: member.isAdmin ? AppColors.primary : AppColors.accent, icon: member.isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Contact: ${member.contactNumber}', style: AppTextStyles.bodySmall),
                Text('Batch: ${member.batch}', style: AppTextStyles.bodySmall),
                Text('Department: ${member.department}', style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _JoinRequestTile extends StatelessWidget {
  final GroupJoinRequestEntity request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _JoinRequestTile({required this.request, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _softDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 22, backgroundColor: AppColors.surfaceLight, child: Text(_initials(request.name), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.name, style: AppTextStyles.labelLarge),
                    Text(DateFormat('dd MMM yyyy, h:mm a').format(request.requestedAt), style: AppTextStyles.caption),
                  ],
                ),
              ),
              const _StatusPill(label: 'Pending', color: AppColors.warning, icon: Icons.hourglass_top_rounded),
            ],
          ),
          const SizedBox(height: 12),
          Text('Contact: ${request.contactNumber}', style: AppTextStyles.bodySmall),
          Text('Batch: ${request.batch}', style: AppTextStyles.bodySmall),
          Text('Department: ${request.department}', style: AppTextStyles.bodySmall),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success.withOpacity(0.18), foregroundColor: AppColors.success, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Reject'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.error.withOpacity(0.14), foregroundColor: AppColors.error, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: AppColors.surfaceLight.withOpacity(0.78), borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.glassBorder)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.accent),
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusPill({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(99), border: Border.all(color: color.withOpacity(0.28))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _GroupActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool secondary;

  const _GroupActionButton({required this.label, required this.icon, required this.onPressed, this.secondary = false});

  @override
  Widget build(BuildContext context) {
    if (secondary) {
      return OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label), style: _outlineButtonStyle());
    }
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    );
  }
}

class _DisabledBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _DisabledBadge({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.25))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(label, style: AppTextStyles.labelLarge.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _GroupsLoadingState extends StatelessWidget {
  const _GroupsLoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 110),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, __) => Container(
        height: 220,
        decoration: BoxDecoration(color: AppColors.surface.withOpacity(0.72), borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.glassBorder)),
      ).animate(onPlay: (controller) => controller.repeat(reverse: true)).fade(begin: 0.45, end: 0.9, duration: 900.ms),
    );
  }
}

class _EmptyGroupsState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyGroupsState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_rounded, size: 76, color: AppColors.textHint.withOpacity(0.55)),
            const SizedBox(height: 16),
            Text('No study groups yet', style: AppTextStyles.h4),
            const SizedBox(height: 8),
            Text('Create the first date and time-slot based study group.', textAlign: TextAlign.center, style: AppTextStyles.bodyMedium),
            const SizedBox(height: 18),
            ElevatedButton.icon(onPressed: onCreate, icon: const Icon(Icons.add_rounded), label: const Text('Create Group'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _GroupsErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _GroupsErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 64, color: AppColors.error),
            const SizedBox(height: 14),
            Text('Could not load study groups', style: AppTextStyles.h4),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: AppTextStyles.bodyMedium),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  final String message;
  const _InlineEmpty({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 34), child: Center(child: Text(message, style: AppTextStyles.bodyMedium)));
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _InlineError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
          const SizedBox(height: 8),
          TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
        ],
      ),
    );
  }
}

Future<DateTime?> _showUniSpaceDatePicker(BuildContext context, DateTime selectedDate) {
  return showDatePicker(
    context: context,
    initialDate: selectedDate,
    firstDate: DateTime.now(),
    lastDate: DateTime.now().add(const Duration(days: 365)),
    builder: (context, child) => Theme(
      data: Theme.of(context).copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.primary, surface: AppColors.surface)),
      child: child!,
    ),
  );
}

StudyTimeSlot? _slotFromGroup(StudyGroupEntity group) {
  for (final slot in fixedStudyTimeSlots) {
    if (_normalTime(slot.startTime) == _normalTime(group.startTime ?? '') && _normalTime(slot.endTime) == _normalTime(group.endTime ?? '')) {
      return slot;
    }
    if (slot.label == group.timeSlot) return slot;
  }
  return null;
}

String _normalTime(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return value;
  return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}:00';
}

InputDecoration _inputDecoration(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: AppColors.accent),
    filled: true,
    fillColor: AppColors.surfaceLight.withOpacity(0.72),
    labelStyle: AppTextStyles.bodySmall,
    hintStyle: AppTextStyles.bodySmall,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.glassBorder)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.accent)),
  );
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: AppColors.surface.withOpacity(0.88),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: AppColors.glassBorder),
    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 18, offset: const Offset(0, 10))],
  );
}

BoxDecoration _softDecoration() {
  return BoxDecoration(color: AppColors.surfaceLight.withOpacity(0.55), borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.glassBorder));
}

ButtonStyle _outlineButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: AppColors.accent,
    side: BorderSide(color: AppColors.accent.withOpacity(0.42)),
    minimumSize: const Size(0, 44),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );
}

void _showSnack(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: isError ? AppColors.error : AppColors.success, behavior: SnackBarBehavior.floating),
  );
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return 'U';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
}

String _friendlyError(Object error) {
  final raw = error.toString();
  if (raw.contains('duplicate') || raw.contains('already sent')) return 'You already have a pending request for this group.';
  if (raw.contains('already a member')) return 'You are already a member of this group.';
  if (raw.contains('full')) return 'This group is already full.';
  if (raw.contains('blocked')) return 'This slot is blocked by teacher/admin booking. Please choose another slot.';
  if (raw.contains('Maximum members')) return raw.replaceFirst('Exception: ', '');
  if (raw.contains('permission') || raw.contains('not group admin') || raw.contains('Only the group admin')) return 'You do not have permission to do this action.';
  return raw.replaceFirst('Exception: ', '');
}
