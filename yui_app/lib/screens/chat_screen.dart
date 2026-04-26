import 'dart:async';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_client.dart';
import '../core/app_snackbar.dart';
import '../core/auth_provider.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'profile_screen.dart';

const _imageExpireDays = 60;

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => ChatListScreenState();
}

class ChatListScreenState extends State<ChatListScreen> {
  List<ChatRoom> _rooms = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    loadRooms();
  }

  Future<void> loadRooms() async {
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: loadRooms),
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
            ElevatedButton(onPressed: loadRooms, child: const Text('再読み込み')),
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
      onRefresh: loadRooms,
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
            if (mounted) loadRooms();
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
  StreamSubscription<RemoteMessage>? _fcmSubscription;
  String? _startTime;
  String? _endTime;
  String? _slotName;
  File? _pendingImage;

  @override
  void initState() {
    super.initState();
    _startTime = widget.room.startTime;
    _endTime = widget.room.endTime;
    _slotName = widget.room.slotName;
    _loadMessages();
    _pollTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _pollMessages(),
    );
    _fcmSubscription = FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] == 'new_chat_message' &&
          message.data['room_id'] == widget.room.roomId) {
        _pollMessages();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _fcmSubscription?.cancel();
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

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final outPath = '${Directory.systemTemp.path}/chat_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final compressed = await FlutterImageCompress.compressAndGetFile(
      picked.path,
      outPath,
      quality: 70,
      minWidth: 1080,
      minHeight: 1080,
      format: CompressFormat.jpeg,
    );
    if (compressed != null && mounted) {
      setState(() => _pendingImage = File(compressed.path));
    }
  }

  DateTime _parseCreatedAt(String iso) {
    final normalized = iso.endsWith('Z') || iso.contains('+') ? iso : '${iso}Z';
    return DateTime.parse(normalized);
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
        _messages.sort((a, b) => _parseCreatedAt(a.createdAt).compareTo(_parseCreatedAt(b.createdAt)));
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
    final image = _pendingImage;
    if (text.isEmpty && image == null) return;

    setState(() { _isSending = true; _pendingImage = null; });
    _inputCtrl.clear();

    final authUser = context.read<AuthProvider>().user;

    try {
      final data = await apiClient.sendMessage(
        widget.room.roomId,
        text,
        imageFile: image,
      );
      final msg = Message.fromJson({
        ...data,
        'shop_name': authUser?.shopName,
        'avatar_url': authUser?.avatarUrl,
      });
      setState(() {
        _messages.add(msg);
        _messages.sort((a, b) => _parseCreatedAt(a.createdAt).compareTo(_parseCreatedAt(b.createdAt)));
      });
      _scrollToBottom();
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message, isError: true);
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
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 画像プレビュー
                  if (_pendingImage != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              _pendingImage!,
                              height: 100,
                              width: 100,
                              fit: BoxFit.cover,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _pendingImage = null),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(2),
                              child: const Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // テキスト入力行
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.image_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: _isSending ? null : _pickImage,
                        ),
                        Expanded(
                          child: TextField(
                            controller: _inputCtrl,
                            maxLines: null,
                            textInputAction: TextInputAction.newline,
                            decoration: const InputDecoration(
                              hintText: 'メッセージを入力',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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

  bool get _isImageExpired {
    if (message.imageUrl == null) return false;
    try {
      final normalized = message.createdAt.endsWith('Z') || message.createdAt.contains('+')
          ? message.createdAt
          : '${message.createdAt}Z';
      return DateTime.now().difference(DateTime.parse(normalized)).inDays >= _imageExpireDays;
    } catch (_) {
      return false;
    }
  }

  Widget _buildImageContent(BuildContext context) {
    if (_isImageExpired) {
      return Container(
        width: 180,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported_outlined, color: Colors.grey[500], size: 28),
            const SizedBox(height: 4),
            Text(
              '保存期限が過ぎました',
              style: TextStyle(color: Colors.grey[600], fontSize: 11),
            ),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _FullscreenImageScreen(
            imageUrl: resolveUrl(message.imageUrl!),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          resolveUrl(message.imageUrl!),
          width: 200,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : SizedBox(
                  width: 200,
                  height: 140,
                  child: Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                          : null,
                      strokeWidth: 2,
                    ),
                  ),
                ),
          errorBuilder: (context, err, stack) => Container(
            width: 200,
            height: 120,
            color: Colors.grey[200],
            child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = message.imageUrl != null;
    final hasText = message.body.isNotEmpty;

    if (isMe) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 64),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (hasImage) ...[
              _buildImageContent(context),
              const SizedBox(height: 4),
            ],
            if (hasText)
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
                child: Linkify(
                  text: message.body,
                  style: const TextStyle(color: Colors.white),
                  linkStyle: const TextStyle(color: Colors.white, decoration: TextDecoration.underline),
                  onOpen: (link) => launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication),
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

    // 他人のメッセージ
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
                if (hasImage) ...[
                  _buildImageContent(context),
                  const SizedBox(height: 4),
                ],
                if (hasText)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    child: Linkify(
                      text: message.body,
                      linkStyle: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
                      onOpen: (link) => launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication),
                    ),
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

// ---- フルスクリーン画像ビューワー ----

class _FullscreenImageScreen extends StatelessWidget {
  final String imageUrl;

  const _FullscreenImageScreen({required this.imageUrl});

  Future<void> _saveImage(BuildContext context) async {
    try {
      final response = await http.get(Uri.parse(imageUrl));
      final result = await ImageGallerySaver.saveImage(
        response.bodyBytes,
        name: 'yui_chat_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (context.mounted) {
        final saved = result['isSuccess'] == true;
        showAppSnackBar(context, saved ? '画像を保存しました' : '保存に失敗しました', isError: !saved);
      }
    } catch (_) {
      if (context.mounted) showAppSnackBar(context, '保存に失敗しました', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: '保存',
            onPressed: () => _saveImage(context),
          ),
        ],
      ),
      body: PhotoView(
        imageProvider: NetworkImage(imageUrl),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 3,
        loadingBuilder: (_, __) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        errorBuilder: (context, err, stack) => const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
        ),
      ),
    );
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
  int? _maxVendors;
  bool _isSavingTime = false;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _startTime = _parseTime(widget.currentStartTime);
    _endTime = _parseTime(widget.currentEndTime);
    _nameCtrl = TextEditingController(text: widget.currentName ?? '');
    _maxVendors = widget.room.maxVendors;
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
        maxVendors: _maxVendors,
      );
      widget.onTimeUpdated(_toHHMM(_startTime), _toHHMM(_endTime));
      widget.onNameUpdated(newName);
      if (mounted) {
        showAppSnackBar(context, '保存しました');
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      if (mounted) {
        showAppSnackBar(context, e.message, isError: true);
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
        showAppSnackBar(context, e.message, isError: true);
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
          if (widget.isInitiator && widget.room.minVendors != null) ...[
            const SizedBox(height: 20),
            const Text('参加人数', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '最低 ${widget.room.minVendors}人（固定）',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const Spacer(),
                const Text('最大: ', style: TextStyle(fontSize: 13)),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: (_maxVendors ?? 0) > (widget.room.minVendors ?? 1)
                      ? () => setState(() => _maxVendors = (_maxVendors ?? 1) - 1)
                      : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Text('${_maxVendors ?? '-'}人', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() => _maxVendors = (_maxVendors ?? widget.room.minVendors ?? 1) + 1),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
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
