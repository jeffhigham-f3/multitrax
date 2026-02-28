class SongSummary {
  SongSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    this.currentMixVersionId,
    this.currentMixPath,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final String? currentMixVersionId;
  final String? currentMixPath;

  SongSummary copyWith({
    String? currentMixVersionId,
    String? currentMixPath,
  }) {
    return SongSummary(
      id: id,
      title: title,
      createdAt: createdAt,
      currentMixVersionId: currentMixVersionId ?? this.currentMixVersionId,
      currentMixPath: currentMixPath ?? this.currentMixPath,
    );
  }

  factory SongSummary.fromMap(Map<String, dynamic> map) {
    return SongSummary(
      id: map['id'] as String,
      title: (map['title'] as String?) ?? 'Untitled Song',
      createdAt: DateTime.tryParse((map['created_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      currentMixVersionId: map['current_mix_version_id'] as String?,
      currentMixPath: map['current_mix_path'] as String?,
    );
  }

  factory SongSummary.fromJson(Map<String, dynamic> json) => SongSummary(
        id: json['id'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        currentMixVersionId: json['currentMixVersionId'] as String?,
        currentMixPath: json['currentMixPath'] as String?,
      );

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'currentMixVersionId': currentMixVersionId,
      'currentMixPath': currentMixPath,
    };
  }
}

class SongMember {
  SongMember({
    required this.userId,
    required this.role,
  });

  final String userId;
  final String role;

  factory SongMember.fromMap(Map<String, dynamic> map) {
    return SongMember(
      userId: map['user_id'] as String,
      role: (map['role'] as String?) ?? 'listener',
    );
  }

  factory SongMember.fromJson(Map<String, dynamic> json) => SongMember(
        userId: json['userId'] as String,
        role: json['role'] as String,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'role': role,
      };
}

class TrackSlot {
  TrackSlot({
    required this.id,
    required this.slotIndex,
    required this.label,
    this.assignedUserId,
    this.currentTakeId,
    this.currentTakeFilePath,
  });

  final String id;
  final int slotIndex;
  final String label;
  final String? assignedUserId;
  final String? currentTakeId;
  final String? currentTakeFilePath;

  factory TrackSlot.fromMap(Map<String, dynamic> map) {
    return TrackSlot(
      id: map['id'] as String,
      slotIndex: map['slot_index'] as int? ?? 0,
      label: (map['label'] as String?) ?? 'Track',
      assignedUserId: map['assigned_user_id'] as String?,
      currentTakeId: map['current_take_id'] as String?,
      currentTakeFilePath: map['current_take_file_path'] as String?,
    );
  }

  factory TrackSlot.fromJson(Map<String, dynamic> json) => TrackSlot(
        id: json['id'] as String,
        slotIndex: json['slotIndex'] as int,
        label: json['label'] as String,
        assignedUserId: json['assignedUserId'] as String?,
        currentTakeId: json['currentTakeId'] as String?,
        currentTakeFilePath: json['currentTakeFilePath'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'slotIndex': slotIndex,
        'label': label,
        'assignedUserId': assignedUserId,
        'currentTakeId': currentTakeId,
        'currentTakeFilePath': currentTakeFilePath,
      };
}

class RenderJob {
  RenderJob({
    required this.id,
    required this.status,
    required this.createdAt,
    this.errorText,
  });

  final String id;
  final String status;
  final DateTime createdAt;
  final String? errorText;

  factory RenderJob.fromMap(Map<String, dynamic> map) {
    return RenderJob(
      id: map['id'] as String,
      status: (map['status'] as String?) ?? 'pending',
      createdAt: DateTime.tryParse((map['created_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      errorText: map['error_text'] as String?,
    );
  }

  factory RenderJob.fromJson(Map<String, dynamic> json) => RenderJob(
        id: json['id'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        errorText: json['errorText'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'errorText': errorText,
      };
}

class ExportJob {
  ExportJob({
    required this.id,
    required this.outputFormat,
    required this.status,
    required this.createdAt,
    this.outputFilePath,
    this.errorText,
  });

  final String id;
  final String outputFormat;
  final String status;
  final DateTime createdAt;
  final String? outputFilePath;
  final String? errorText;

  factory ExportJob.fromMap(Map<String, dynamic> map) {
    return ExportJob(
      id: map['id'] as String,
      outputFormat: (map['output_format'] as String?) ?? 'mp3',
      status: (map['status'] as String?) ?? 'pending',
      createdAt: DateTime.tryParse((map['created_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      outputFilePath: map['output_file_path'] as String?,
      errorText: map['error_text'] as String?,
    );
  }

  factory ExportJob.fromJson(Map<String, dynamic> json) => ExportJob(
        id: json['id'] as String,
        outputFormat: json['outputFormat'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        outputFilePath: json['outputFilePath'] as String?,
        errorText: json['errorText'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'outputFormat': outputFormat,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'outputFilePath': outputFilePath,
        'errorText': errorText,
      };
}

class SongDetail {
  SongDetail({
    required this.song,
    required this.trackSlots,
    required this.members,
    required this.renderJobs,
    required this.exportJobs,
    this.localMixPath,
  });

  final SongSummary song;
  final List<TrackSlot> trackSlots;
  final List<SongMember> members;
  final List<RenderJob> renderJobs;
  final List<ExportJob> exportJobs;
  final String? localMixPath;

  SongDetail copyWith({
    SongSummary? song,
    List<TrackSlot>? trackSlots,
    List<SongMember>? members,
    List<RenderJob>? renderJobs,
    List<ExportJob>? exportJobs,
    String? localMixPath,
  }) {
    return SongDetail(
      song: song ?? this.song,
      trackSlots: trackSlots ?? this.trackSlots,
      members: members ?? this.members,
      renderJobs: renderJobs ?? this.renderJobs,
      exportJobs: exportJobs ?? this.exportJobs,
      localMixPath: localMixPath ?? this.localMixPath,
    );
  }

  factory SongDetail.fromJson(Map<String, dynamic> json) => SongDetail(
        song: SongSummary.fromJson(json['song'] as Map<String, dynamic>),
        trackSlots: (json['trackSlots'] as List<dynamic>)
            .map((e) => TrackSlot.fromJson(e as Map<String, dynamic>))
            .toList(),
        members: (json['members'] as List<dynamic>)
            .map((e) => SongMember.fromJson(e as Map<String, dynamic>))
            .toList(),
        renderJobs: (json['renderJobs'] as List<dynamic>)
            .map((e) => RenderJob.fromJson(e as Map<String, dynamic>))
            .toList(),
        exportJobs: (json['exportJobs'] as List<dynamic>)
            .map((e) => ExportJob.fromJson(e as Map<String, dynamic>))
            .toList(),
        localMixPath: json['localMixPath'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'song': song.toJson(),
        'trackSlots': trackSlots.map((e) => e.toJson()).toList(),
        'members': members.map((e) => e.toJson()).toList(),
        'renderJobs': renderJobs.map((e) => e.toJson()).toList(),
        'exportJobs': exportJobs.map((e) => e.toJson()).toList(),
        'localMixPath': localMixPath,
      };
}
