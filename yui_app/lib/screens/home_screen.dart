import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/auth_provider.dart';
import '../core/notification_handler.dart';
import '../models/app_notification.dart';
import '../models/chat.dart';
import '../models/join_request.dart';
import 'calendar_screen.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'admin_screen.dart';
import 'notifications_screen.dart';
import 'package:upgrader/upgrader.dart';

// iTunes APIが trackViewUrl を返さない場合でもApp Storeを開けるようフォールバックURLを保証
class _IosUpgraderStore extends UpgraderStore {
  final _inner = UpgraderAppStore();

  @override
  Future<UpgraderVersionInfo> getVersionInfo({
    required UpgraderState state,
    required installedVersion,
    required String? country,
    required String? language,
  }) async {
    final info = await _inner.getVersionInfo(
      state: state,
      installedVersion: installedVersion,
      country: country,
      language: language,
    );
    if (info.appStoreListingURL != null && info.appStoreListingURL!.isNotEmpty) {
      return info;
    }
    return UpgraderVersionInfo(
      appStoreListingURL: 'https://apps.apple.com/jp/app/id6762629745',
      appStoreVersion: info.appStoreVersion,
      installedVersion: info.installedVersion,
      isCriticalUpdate: info.isCriticalUpdate,
      minAppVersion: info.minAppVersion,
      releaseNotes: info.releaseNotes,
    );
  }
}

class _JaUpgraderMessages extends UpgraderMessages {
  @override
  String get title => 'アップデートのお知らせ';
  @override
  String get body => '{{appName}} の新しいバージョン（{{currentInstalledVersion}} → {{currentAppStoreVersion}}）が利用可能です。';
  @override
  String get buttonTitleUpdate => '今すぐアップデート';
  @override
  String get buttonTitleIgnore => '無視する';
  @override
  String get buttonTitleLater => '後で';
  @override
  String get prompt => 'アップデートしますか？';
  @override
  String get releaseNotes => 'リリースノート';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  int _pendingCount = 0;
  final _calendarKey = GlobalKey<CalendarScreenState>();
  final _chatListKey = GlobalKey<ChatListScreenState>();

  @override
  void initState() {
    super.initState();
    _loadPendingCount();
    _loadChatUnread();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setupNotificationHandlers(context);
    });
  }

  Future<void> _loadPendingCount() async {
    try {
      final results = await Future.wait([
        apiClient.getIncomingRequests(),
        apiClient.getNotifications(),
      ]);
      final incomingCount = results[0]
          .map((e) => JoinRequest.fromJson(e as Map<String, dynamic>))
          .where((r) => r.status == 'pending')
          .length;
      final unreadCount = results[1]
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .where((n) => !n.isRead)
          .length;
      if (mounted) setState(() => _pendingCount = incomingCount + unreadCount);
    } catch (_) {
      // バッジ更新失敗は無視
    }
  }

  // チャット未読数をバッジに反映（チャットタブ用）
  int _chatUnreadCount = 0;
  Future<void> _loadChatUnread() async {
    try {
      final rooms = await apiClient.getChatRooms();
      int total = 0;
      for (final e in rooms) {
        total += ChatRoom.fromJson(e as Map<String, dynamic>).unreadCount;
      }
      if (mounted) setState(() => _chatUnreadCount = total);
    } catch (_) {}
  }

  List<Widget> get _screens {
    final auth = context.read<AuthProvider>();
    if (auth.isAdmin) {
      return [
        CalendarScreen(key: _calendarKey),
        ChatListScreen(key: _chatListKey),
        NotificationsScreen(key: const ValueKey('notifications'), onRefreshed: _loadPendingCount),
        const AdminScreen(),
      ];
    }
    return [
      CalendarScreen(key: _calendarKey),
      ChatListScreen(key: _chatListKey),
      NotificationsScreen(key: const ValueKey('notifications'), onRefreshed: _loadPendingCount),
      const ProfileScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    final notifDestination = NavigationDestination(
      icon: Badge(
        isLabelVisible: _pendingCount > 0,
        label: Text('$_pendingCount'),
        child: const Icon(Icons.notifications_outlined),
      ),
      selectedIcon: Badge(
        isLabelVisible: _pendingCount > 0,
        label: Text('$_pendingCount'),
        child: const Icon(Icons.notifications),
      ),
      label: '通知',
    );

    return Scaffold(
      body: UpgradeAlert(
        upgrader: Upgrader(
          messages: _JaUpgraderMessages(),
          storeController: UpgraderStoreController(
            oniOS: () => _IosUpgraderStore(),
          ),
        ),
        dialogStyle: UpgradeDialogStyle.cupertino,
        barrierDismissible: false,
        showIgnore: false,
        showLater: false,
        child: IndexedStack(index: _currentIndex, children: _screens),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          if (index == 0) _calendarKey.currentState?.loadSlots();
          if (index == 1) { _loadChatUnread(); _chatListKey.currentState?.loadRooms(); }
          if (index == 2) _loadPendingCount();
        },
        destinations: auth.isAdmin
            ? [
                const NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                  label: '出店カレンダー',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: _chatUnreadCount > 0,
                    label: Text('$_chatUnreadCount'),
                    child: const Icon(Icons.chat_bubble_outline),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: _chatUnreadCount > 0,
                    label: Text('$_chatUnreadCount'),
                    child: const Icon(Icons.chat_bubble),
                  ),
                  label: 'チャット',
                ),
                notifDestination,
                const NavigationDestination(
                  icon: Icon(Icons.admin_panel_settings_outlined),
                  selectedIcon: Icon(Icons.admin_panel_settings),
                  label: '管理',
                ),
              ]
            : [
                const NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                  label: '出店カレンダー',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: _chatUnreadCount > 0,
                    label: Text('$_chatUnreadCount'),
                    child: const Icon(Icons.chat_bubble_outline),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: _chatUnreadCount > 0,
                    label: Text('$_chatUnreadCount'),
                    child: const Icon(Icons.chat_bubble),
                  ),
                  label: 'チャット',
                ),
                notifDestination,
                const NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'プロフィール',
                ),
              ],
      ),
    );
  }
}

