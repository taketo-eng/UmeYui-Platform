class Reservation {
  final String id;
  final String slotId;
  final String userId;
  final bool isInitiator;
  final String status;

  const Reservation({
    required this.id,
    required this.slotId,
    required this.userId,
    required this.isInitiator,
    required this.status,
  });

  factory Reservation.fromJson(Map<String, dynamic> json) => Reservation(
    id: json['id'] as String,
    slotId: json['slot_id'] as String,
    userId: json['user_id'] as String,
    isInitiator: (json['is_initiator'] as int) == 1,
    status: json['status'] as String,
  );
}
