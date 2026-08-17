enum CallDirection { outgoing, incoming }

class CallHistoryRecord {
  const CallHistoryRecord({
    required this.id,
    required this.peerNumber,
    required this.direction,
    required this.status,
    required this.createdAt,
    this.answeredAt,
    this.endedAt,
  });

  final String id;
  final String peerNumber;
  final CallDirection direction;
  final String status; // ringing | accepted | declined | missed | ended
  final DateTime createdAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;

  int get durationSeconds {
    if (answeredAt == null) return 0;
    final end = endedAt ?? DateTime.now();
    return end.difference(answeredAt!).inSeconds.clamp(0, 1 << 30);
  }

  factory CallHistoryRecord.fromMap(Map<String, dynamic> map, String myUserId) {
    final isOutgoing = map['caller_id'] == myUserId;
    return CallHistoryRecord(
      id: map['id'] as String,
      peerNumber: isOutgoing
          ? map['callee_number'] as String
          : map['caller_number'] as String,
      direction: isOutgoing ? CallDirection.outgoing : CallDirection.incoming,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      answeredAt: map['answered_at'] != null
          ? DateTime.parse(map['answered_at'] as String)
          : null,
      endedAt: map['ended_at'] != null
          ? DateTime.parse(map['ended_at'] as String)
          : null,
    );
  }
}
