import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class RecordingService {
  RecordingService({
    AudioRecorder? recorder,
  }) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  Future<void> start({
    required String songId,
    required int slotIndex,
  }) async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw const RecordingException(
        'Microphone permission is required to record.',
      );
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final recordingsDirectory = Directory(
      path.join(supportDirectory.path, 'recordings', songId),
    );
    await recordingsDirectory.create(recursive: true);

    final outputPath = path.join(
      recordingsDirectory.path,
      'slot_${slotIndex}_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 48000,
        bitRate: 192000,
        numChannels: 1,
      ),
      path: outputPath,
    );
  }

  Future<String?> stop() => _recorder.stop();

  Future<void> cancel() => _recorder.cancel();

  Future<bool> get isRecording => _recorder.isRecording();
}

class RecordingException implements Exception {
  const RecordingException(this.message);

  final String message;

  @override
  String toString() => message;
}
