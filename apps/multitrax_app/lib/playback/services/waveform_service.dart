import 'dart:io';
import 'dart:math';

import 'package:just_waveform/just_waveform.dart';

import 'package:multitrax_app/core/storage/song_cache_store.dart';
import 'package:multitrax_app/playback/models/waveform_data.dart';

class WaveformService {
  WaveformService({
    required SongCacheStore cacheStore,
  }) : _cacheStore = cacheStore;

  final SongCacheStore _cacheStore;

  Future<WaveformData> loadTrackWaveform({
    required String songId,
    required String takeId,
    required String localAudioPath,
    int targetSampleCount = 300,
  }) async {
    final cached = await _cacheStore.readWaveformSamples(
      songId: songId,
      takeId: takeId,
    );
    if (cached != null) {
      return WaveformData.fromJson(cached);
    }

    final waveOutFile = await _cacheStore.waveformBinaryFile(
      songId: songId,
      takeId: takeId,
    );
    final waveform = await _extractWaveform(
      audioInFile: File(localAudioPath),
      waveOutFile: waveOutFile,
    );
    final samples = _sampleWaveform(
      waveform: waveform,
      targetSampleCount: targetSampleCount,
    );
    final data = WaveformData(
      id: takeId,
      durationMs: waveform.duration.inMilliseconds,
      samples: samples,
    );
    await _cacheStore.saveWaveformSamples(
      songId: songId,
      takeId: takeId,
      payload: data.toJson(),
    );
    return data;
  }

  Future<Waveform> _extractWaveform({
    required File audioInFile,
    required File waveOutFile,
  }) async {
    Waveform? waveform;
    final extractionStream = JustWaveform.extract(
      audioInFile: audioInFile,
      waveOutFile: waveOutFile,
      zoom: const WaveformZoom.pixelsPerSecond(120),
    );
    await for (final progress in extractionStream) {
      waveform = progress.waveform ?? waveform;
    }
    if (waveform == null) {
      throw StateError('Waveform extraction did not return data.');
    }
    return waveform;
  }

  List<double> _sampleWaveform({
    required Waveform waveform,
    required int targetSampleCount,
  }) {
    if (targetSampleCount <= 0) return const [];
    final duration = waveform.duration;
    if (duration == Duration.zero) {
      return List<double>.filled(targetSampleCount, 0);
    }

    final pixelCount = max(1, waveform.positionToPixel(duration).toInt());
    final totalSamples = max(8, min(pixelCount, targetSampleCount));
    final fullScale = waveform.flags == 0 ? 32768.0 : 128.0;

    final samples = <double>[];
    for (var i = 0; i < totalSamples; i++) {
      final ratio = totalSamples == 1 ? 0.0 : i / (totalSamples - 1);
      final pixelIndex = (ratio * (pixelCount - 1)).round();
      final minSample = waveform.getPixelMin(pixelIndex).abs().toDouble();
      final maxSample = waveform.getPixelMax(pixelIndex).abs().toDouble();
      final amplitude = max(minSample, maxSample) / fullScale;
      samples.add(amplitude.clamp(0.0, 1.0));
    }
    return samples;
  }
}
