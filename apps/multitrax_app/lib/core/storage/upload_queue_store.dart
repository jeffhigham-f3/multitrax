import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PendingUpload {
  static String _legacySubmissionIdFallback(
    String songId,
    String trackSlotId,
    String localFilePath,
  ) {
    final entropy = DateTime.now().microsecondsSinceEpoch;
    return '${songId}_${trackSlotId}_${localFilePath.hashCode}_$entropy';
  }

  PendingUpload({
    required this.songId,
    required this.trackSlotId,
    required this.localFilePath,
    required this.submissionId,
    this.basedOnMixVersionId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  final String songId;
  final String trackSlotId;
  final String localFilePath;
  final String submissionId;
  final String? basedOnMixVersionId;
  final DateTime createdAt;

  factory PendingUpload.fromJson(Map<String, dynamic> json) {
    return PendingUpload(
      songId: json['songId'] as String,
      trackSlotId: json['trackSlotId'] as String,
      localFilePath: json['localFilePath'] as String,
      submissionId: (json['submissionId'] as String?) ??
          _legacySubmissionIdFallback(
            json['songId'] as String,
            json['trackSlotId'] as String,
            json['localFilePath'] as String,
          ),
      basedOnMixVersionId: json['basedOnMixVersionId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'songId': songId,
        'trackSlotId': trackSlotId,
        'localFilePath': localFilePath,
        'submissionId': submissionId,
        'basedOnMixVersionId': basedOnMixVersionId,
        'createdAt': createdAt.toIso8601String(),
      };
}

class UploadQueueStore {
  UploadQueueStore({
    SharedPreferences? preferences,
  }) : _preferencesFuture =
            preferences != null ? Future.value(preferences) : SharedPreferences.getInstance();

  static const _queueKey = 'pending_upload_queue_v1';

  final Future<SharedPreferences> _preferencesFuture;

  Future<List<PendingUpload>> readAll() async {
    final preferences = await _preferencesFuture;
    final raw = preferences.getStringList(_queueKey);
    if (raw == null || raw.isEmpty) return const [];

    return raw
        .map((item) => PendingUpload.fromJson(jsonDecode(item) as Map<String, dynamic>))
        .toList();
  }

  Future<void> enqueue(PendingUpload item) async {
    final current = await readAll();
    current.add(item);
    await replaceAll(current);
  }

  Future<void> replaceAll(List<PendingUpload> items) async {
    final preferences = await _preferencesFuture;
    final payload = items.map((item) => jsonEncode(item.toJson())).toList();
    await preferences.setStringList(_queueKey, payload);
  }

  Future<int> size() async => (await readAll()).length;
}
