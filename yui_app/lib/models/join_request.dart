class JoinRequest {
  final String id;
  final String slotId;
  final String status; // pending / approved / rejected
  final String? message;
  final String? responseMessage;
  final String createdAt;

  // 受信一覧・枠別一覧で使う申請者情報
  final String? requesterId;
  final String? shopName;
  final String? avatarUrl;
  final String? email;

  // 送信一覧・受信一覧で使う枠情報
  final String? slotDate;
  final String? slotName;
  final String? startTime;
  final String? endTime;
  final String? description;

  const JoinRequest({
    required this.id,
    required this.slotId,
    required this.status,
    this.message,
    this.responseMessage,
    required this.createdAt,
    this.requesterId,
    this.shopName,
    this.avatarUrl,
    this.email,
    this.slotDate,
    this.slotName,
    this.startTime,
    this.endTime,
    this.description,
  });

  factory JoinRequest.fromJson(Map<String, dynamic> json) => JoinRequest(
    id: json['id'] as String,
    slotId: json['slot_id'] as String,
    status: json['status'] as String,
    message: json['message'] as String?,
    responseMessage: json['response_message'] as String?,
    createdAt: json['created_at'] as String,
    requesterId: json['requester_id'] as String?,
    shopName: json['shop_name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    email: json['email'] as String?,
    slotDate: json['date'] as String?,
    slotName: json['slot_name'] as String?,
    startTime: json['start_time'] as String?,
    endTime: json['end_time'] as String?,
    description: json['description'] as String?,
  );
}
