import 'package:table_calendar/table_calendar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/auth_provider.dart';
import '../models/slot.dart';
import 'profile_screen.dart';

// 発起人ダイアログの返却値
class _InitiatorSettings {
  final int minVendors;
  final int maxVendors;
  final String? startTime;
  final String? endTime;
  final String? description;
  final String? name; // 管理者発起人フローのみ
  const _InitiatorSettings({
    required this.minVendors,
    required this.maxVendors,
    this.startTime,
    this.endTime,
    this.description,
    this.name,
  });
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<Slot> _slots = [];
  String _filter = 'all';
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await apiClient.getSlots();
      setState(() {
        _slots =
            data.map((e) => Slot.fromJson(e as Map<String, dynamic>)).toList();
        _isLoading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    }
  }

  List<Slot> _filteredSlots(String? myUserId) {
    if (_filter == 'all') return _slots;
    if (_filter == 'joined') {
      return _slots
          .where((s) => s.vendors.any((v) => v.userId == myUserId))
          .toList();
    }
    return _slots.where((s) => s.status == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('出店カレンダー'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadSlots),
        ],
      ),
      floatingActionButton: auth.isAdmin
          ? FloatingActionButton(
              onPressed: () => _showAddSlotDialog(context),
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          _FilterChips(
            current: _filter,
            onChanged: (value) => setState(() => _filter = value),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _loadSlots, child: const Text('再読み込み')),
          ],
        ),
      );
    }

    final myUserId = context.read<AuthProvider>().user?.id;
    final filtered = _filteredSlots(myUserId);

    if (filtered.isEmpty) {
      return const Center(child: Text('出店可能な日程はまだありません'));
    }
    return RefreshIndicator(
      onRefresh: _loadSlots,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length,
        itemBuilder: (context, index) =>
            _SlotCard(slot: filtered[index], onReserved: _loadSlots, onDeleted: _loadSlots),
      ),
    );
  }

  String _fmt2(int n) => n.toString().padLeft(2, '0');
  String _fmtTime(TimeOfDay t) => '${_fmt2(t.hour)}:${_fmt2(t.minute)}';

  Future<void> _showAddSlotDialog(BuildContext context) async {
    final existingDates = _slots.map((s) => s.date).toSet();
    final selectedDays = <DateTime>{};
    DateTime focusedDay = DateTime.now();
    bool asInitiator = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('出店可能日を追加'),
          contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TableCalendar(
                  firstDay: DateTime.now(),
                  lastDay: DateTime.now().add(const Duration(days: 365)),
                  focusedDay: focusedDay,
                  calendarFormat: CalendarFormat.month,
                  locale: 'ja_JP',
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                  ),
                  onDaySelected: (selectedDay, newFocusedDay) {
                    final dateStr =
                        '${selectedDay.year}-${selectedDay.month.toString().padLeft(2, '0')}-${selectedDay.day.toString().padLeft(2, '0')}';
                    if (existingDates.contains(dateStr)) return;
                    setDialogState(() {
                      focusedDay = newFocusedDay;
                      if (selectedDays.contains(selectedDay)) {
                        selectedDays.remove(selectedDay);
                      } else {
                        selectedDays.add(selectedDay);
                      }
                    });
                  },
                  selectedDayPredicate: (day) => selectedDays.any(
                    (d) =>
                        d.year == day.year &&
                        d.month == day.month &&
                        d.day == day.day,
                  ),
                  calendarBuilders: CalendarBuilders(
                    defaultBuilder: (ctx, day, focusedDay) {
                      final dateStr =
                          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                      if (existingDates.contains(dateStr)) {
                        return Center(
                          child: Text('${day.day}',
                              style: const TextStyle(color: Colors.grey)),
                        );
                      }
                      return null;
                    },
                  ),
                  onPageChanged: (newFocusedDay) {
                    setDialogState(() => focusedDay = newFocusedDay);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    selectedDays.isEmpty
                        ? '日付をタップして選択してください'
                        : '${selectedDays.length}日選択中',
                    style: TextStyle(
                      color: selectedDays.isEmpty
                          ? Colors.grey
                          : Theme.of(ctx).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('発起人として設定する'),
                  subtitle: const Text(
                    '梅屋オーナーが主催者として枠を設定します',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: asInitiator,
                  onChanged: (v) => setDialogState(() => asInitiator = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: selectedDays.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      if (asInitiator) {
                        // 代表日付で確認ダイアログ
                        final sortedDates = selectedDays.toList()..sort();
                        final firstDateStr =
                            '${sortedDates.first.year}-${_fmt2(sortedDates.first.month)}-${_fmt2(sortedDates.first.day)}';
                        final settings =
                            await _showAdminInitiatorDialog(context, firstDateStr);
                        if (settings != null) {
                          await _addMultipleSlots(
                            sortedDates,
                            initiatorSettings: settings,
                          );
                        }
                      } else {
                        await _addMultipleSlots(selectedDays.toList());
                      }
                    },
              child: Text(
                  selectedDays.isEmpty ? '追加' : '${selectedDays.length}日を追加'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMultipleSlots(
    List<DateTime> dates, {
    _InitiatorSettings? initiatorSettings,
  }) async {
    dates.sort();
    int successCount = 0;
    final errors = <String>[];

    for (final date in dates) {
      final dateStr =
          '${date.year}-${_fmt2(date.month)}-${_fmt2(date.day)}';
      try {
        final slotData = await apiClient.createSlot(dateStr);
        if (initiatorSettings != null) {
          final slotId = slotData['id'] as String;
          await apiClient.createReservation(
            slotId,
            minVendors: initiatorSettings.minVendors,
            maxVendors: initiatorSettings.maxVendors,
          );
          await apiClient.updateSlot(
            slotId,
            name: initiatorSettings.name,
            startTime: initiatorSettings.startTime,
            endTime: initiatorSettings.endTime,
            description: initiatorSettings.description,
          );
        }
        successCount++;
      } on ApiException catch (e) {
        errors.add('$dateStr: ${e.message}');
      }
    }

    if (mounted) {
      _loadSlots();
      final message = errors.isEmpty
          ? '$successCount日分の枠を追加しました'
          : '$successCount日追加（${errors.length}件失敗）';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: errors.isEmpty ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  Future<_InitiatorSettings?> _showAdminInitiatorDialog(
      BuildContext context, String sampleDate) {
    int minVendors = 3;
    int maxVendors = 8;
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    String fmtTime(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return showDialog<_InitiatorSettings>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: const Text('発起人として設定'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '枠名（任意）',
                      hintText: '例：春の梅屋マルシェ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('最低人数'),
                      Row(children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: minVendors > 1
                              ? () => setS(() {
                                    minVendors--;
                                    if (maxVendors < minVendors) maxVendors = minVendors;
                                  })
                              : null,
                        ),
                        Text('$minVendors人',
                            style: const TextStyle(fontSize: 18)),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: minVendors < 15
                              ? () => setS(() => minVendors++)
                              : null,
                        ),
                      ]),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('最大人数'),
                      Row(children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: maxVendors > minVendors
                              ? () => setS(() => maxVendors--)
                              : null,
                        ),
                        Text('$maxVendors人',
                            style: const TextStyle(fontSize: 18)),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: maxVendors < 15
                              ? () => setS(() => maxVendors++)
                              : null,
                        ),
                      ]),
                    ],
                  ),
                  const Divider(height: 24),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('希望時間帯（任意）',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF616161))),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time, size: 16),
                        label: Text(startTime == null
                            ? '開始時間'
                            : fmtTime(startTime!)),
                        onPressed: () async {
                          final p = await showTimePicker(
                            context: ctx,
                            initialTime: startTime ??
                                const TimeOfDay(hour: 10, minute: 0),
                            builder: (c, child) => MediaQuery(
                              data: MediaQuery.of(c)
                                  .copyWith(alwaysUse24HourFormat: true),
                              child: child!,
                            ),
                          );
                          if (p != null) setS(() => startTime = p);
                        },
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('〜'),
                    ),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time, size: 16),
                        label: Text(
                            endTime == null ? '終了時間' : fmtTime(endTime!)),
                        onPressed: () async {
                          final p = await showTimePicker(
                            context: ctx,
                            initialTime: endTime ??
                                const TimeOfDay(hour: 17, minute: 0),
                            builder: (c, child) => MediaQuery(
                              data: MediaQuery.of(c)
                                  .copyWith(alwaysUse24HourFormat: true),
                              child: child!,
                            ),
                          );
                          if (p != null) setS(() => endTime = p);
                        },
                      ),
                    ),
                  ]),
                  const Divider(height: 24),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('募集要項（任意）',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF616161))),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: '参加者への一言、出店テーマ、持参物など',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                ctx,
                _InitiatorSettings(
                  minVendors: minVendors,
                  maxVendors: maxVendors,
                  startTime:
                      startTime != null ? fmtTime(startTime!) : null,
                  endTime: endTime != null ? fmtTime(endTime!) : null,
                  description: descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  name: nameCtrl.text.trim().isEmpty
                      ? null
                      : nameCtrl.text.trim(),
                ),
              ),
              child: const Text('設定する'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- 枠カード ----

class _SlotCard extends StatelessWidget {
  final Slot slot;
  final VoidCallback onReserved;
  final VoidCallback? onDeleted;

  const _SlotCard({required this.slot, required this.onReserved, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.read<AuthProvider>();
    final myUserId = auth.user?.id;
    final isJoined =
        myUserId != null && slot.vendors.any((v) => v.userId == myUserId);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // カラーアクセントバー（ステータスに応じた色）
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: switch (slot.status) {
                'recruiting' => const Color(0xFFE07B00),
                'confirmed' => const Color(0xFF2E7D32),
                'cancelled' => const Color(0xFFC62828),
                _ => const Color(0xFFCCCCCC),
              },
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
          ),
          Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 日付・ステータス・参加中バッジ
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        slot.date,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (slot.name != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          slot.name!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Row(
                  children: [
                    if (isJoined) ...[
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: slot.isConfirmed
                              ? const Color(0xFFE8F5E9)
                              : const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 12,
                              color: slot.isConfirmed
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFFE07B00),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '参加中',
                              style: TextStyle(
                                color: slot.isConfirmed
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFFE07B00),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    _StatusChip(status: slot.status),
                    // 管理者 + (募集前 or 発起人) の場合に削除ボタン
                    if (auth.isAdmin && (slot.isOpen || slot.vendors.any((v) => v.userId == myUserId && v.isInitiator))) ...[
                      const SizedBox(width: 4),
                      _DeleteSlotButton(slot: slot, onDeleted: onDeleted),
                    ],
                  ],
                ),
              ],
            ),
            if (slot.startTime != null && slot.endTime != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('${slot.startTime} 〜 ${slot.endTime}',
                      style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ],
            if (slot.description != null && slot.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                slot.description!,
                style: const TextStyle(fontSize: 13, color: Color(0xFF616161)),
              ),
            ],

            const SizedBox(height: 12),

            // 参加者アコーディオン
            if (slot.vendors.isNotEmpty) ...[
              _VendorList(vendors: slot.vendors, myUserId: myUserId),
              const SizedBox(height: 8),
            ],

            // 募集状況バー
            if (slot.minVendors != null) ...[
              _ProgressBar(slot: slot),
              const SizedBox(height: 12),
            ],

            // 予約ボタン（未参加・出店者のみ）
            if (!auth.isAdmin && !isJoined && (slot.isOpen || slot.isRecruiting))
              _ReserveButton(slot: slot, onReserved: onReserved),

            // キャンセルボタン（参加中・募集中のみ）
            if (!auth.isAdmin && isJoined && slot.isRecruiting)
              _CancelButton(slot: slot, onCancelled: onReserved),
          ],
          ),
          ),
        ],
      ),
    );
  }
}

