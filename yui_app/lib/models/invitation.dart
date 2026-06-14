class Invitation {
  final String id;
  final String slotId;
  final String status; // pending / accepted / declined
  final String? message;
  final String? responseMessage;
  final String createdAt;

  // 相手の情報（受信=発起人 / 送信=招待相手）
  final String? counterpartId; // inviter_id または invitee_id
  final String? shopName;
  final String? avatarUrl;

  // 枠情報
  final String? slotDate;
  final String? slotName;
  final String? startTime;
  final String? endTime;
  final String? description;

  const Invitation({
    required this.id,
    required this.slotId,
    required this.status,
    this.message,
    this.responseMessage,
    required this.createdAt,
    this.counterpartId,
    this.shopName,
    this.avatarUrl,
    this.slotDate,
    this.slotName,
    this.startTime,
    this.endTime,
    this.description,
  });

  factory Invitation.fromJson(Map<String, dynamic> json) => Invitation(
    id: json['id'] as String,
    slotId: json['slot_id'] as String,
    status: json['status'] as String,
    message: json['message'] as String?,
    responseMessage: json['response_message'] as String?,
    createdAt: json['created_at'] as String,
    // incoming は inviter_id、outgoing は invitee_id が来る
    counterpartId: (json['inviter_id'] ?? json['invitee_id']) as String?,
    shopName: json['shop_name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    slotDate: json['date'] as String?,
    slotName: json['slot_name'] as String?,
    startTime: json['start_time'] as String?,
    endTime: json['end_time'] as String?,
    description: json['description'] as String?,
  );
}

class InvitableUser {
  final String id;
  final String? shopName;
  final String? avatarUrl;
  final String? category;
  final bool alreadyInvited;

  const InvitableUser({
    required this.id,
    this.shopName,
    this.avatarUrl,
    this.category,
    required this.alreadyInvited,
  });

  factory InvitableUser.fromJson(Map<String, dynamic> json) => InvitableUser(
    id: json['id'] as String,
    shopName: json['shop_name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    category: json['category'] as String?,
    alreadyInvited: (json['already_invited'] as int? ?? 0) == 1,
  );
}
