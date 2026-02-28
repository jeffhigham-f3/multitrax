class WaveformData {
  const WaveformData({
    required this.id,
    required this.durationMs,
    required this.samples,
  });

  final String id;
  final int durationMs;
  final List<double> samples;

  Duration get duration => Duration(milliseconds: durationMs);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'durationMs': durationMs,
      'samples': samples,
    };
  }

  factory WaveformData.fromJson(Map<String, dynamic> json) {
    return WaveformData(
      id: json['id'] as String,
      durationMs: json['durationMs'] as int,
      samples: (json['samples'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(),
    );
  }
}
