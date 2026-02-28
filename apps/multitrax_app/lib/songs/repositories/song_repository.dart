import 'package:multitrax_app/core/storage/upload_queue_store.dart';
import 'package:multitrax_app/songs/models/song_models.dart';

class TakeSubmissionResult {
  TakeSubmissionResult({
    required this.queuedForRetry,
  });

  final bool queuedForRetry;
}

abstract class SongRepository {
  Future<List<SongSummary>> fetchSongs({
    required int page,
    int pageSize = 20,
  });

  Future<SongDetail> fetchSongDetail(String songId);

  Future<void> createSong(String title);

  Future<void> addMemberByEmail({
    required String songId,
    required String email,
    String role = 'editor',
  });

  Future<void> queueRenderJob(String songId);

  Future<void> queueExportJob({
    required String songId,
    required String outputFormat,
  });

  Future<TakeSubmissionResult> submitTake({
    required String songId,
    required String trackSlotId,
    required String localFilePath,
    String? basedOnMixVersionId,
  });

  Future<void> flushPendingUploads();

  Future<List<PendingUpload>> pendingUploads();

  Future<String?> syncLatestMix({
    required String songId,
    String? mixPath,
  });

  Future<String> cacheTakeForPlayback({
    required String songId,
    required String takePath,
  });
}
