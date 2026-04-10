import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/auth_provider.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'profile_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<ChatRoom> _rooms = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await apiClient.getChatRooms();
      setState(() {
        _rooms = data
            .map((e) => ChatRoom.fromJson(e as Map<String, dynamic>))
            .toList();
        _isLoading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('チャット'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadRooms),
        ],
      ),
      body: _buildBody(),
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
            ElevatedButton(onPressed: _loadRooms, child: const Text('再読み込み')),
          ],
        ),
      );
    }
    if (_rooms.isEmpty) {
      return const Center(
        child: Text(
          '参加確定したイベントのチャットが\nここに表示されます',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadRooms,
      child: ListView.separated(
        itemCount: _rooms.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, index) => _ChatRoomTile(
          room: _rooms[index],
          onTap: () async {
            final result = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (_) => ChatRoomScreen(room: _rooms[index]),
              ),
            );
            // 部屋から戻ったら既読反映のため一覧を再取得
            if (mounted) _loadRooms();
          },
        ),
      ),
    );
  }
}

class _ChatRoomTile extends StatelessWidget {
  final ChatRoom room;
  final VoidCallback onTap;

  const _ChatRoomTile({required this.room, required this.onTap});

  String _formatLastTime(String? iso) {
    if (iso == null) return '';
    try {
      final normalized = iso.endsWith('Z') || iso.contains('+') ? iso : '${iso}Z';
      final dt = DateTime.parse(normalized).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = room.unreadCount > 0;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      onTap: onTap,
      title: Row(
        children: [
          Expanded(
            child: Text(
              room.displayTitle,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (room.lastMessageAt != null) ...[
            const SizedBox(width: 8),
            Text(
              _formatLastTime(room.lastMessageAt),
              style: TextStyle(
                fontSize: 11,
                color: hasUnread ? theme.colorScheme.primary : Colors.grey,
              ),
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (room.lastMessageBody != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(
                room.lastMessageBody!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: hasUnread ? Colors.black87 : Colors.grey,
                  fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          Row(
            children: [
              ...room.members.take(5).map(
                (m) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: m.avatarUrl != null
                        ? NetworkImage(resolveUrl(m.avatarUrl!))
                        : null,
                    child: m.avatarUrl == null
                        ? Text(
                            (m.shopName ?? '?').substring(0, 1),
                            style: const TextStyle(fontSize: 9),
                          )
                        : null,
                  ),
                ),
              ),
              if (room.members.length > 5)
                Text(
                  '+${room.members.length - 5}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],
          ),
        ],
      ),
      trailing: hasUnread
          ? Badge(
              label: Text('${room.unreadCount}'),
              child: const SizedBox(width: 8),
            )
          : const Icon(Icons.chevron_right, color: Colors.grey),
    );
  }
}

// ---- 個別チャットルーム画面 ----

class ChatRoomScreen extends StatefulWidget {
  final ChatRoom room;
  const ChatRoomScreen({super.key, required this.room});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final List<Message> _messages = [];
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _isLoadingMessages = true;
  bool _isSending = false;
  Timer? _pollTimer;
  String? _startTime;
  String? _endTime;
  String? _slotName;

  @override
  void initState() {
    super.initState();
    _startTime = widget.room.startTime;
    _endTime = widget.room.endTime;
    _slotName = widget.room.slotName;
    _loadMessages();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollMessages(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final data = await apiClient.getMessages(widget.room.roomId);
      final msgs = (data['messages'] as List<dynamic>)
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
        _isLoadingMessages = false;
      });
      _scrollToBottom();
    } on ApiException {
      setState(() => _isLoadingMessages = false);
    }
  }

  // 差分のみ取得して追記（IDベースで重複排除）
  Future<void> _pollMessages() async {
    if (!mounted) return;
    try {
      final data = await apiClient.getMessages(widget.room.roomId);
      final msgs = (data['messages'] as List<dynamic>)
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList();

      if (msgs.isEmpty) return;

      final existingIds = _messages.map((m) => m.id).toSet();
      final newMsgs = msgs.where((m) => !existingIds.contains(m.id)).toList();

      if (newMsgs.isEmpty) return;

      setState(() {
        _messages.addAll(newMsgs);
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      });
      _scrollToBottom();
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    _inputCtrl.clear();

    final authUser = context.read<AuthProvider>().user;

    try {
      final data = await apiClient.sendMessage(widget.room.roomId, text);
      final msg = Message.fromJson({
        ...data,
        'shop_name': authUser?.shopName,
        'avatar_url': authUser?.avatarUrl,
      });
      setState(() => _messages.add(msg));
      _scrollToBottom();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _showSettingsSheet(bool isInitiator) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _EventSettingsSheet(
        room: widget.room,
        currentStartTime: _startTime,
        currentEndTime: _endTime,
        currentName: _slotName,
        isInitiator: isInitiator,
        onTimeUpdated: (start, end) {
          if (mounted) setState(() { _startTime = start; _endTime = end; });
        },
        onNameUpdated: (name) {
          if (mounted) setState(() => _slotName = name);
        },
        onEventCancelled: () {
          if (mounted) Navigator.pop(context, 'room_closed');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = context.read<AuthProvider>().user?.id;
    final isInitiator = widget.room.members.any(
      (m) => m.id == myUserId && m.isInitiator,
    );
    final title = _slotName ?? widget.room.date;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16)),
            Text(
              widget.room.date,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          // 参加者アイコン（3人まで）
          ...widget.room.members.take(3).map(
            (m) => GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(userId: m.id),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  backgroundImage: m.avatarUrl != null
                      ? NetworkImage(resolveUrl(m.avatarUrl!))
                      : null,
                  child: m.avatarUrl == null
                      ? Text(
                          (m.shopName ?? '?').substring(0, 1),
                          style: const TextStyle(fontSize: 11),
                        )
                      : null,
                ),
              ),
            ),
          ),
          // 設定ボタン
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _showSettingsSheet(isInitiator),
          ),
        ],
      ),
      body: Column(
        children: [
          // メッセージ一覧
          Expanded(
            child: _isLoadingMessages
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? const Center(
                    child: Text(
                      'まだメッセージがありません',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) => _MessageBubble(
                      message: _messages[index],
                      isMe: _messages[index].userId == myUserId,
                      onAvatarTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UserProfileScreen(
                            userId: _messages[index].userId,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          // 入力欄
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      maxLines: null,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'メッセージを入力',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.send,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    onPressed: _isSending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- メッセージバブル ----

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final VoidCallback onAvatarTap;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isMe) {
      // 自分のメッセージ: 右寄せ
      return Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 64),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Text(
                message.body,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatTime(message.createdAt),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // 他人のメッセージ: 左寄せ（アイコン・名前付き）
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 64),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: onAvatarTap,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer,
              backgroundImage: message.avatarUrl != null
                  ? NetworkImage(resolveUrl(message.avatarUrl!))
                  : null,
              child: message.avatarUrl == null
                  ? Text(
                      (message.shopName ?? '?').substring(0, 1),
                      style: const TextStyle(fontSize: 11),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.shopName ?? '名前未設定',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Text(message.body),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTime(message.createdAt),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      // SQLiteのCURRENT_TIMESTAMPはUTCだがZサフィックスがないためUTCとして扱う
      final normalized = iso.endsWith('Z') || iso.contains('+') ? iso : '${iso}Z';
      final dt = DateTime.parse(normalized).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }
}

// ---- イベント設定シート ----

class _EventSettingsSheet extends StatefulWidget {
  final ChatRoom room;
  final String? currentStartTime;
  final String? currentEndTime;
  final String? currentName;
  final bool isInitiator;
  final void Function(String?, String?) onTimeUpdated;
  final void Function(String?) onNameUpdated;
  final VoidCallback onEventCancelled;

  const _EventSettingsSheet({
    required this.room,
    required this.currentStartTime,
    required this.currentEndTime,
    this.currentName,
    required this.isInitiator,
    required this.onTimeUpdated,
    required this.onNameUpdated,
    required this.onEventCancelled,
  });

  @override
  State<_EventSettingsSheet> createState() => _EventSettingsSheetState();
}

class _EventSettingsSheetState extends State<_EventSettingsSheet> {
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  late final TextEditingController _nameCtrl;
  bool _isSavingTime = false;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _startTime = _parseTime(widget.currentStartTime);
    _endTime = _parseTime(widget.currentEndTime);
    _nameCtrl = TextEditingController(text: widget.currentName ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  TimeOfDay? _parseTime(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatTimeOfDay(TimeOfDay? t) {
    if (t == null) return '未設定';
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String? _toHHMM(TimeOfDay? t) {
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = (isStart ? _startTime : _endTime) ?? TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _isSavingTime = true);
    try {
      final newName = _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim();
      await apiClient.updateSlot(
        widget.room.slotId,
        name: newName,
        startTime: _toHHMM(_startTime),
        endTime: _toHHMM(_endTime),
      );
      widget.onTimeUpdated(_toHHMM(_startTime), _toHHMM(_endTime));
      widget.onNameUpdated(newName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存しました')),
        );
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingTime = false);
    }
  }

  Future<void> _cancelEvent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('イベントをキャンセル'),
        content: const Text(
          'このイベントをキャンセルすると、参加者全員の予約がキャンセルされ、チャットルームも削除されます。\nよろしいですか？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('戻る'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('キャンセルする'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isCancelling = true);
    try {
      await apiClient.cancelEvent(widget.room.slotId);
      if (mounted) Navigator.pop(context);
      widget.onEventCancelled();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'イベント設定',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (widget.isInitiator) ...[
            const SizedBox(height: 20),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '枠名（任意）',
                hintText: '例：春の梅屋マルシェ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text('開催時間帯', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.access_time, size: 18),
                  label: Text('開始: ${_formatTimeOfDay(_startTime)}'),
                  onPressed: () => _pickTime(isStart: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.access_time, size: 18),
                  label: Text('終了: ${_formatTimeOfDay(_endTime)}'),
                  onPressed: () => _pickTime(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSavingTime ? null : _save,
              child: _isSavingTime
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ),
          if (widget.isInitiator) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isCancelling ? null : _cancelEvent,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                child: _isCancelling
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.red,
                        ),
                      )
                    : const Text('イベントをキャンセル（全員解除）'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