// ---- 枠削除ボタン（管理者 + open のみ） ----

class _DeleteSlotButton extends StatefulWidget {
  final Slot slot;
  final VoidCallback? onDeleted;
  const _DeleteSlotButton({required this.slot, this.onDeleted});

  @override
  State<_DeleteSlotButton> createState() => _DeleteSlotButtonState();
}

class _DeleteSlotButtonState extends State<_DeleteSlotButton> {
  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('枠を削除'),
        content: Text(
          widget.slot.vendors.isNotEmpty
              ? '${widget.slot.date} の枠を削除しますか？\n参加中の出店者（${widget.slot.vendors.length}人）の予約もすべてキャンセルされます。\nこの操作は元に戻せません。'
              : '${widget.slot.date} の枠を削除しますか？\nこの操作は元に戻せません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await apiClient.deleteSlot(widget.slot.id);
      widget.onDeleted?.call();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.delete_outline, size: 18),
      color: Colors.red,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      ),
      onPressed: _delete,
      tooltip: '枠を削除',
    );
  }
}

// ---- ステータスチップ ----

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'open' => ('募集前', const Color(0xFFF0EDEE), const Color(0xFF888088)),
      'recruiting' => ('募集中', const Color(0xFFFFF3E0), const Color(0xFFE07B00)),
      'confirmed' => ('開催確定', const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      'cancelled' => ('キャンセル', const Color(0xFFFFEBEE), const Color(0xFFC62828)),
      _ => ('不明', const Color(0xFFF0EDEE), const Color(0xFF888088)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---- 参加者リスト（アコーディオン） ----

class _VendorList extends StatelessWidget {
  final List<SlotVendor> vendors;
  final String? myUserId;

  const _VendorList({required this.vendors, this.myUserId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Row(
        children: [
          // 先頭3人のアバター
          ...vendors.take(3).map((v) => Padding(
                padding: const EdgeInsets.only(right: 3),
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  backgroundImage: v.avatarUrl != null
                      ? NetworkImage(resolveUrl(v.avatarUrl!))
                      : null,
                  child: v.avatarUrl == null
                      ? Text((v.shopName ?? '?').substring(0, 1),
                          style: const TextStyle(fontSize: 8))
                      : null,
                ),
              )),
          if (vendors.length > 3)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text('+${vendors.length - 3}',
                  style:
                      const TextStyle(fontSize: 11, color: Colors.grey)),
            ),
          const SizedBox(width: 8),
          Text('参加者 ${vendors.length}人',
              style: const TextStyle(fontSize: 13, color: Color(0xFF616161))),
        ],
      ),
      children: vendors.map((v) {
        final isMe = v.userId == myUserId;
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primaryContainer,
            backgroundImage:
                v.avatarUrl != null ? NetworkImage(resolveUrl(v.avatarUrl!)) : null,
            child: v.avatarUrl == null
                ? Text((v.shopName ?? '?').substring(0, 1),
                    style: const TextStyle(fontSize: 12))
                : null,
          ),
          title: Row(
            children: [
              Text(v.shopName ?? '名前未設定',
                  style: const TextStyle(fontSize: 14)),
              if (v.isInitiator) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('発起人',
                      style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.primary)),
                ),
              ],
              if (isMe) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('自分',
                      style:
                          TextStyle(fontSize: 10, color: Colors.grey)),
                ),
              ],
            ],
          ),
          trailing: isMe
              ? null
              : const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          onTap: isMe
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            UserProfileScreen(userId: v.userId)),
                  ),
        );
      }).toList(),
    );
  }
}

