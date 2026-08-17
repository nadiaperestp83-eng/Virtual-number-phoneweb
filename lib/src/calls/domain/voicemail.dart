class Voicemail {
  const Voicemail({
    required this.id,
    required this.callerNumber,
    required this.callerName,
    required this.durationSeconds,
    required this.listened,
    required this.createdAt,
    required this.storagePath,
  });

  final String id;
  final String callerNumber;
  final String? callerName;
  final int durationSeconds;
  final bool listened;
  final DateTime createdAt;
  final String storagePath;

  factory Voicemail.fromMap(Map<String, dynamic> map) {
    return Voicemail(
      id: map['id'] as String,
      callerNumber: map['caller_number'] as String,
      callerName: map['caller_name'] as String?,
      durationSeconds: map['duration_seconds'] as int? ?? 0,
      listened: map['listened'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
      storagePath: map['storage_path'] as String,
    );
  }
}
