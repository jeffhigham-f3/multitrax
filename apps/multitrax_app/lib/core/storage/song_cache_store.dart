import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:multitrax_app/songs/models/song_models.dart';

class SongCacheStore {
  SongCacheStore();

  Future<Directory> _baseDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final cacheDirectory = Directory(path.join(supportDirectory.path, 'song_cache'));
    if (!cacheDirectory.existsSync()) {
      await cacheDirectory.create(recursive: true);
    }
    return cacheDirectory;
  }

  Future<void> saveSongList(List<SongSummary> songs) async {
    final directory = await _baseDirectory();
    final file = File(path.join(directory.path, 'song_list.json'));
    await file.writeAsString(
      jsonEncode(songs.map((song) => song.toJson()).toList()),
      flush: true,
    );
  }

  Future<List<SongSummary>> readSongList() async {
    final directory = await _baseDirectory();
    final file = File(path.join(directory.path, 'song_list.json'));
    if (!file.existsSync()) return const [];

    final payload = jsonDecode(await file.readAsString()) as List<dynamic>;
    return payload
        .map((item) => SongSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveSongDetail(SongDetail detail) async {
    final directory = await _baseDirectory();
    final file = File(path.join(directory.path, '${detail.song.id}.json'));
    await file.writeAsString(jsonEncode(detail.toJson()), flush: true);
  }

  Future<SongDetail?> readSongDetail(String songId) async {
    final directory = await _baseDirectory();
    final file = File(path.join(directory.path, '$songId.json'));
    if (!file.existsSync()) return null;
    final payload = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return SongDetail.fromJson(payload);
  }

  Future<String?> downloadAndCacheMix({
    required String songId,
    required String mixPath,
  }) async {
    final file = await _mixCacheFile(songId: songId, mixPath: mixPath);
    if (file.existsSync()) return file.path;
    final bytes = await Supabase.instance.client.storage.from('mixes').download(mixPath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String> downloadAndCacheTake({
    required String songId,
    required String takePath,
  }) async {
    final file = await _takeCacheFile(songId: songId, takePath: takePath);
    if (file.existsSync()) return file.path;
    final bytes = await Supabase.instance.client.storage.from('takes').download(takePath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<File> waveformBinaryFile({
    required String songId,
    required String takeId,
  }) async {
    final directory = await _waveformsDirectory();
    return File(path.join(directory.path, '${songId}_$takeId.wave'));
  }

  Future<void> saveWaveformSamples({
    required String songId,
    required String takeId,
    required Map<String, dynamic> payload,
  }) async {
    final file = await _waveformJsonFile(songId: songId, takeId: takeId);
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<Map<String, dynamic>?> readWaveformSamples({
    required String songId,
    required String takeId,
  }) async {
    final file = await _waveformJsonFile(songId: songId, takeId: takeId);
    if (!file.existsSync()) return null;
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  Future<File> _mixCacheFile({
    required String songId,
    required String mixPath,
  }) async {
    final directory = await _baseDirectory();
    final extension = path.extension(mixPath).replaceFirst('.', '');
    final filename = extension.isEmpty ? 'latest_mix.wav' : 'latest_mix.$extension';
    return File(path.join(directory.path, '${songId}_$filename'));
  }

  Future<File> _takeCacheFile({
    required String songId,
    required String takePath,
  }) async {
    final directory = await _baseDirectory();
    final filename = path.basename(takePath);
    return File(path.join(directory.path, '${songId}_take_$filename'));
  }

  Future<Directory> _waveformsDirectory() async {
    final baseDirectory = await _baseDirectory();
    final directory = Directory(path.join(baseDirectory.path, 'waveforms'));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> _waveformJsonFile({
    required String songId,
    required String takeId,
  }) async {
    final directory = await _waveformsDirectory();
    return File(path.join(directory.path, '${songId}_$takeId.json'));
  }
}