// ---- 募集進捗バー ----

class _ProgressBar extends StatelessWidget {
  final Slot slot;
  const _ProgressBar({required this.slot});

  @override
  Widget build(BuildContext context) {
    final min = slot.minVendors ?? 0;
    final max = slot.maxVendors ?? min;
    final current = slot.currentCount;
    final progress = min > 0 ? (current / min).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$current / $min人（最大$max人）',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey[200],
          color: progress >= 1.0 ? Colors.green : Colors.orange,
        ),
      ],
    );
  }
}

// ---- キャンセルボタン ----

class _CancelButton extends StatefulWidget {
  final Slot slot;
  final VoidCallback onCancelled;
  const _CancelButton({required this.slot, required this.onCancelled});

  @override
  State<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends State<_CancelButton> {
  bool _isLoading = false;

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('出店をキャンセル'),
        content: Text(
          '${widget.slot.date} の出店参加をキャンセルしますか？\n\n'
          '※ キャンセル後、参加者が最低人数を下回った場合は募集中に戻ります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('キャンセルする'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await apiClient.cancelReservation(widget.slot.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('キャンセルしました'),
            backgroundColor: Colors.orange,
          ),
        );
        widget.onCancelled();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
        ),
        onPressed: _isLoading ? null : _cancel,
        icon: _isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
              )
            : const Icon(Icons.cancel_outlined, size: 18),
        label: const Text('出店をキャンセル'),
      ),
    );
  }
}

