class AppNotification {
  final String id;
  final String type; // recruitment_started / request_approved / request_rejected
  final String? slotId;
  final String message;
  final bool isRead;
  final String createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    this.slotId,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: json['id'] as String,
    type: json['type'] as String,
    slotId: json['slot_id'] as String?,
    message: json['message'] as String,
    isRead: (json['is_read'] as int) == 1,
    createdAt: json['created_at'] as String,
  );
}
