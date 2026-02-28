import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:multitrax_app/core/storage/song_cache_store.dart';
import 'package:multitrax_app/core/storage/upload_queue_store.dart';
import 'package:multitrax_app/songs/models/song_models.dart';
import 'package:multitrax_app/songs/repositories/song_repository.dart';

class SupabaseSongRepository implements SongRepository {
  SupabaseSongRepository({
    required SupabaseClient client,
    required SongCacheStore cacheStore,
    required UploadQueueStore uploadQueueStore,
    Uuid? uuid,
  })  : _client = client,
        _cacheStore = cacheStore,
        _uploadQueueStore = uploadQueueStore,
        _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final SongCacheStore _cacheStore;
  final UploadQueueStore _uploadQueueStore;
  final Uuid _uuid;

  String get _currentUserId {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('User must be authenticated.');
    }
    return userId;
  }

  @override
  Future<List<SongSummary>> fetchSongs({
    required int page,
    int pageSize = 20,
  }) async {
    final from = page * pageSize;
    final to = from + pageSize - 1;

    try {
      final raw = await _client
          .from('songs')
          .select('id,title,created_at,current_mix_version_id')
          .order('created_at', ascending: false)
          .range(from, to);

      final rows = List<Map<String, dynamic>>.from(raw as List<dynamic>);
      final songs = <SongSummary>[];
      for (final row in rows) {
        final mixVersionId = row['current_mix_version_id'] as String?;
        final mixPath = mixVersionId == null ? null : await _fetchMixPath(mixVersionId);
        songs.add(
          SongSummary.fromMap({
            ...row,
            'current_mix_path': mixPath,
          }),
        );
      }

      if (page == 0) {
        await _cacheStore.saveSongList(songs);
      }
      return songs;
    } catch (_) {
      if (page == 0) {
        return _cacheStore.readSongList();
      }
      rethrow;
    }
  }

  @override
  Future<SongDetail> fetchSongDetail(String songId) async {
    try {
      final songRow = Map<String, dynamic>.from(
        await _client
            .from('songs')
            .select('id,title,created_at,current_mix_version_id')
            .eq('id', songId)
            .single() as Map,
      );
      final currentMixVersionId = songRow['current_mix_version_id'] as String?;
      final currentMixPath = currentMixVersionId == null
          ? null
          : await _fetchMixPath(currentMixVersionId);

      final trackRows = List<Map<String, dynamic>>.from(
        await _client
            .from('track_slots')
            .select('id,slot_index,label,assigned_user_id,current_take_id')
            .eq('song_id', songId)
            .order('slot_index', ascending: true) as List<dynamic>,
      );

      final takeIds = trackRows
          .map((row) => row['current_take_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final takePathById = <String, String>{};
      if (takeIds.isNotEmpty) {
        final takeRows = List<Map<String, dynamic>>.from(
          await _client
              .from('takes')
              .select('id,file_path')
              .inFilter('id', takeIds) as List<dynamic>,
        );
        for (final takeRow in takeRows) {
          final takeId = takeRow['id'] as String?;
          final filePath = takeRow['file_path'] as String?;
          if (takeId != null && filePath != null) {
            takePathById[takeId] = filePath;
          }
        }
      }
      final normalizedTrackRows = trackRows
          .map((row) {
            final currentTakeId = row['current_take_id'] as String?;
            return {
              ...row,
              'current_take_file_path':
                  currentTakeId == null ? null : takePathById[currentTakeId],
            };
          })
          .toList()
        ..sort(
          (a, b) =>
              (a['slot_index'] as int? ?? 0).compareTo(b['slot_index'] as int? ?? 0),
        );

      final memberRows = List<Map<String, dynamic>>.from(
        await _client
            .from('song_members')
            .select('user_id,role')
            .eq('song_id', songId)
            .order('created_at') as List<dynamic>,
      );

      final renderRows = List<Map<String, dynamic>>.from(
        await _client
            .from('render_jobs')
            .select('id,status,error_text,created_at')
            .eq('song_id', songId)
            .order('created_at', ascending: false)
            .limit(25) as List<dynamic>,
      );

      final exportRows = List<Map<String, dynamic>>.from(
        await _client
            .from('export_jobs')
            .select('id,output_format,status,output_file_path,error_text,created_at')
            .eq('song_id', songId)
            .order('created_at', ascending: false)
            .limit(25) as List<dynamic>,
      );

      final detail = SongDetail(
        song: SongSummary.fromMap({
          ...songRow,
          'current_mix_path': currentMixPath,
        }),
        trackSlots: normalizedTrackRows.map(TrackSlot.fromMap).toList(),
        members: memberRows.map(SongMember.fromMap).toList(),
        renderJobs: renderRows.map(RenderJob.fromMap).toList(),
        exportJobs: exportRows.map(ExportJob.fromMap).toList(),
      );

      await _cacheStore.saveSongDetail(detail);
      return detail;
    } catch (_) {
      final cached = await _cacheStore.readSongDetail(songId);
      if (cached != null) return cached;
      rethrow;
    }
  }

  @override
  Future<void> createSong(String title) async {
    await _client.from('songs').insert({
      'title': title.trim(),
      'created_by': _currentUserId,
    });
  }

  @override
  Future<void> addMemberByEmail({
    required String songId,
    required String email,
    String role = 'editor',
  }) async {
    await _client.rpc<dynamic>(
      'add_song_member_by_email',
      params: {
        'p_song_id': songId,
        'p_member_email': email.trim(),
        'p_role': role,
      },
    );
  }

  @override
  Future<void> queueRenderJob(String songId) async {
    await _client.from('render_jobs').insert({
      'song_id': songId,
      'requested_by': _currentUserId,
      'status': 'pending',
      'payload': <String, dynamic>{},
    });
  }

  @override
  Future<void> queueExportJob({
    required String songId,
    required String outputFormat,
  }) async {
    await _client.from('export_jobs').insert({
      'song_id': songId,
      'requested_by': _currentUserId,
      'output_format': outputFormat,
      'status': 'pending',
    });
  }

  @override
  Future<TakeSubmissionResult> submitTake({
    required String songId,
    required String trackSlotId,
    required String localFilePath,
    String? basedOnMixVersionId,
  }) async {
    final pendingUpload = PendingUpload(
      songId: songId,
      trackSlotId: trackSlotId,
      localFilePath: localFilePath,
      submissionId: _uuid.v4(),
      basedOnMixVersionId: basedOnMixVersionId,
    );

    try {
      await _submitPendingUpload(pendingUpload);
      return TakeSubmissionResult(queuedForRetry: false);
    } catch (error) {
      if (isRetriableSubmissionError(error)) {
        await _uploadQueueStore.enqueue(pendingUpload);
        return TakeSubmissionResult(queuedForRetry: true);
      }
      rethrow;
    }
  }

  @override
  Future<void> flushPendingUploads() async {
    final queue = await _uploadQueueStore.readAll();
    if (queue.isEmpty) return;

    final remaining = <PendingUpload>[];
    var consecutiveFailures = 0;
    for (final item in queue) {
      try {
        await _submitPendingUpload(item);
        consecutiveFailures = 0;
      } catch (error) {
        if (isRetriableSubmissionError(error)) {
          consecutiveFailures += 1;
          remaining.add(item);
          await Future<void>.delayed(_backoffDuration(consecutiveFailures));
        }
      }
    }

    await _uploadQueueStore.replaceAll(remaining);
  }

  @override
  Future<List<PendingUpload>> pendingUploads() {
    return _uploadQueueStore.readAll();
  }

  @override
  Future<String?> syncLatestMix({
    required String songId,
    String? mixPath,
  }) async {
    if (mixPath == null || mixPath.isEmpty) return null;
    return _cacheStore.downloadAndCacheMix(songId: songId, mixPath: mixPath);
  }

  @override
  Future<String> cacheTakeForPlayback({
    required String songId,
    required String takePath,
  }) {
    return _cacheStore.downloadAndCacheTake(songId: songId, takePath: takePath);
  }

  Future<void> _submitPendingUpload(PendingUpload pendingUpload) async {
    final file = File(pendingUpload.localFilePath);
    if (!file.existsSync()) {
      throw StateError('Recording file no longer exists: ${pendingUpload.localFilePath}');
    }

    final extension = path.extension(file.path).replaceFirst('.', '').toLowerCase();
    final normalizedExtension = extension.isEmpty ? 'm4a' : extension;
    final objectPath =
        '${pendingUpload.songId}/takes/${pendingUpload.submissionId}.$normalizedExtension';

    await _client.storage.from('takes').upload(
          objectPath,
          file,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _contentTypeForExtension(normalizedExtension),
          ),
        );

    await _client.rpc<dynamic>(
      'submit_take_and_enqueue_render',
      params: {
        'p_song_id': pendingUpload.songId,
        'p_track_slot_id': pendingUpload.trackSlotId,
        'p_file_path': objectPath,
        'p_based_on_mix_version_id': pendingUpload.basedOnMixVersionId,
        'p_submission_id': pendingUpload.submissionId,
      },
    );
  }

  Future<String?> _fetchMixPath(String mixVersionId) async {
    final mix = await _client
        .from('mix_versions')
        .select('file_path')
        .eq('id', mixVersionId)
        .maybeSingle();
    if (mix == null) return null;
    final mixMap = Map<String, dynamic>.from(mix as Map);
    return mixMap['file_path'] as String?;
  }

  String _contentTypeForExtension(String extension) {
    switch (extension) {
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
      case 'aac':
        return 'audio/mp4';
      default:
        return 'application/octet-stream';
    }
  }

  Duration _backoffDuration(int attempt) {
    final clampedAttempt = attempt > 5 ? 5 : attempt;
    final milliseconds = 200 * (1 << (clampedAttempt - 1));
    return Duration(milliseconds: milliseconds);
  }
}

bool isRetriableSubmissionError(Object error) {
  if (error is TimeoutException || error is SocketException) {
    return true;
  }

  if (error is StorageException) {
    final statusCode = int.tryParse(error.statusCode ?? '');
    if (statusCode == null) {
      return true;
    }
    return statusCode == 408 || statusCode == 425 || statusCode == 429 || statusCode >= 500;
  }

  if (error is PostgrestException) {
    final code = error.code ?? '';
    return code.startsWith('08');
  }

  return false;
}
