class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.target,
    required this.extraData,
    required this.createdAt,
    required this.expiresAt,
    required this.readAt,
    required this.isRead,
  });

  final int id;
  final String title;
  final String body;
  final String target;
  final Map<String, dynamic> extraData;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? readAt;
  final bool isRead;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final rawExtra = json['extra_data'];
    return AppNotification(
      id: json['id'] as int? ?? 0,
      title: (json['title'] ?? 'ApprofittOffro').toString(),
      body: (json['body'] ?? '').toString(),
      target: (json['target'] ?? 'notifications').toString(),
      extraData: rawExtra is Map<String, dynamic>
          ? rawExtra
          : const <String, dynamic>{},
      createdAt: _parseDate(json['created_at']),
      expiresAt: _parseDate(json['expires_at']),
      readAt: _parseDate(json['read_at']),
      isRead: json['is_read'] == true,
    );
  }

  static DateTime? _parseDate(Object? value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }
}
