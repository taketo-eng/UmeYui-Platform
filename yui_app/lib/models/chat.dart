class ChatMember {
  final String id;
  final String? shopName;
  final String? avatarUrl;
  final bool isInitiator;

  const ChatMember({
    required this.id,
    this.shopName,
    this.avatarUrl,
    this.isInitiator = false,
  });

  factory ChatMember.fromJson(Map<String, dynamic> json) => ChatMember(
    id: json['id'] as String,
    shopName: json['shop_name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    isInitiator: (json['is_initiator'] as int? ?? 0) == 1,
  );
}

class ChatRoom {
  final String roomId;
  final String slotId;
  final String date;
  final String? slotName;
  final String? startTime;
  final String? endTime;
  final int? minVendors;
  final int? maxVendors;
  final List<ChatMember> members;
  final String? lastMessageBody;
  final String? lastMessageAt;
  final int unreadCount;

  const ChatRoom({
    required this.roomId,
    required this.slotId,
    required this.date,
    this.slotName,
    this.startTime,
    this.endTime,
    this.minVendors,
    this.maxVendors,
    this.members = const [],
    this.lastMessageBody,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) => ChatRoom(
    roomId: json['room_id'] as String,
    slotId: json['slot_id'] as String,
    date: json['date'] as String,
    slotName: json['slot_name'] as String?,
    startTime: json['start_time'] as String?,
    endTime: json['end_time'] as String?,
    minVendors: json['min_vendors'] as int?,
    maxVendors: json['max_vendors'] as int?,
    members:
        (json['members'] as List<dynamic>?)
            ?.map((m) => ChatMember.fromJson(m as Map<String, dynamic>))
            .toList() ??
        [],
    lastMessageBody: json['last_message_body'] as String?,
    lastMessageAt: json['last_message_at'] as String?,
    unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
  );

  String get displayTitle => slotName ?? date;
}