// ---- 予約ボタン ----

class _ReserveButton extends StatefulWidget {
  final Slot slot;
  final VoidCallback onReserved;
  const _ReserveButton({required this.slot, required this.onReserved});

  @override
  State<_ReserveButton> createState() => _ReserveButtonState();
}

class _ReserveButtonState extends State<_ReserveButton> {
  bool _isLoading = false;

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _reserve() async {
    if (widget.slot.isOpen) {
      // 発起人: 条件設定 → 確認 → 申込
      final settings = await _showInitiatorDialog();
      if (settings != null) {
        await _doReserve(
          minVendors: settings.minVendors,
          maxVendors: settings.maxVendors,
          startTime: settings.startTime,
          endTime: settings.endTime,
          description: settings.description,
        );
      }
    } else {
      // 非発起人: 参加申請ダイアログ
      final message = await _showJoinRequestDialog();
      if (message != null) await _doJoinRequest(message);
    }
  }

  Future<String?> _showJoinRequestDialog() async {
    final msgCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('参加申請を送る'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.slot.date,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (widget.slot.description != null &&
                  widget.slot.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.slot.description!,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: msgCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '一言メッセージ（任意）',
                  hintText: '出店内容や意気込みなどを書いてみましょう',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, msgCtrl.text),
            child: const Text('申請を送る'),
          ),
        ],
      ),
    );
  }

  Future<void> _doJoinRequest(String message) async {
    setState(() => _isLoading = true);
    try {
      await apiClient.sendJoinRequest(widget.slot.id, message: message);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('参加申請を送りました。発起人の承認をお待ちください。'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onReserved();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 発起人ダイアログ: 条件設定 + 内容確認。設定値を返す（キャンセル時はnull）
  Future<_InitiatorSettings?> _showInitiatorDialog() {
    int minVendors = 3;
    int maxVendors = 8;
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    final descCtrl = TextEditingController();

    return showDialog<_InitiatorSettings>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: const Text('出店希望条件を設定'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 最低人数
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('最低人数'),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: minVendors > 1
                              ? () => setDialogState(() {
                                    minVendors--;
                                    if (maxVendors < minVendors) {
                                      maxVendors = minVendors;
                                    }
                                  })
                              : null,
                        ),
                        Text('$minVendors人',
                            style: const TextStyle(fontSize: 18)),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: minVendors < 15
                              ? () => setDialogState(() => minVendors++)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
                // 最大人数
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('最大人数'),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: maxVendors > minVendors
                              ? () => setDialogState(() => maxVendors--)
                              : null,
                        ),
                        Text('$maxVendors人',
                            style: const TextStyle(fontSize: 18)),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: maxVendors < 15
                              ? () => setDialogState(() => maxVendors++)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 24),
                // 時間帯（任意）
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('希望時間帯（任意）',
                      style:
                          TextStyle(fontSize: 13, color: Color(0xFF616161))),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time, size: 16),
                        label: Text(
                          startTime == null
                              ? '開始時間'
                              : _formatTime(startTime!),
                          style: const TextStyle(fontSize: 13),
                        ),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: startTime ??
                                const TimeOfDay(hour: 10, minute: 0),
                            builder: (context, child) => MediaQuery(
                              data: MediaQuery.of(context)
                                  .copyWith(alwaysUse24HourFormat: true),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            setDialogState(() => startTime = picked);
                          }
                        },
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('〜'),
                    ),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time, size: 16),
                        label: Text(
                          endTime == null
                              ? '終了時間'
                              : _formatTime(endTime!),
                          style: const TextStyle(fontSize: 13),
                        ),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: endTime ??
                                const TimeOfDay(hour: 17, minute: 0),
                            builder: (context, child) => MediaQuery(
                              data: MediaQuery.of(context)
                                  .copyWith(alwaysUse24HourFormat: true),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            setDialogState(() => endTime = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                // 募集要項（任意）
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('募集要項（任意）',
                      style: TextStyle(fontSize: 13, color: Color(0xFF616161))),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: '参加者への一言、出店テーマ、持参物など',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () async {
                final timeStr = (startTime != null && endTime != null)
                    ? '${_formatTime(startTime!)} 〜 ${_formatTime(endTime!)}'
                    : '未設定';
                // 確認ダイアログ
                final confirmed = await showDialog<bool>(
                  context: ctx,
                  builder: (confirmCtx) => AlertDialog(
                    title: const Text('申し込み内容の確認'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ConfirmRow('開催日', widget.slot.date),
                        _ConfirmRow('最低人数', '$minVendors人'),
                        _ConfirmRow('最大人数', '$maxVendors人'),
                        _ConfirmRow('希望時間', timeStr),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(confirmCtx, false),
                        child: const Text('戻る'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(confirmCtx, true),
                        child: const Text('出店を申し込む'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                // 条件ダイアログを閉じて設定値を返す
                if (ctx.mounted) {
                  Navigator.pop(
                    ctx,
                    _InitiatorSettings(
                      minVendors: minVendors,
                      maxVendors: maxVendors,
                      startTime: startTime != null
                          ? _formatTime(startTime!)
                          : null,
                      endTime:
                          endTime != null ? _formatTime(endTime!) : null,
                      description: descCtrl.text.trim().isEmpty
                          ? null
                          : descCtrl.text.trim(),
                    ),
                  );
                }
              },
              child: const Text('内容を確認する'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doReserve({
    int? minVendors,
    int? maxVendors,
    String? startTime,
    String? endTime,
    String? description,
  }) async {
    setState(() => _isLoading = true);
    try {
      await apiClient.createReservation(
        widget.slot.id,
        minVendors: minVendors,
        maxVendors: maxVendors,
      );
      // 時間・説明が設定されている場合はスロットも更新
      if (startTime != null || endTime != null || description != null) {
        try {
          await apiClient.updateSlot(widget.slot.id,
              startTime: startTime, endTime: endTime, description: description);
        } catch (_) {
          // スロット更新失敗は無視（予約自体は成功しているため）
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('出店を申し込みました！'),
              backgroundColor: Colors.green),
        );
        widget.onReserved();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _isLoading ? null : _reserve,
        child: _isLoading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(widget.slot.isOpen ? '出店を申し込む（発起人）' : '参加申請を送る'),
      ),
    );
  }
}

// 確認ダイアログ内の行ウィジェット
class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;
  const _ConfirmRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style:
                    const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ---- フィルターチップ ----

class _FilterChips extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;

  const _FilterChips({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const filters = [
      ('all', 'すべて'),
      ('joined', '参加中'),
      ('recruiting', '募集中'),
      ('confirmed', '開催確定'),
      ('open', '募集前'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: filters.map((f) {
          final (value, label) = f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label),
              selected: current == value,
              onSelected: (_) => onChanged(value),
            ),
          );
        }).toList(),
      ),
    );
  }
}
