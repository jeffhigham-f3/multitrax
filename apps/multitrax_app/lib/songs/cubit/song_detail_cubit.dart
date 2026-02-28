import 'dart:io';

import 'package:bloc/bloc.dart';

import 'package:multitrax_app/exports/export_service.dart';
import 'package:multitrax_app/recording/recording_service.dart';
import 'package:multitrax_app/songs/models/song_models.dart';
import 'package:multitrax_app/songs/repositories/song_repository.dart';
import 'package:multitrax_app/sync/song_sync_service.dart';

class SongDetailState {
  static const _unset = Object();

  const SongDetailState({
    this.detail,
    this.isLoading = false,
    this.isSyncing = false,
    this.isRecording = false,
    this.isSubmittingTake = false,
    this.pendingTrackSlotId,
    this.pendingSlotIndex,
    this.pendingRecordingPath,
    this.lastSubmitQueued = false,
    this.errorMessage,
  });

  final SongDetail? detail;
  final bool isLoading;
  final bool isSyncing;
  final bool isRecording;
  final bool isSubmittingTake;
  final String? pendingTrackSlotId;
  final int? pendingSlotIndex;
  final String? pendingRecordingPath;
  final bool lastSubmitQueued;
  final String? errorMessage;

  SongDetailState copyWith({
    Object? detail = _unset,
    bool? isLoading,
    bool? isSyncing,
    bool? isRecording,
    bool? isSubmittingTake,
    Object? pendingTrackSlotId = _unset,
    Object? pendingSlotIndex = _unset,
    Object? pendingRecordingPath = _unset,
    bool? lastSubmitQueued,
    Object? errorMessage = _unset,
  }) {
    return SongDetailState(
      detail: identical(detail, _unset) ? this.detail : detail as SongDetail?,
      isLoading: isLoading ?? this.isLoading,
      isSyncing: isSyncing ?? this.isSyncing,
      isRecording: isRecording ?? this.isRecording,
      isSubmittingTake: isSubmittingTake ?? this.isSubmittingTake,
      pendingTrackSlotId: identical(pendingTrackSlotId, _unset)
          ? this.pendingTrackSlotId
          : pendingTrackSlotId as String?,
      pendingSlotIndex: identical(pendingSlotIndex, _unset)
          ? this.pendingSlotIndex
          : pendingSlotIndex as int?,
      pendingRecordingPath: identical(pendingRecordingPath, _unset)
          ? this.pendingRecordingPath
          : pendingRecordingPath as String?,
      lastSubmitQueued: lastSubmitQueued ?? this.lastSubmitQueued,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class SongDetailCubit extends Cubit<SongDetailState> {
  SongDetailCubit({
    required String songId,
    required SongRepository songRepository,
    required SongSyncService songSyncService,
    required RecordingService recordingService,
    required ExportService exportService,
  })  : _songId = songId,
        _songRepository = songRepository,
        _songSyncService = songSyncService,
        _recordingService = recordingService,
        _exportService = exportService,
        super(const SongDetailState());

  final String _songId;
  final SongRepository _songRepository;
  final SongSyncService _songSyncService;
  final RecordingService _recordingService;
  final ExportService _exportService;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      final detail = await _songRepository.fetchSongDetail(_songId);
      emit(state.copyWith(detail: detail, isLoading: false));
    } catch (_) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load song details.',
        ),
      );
    }
  }

  Future<void> syncLatest() async {
    emit(state.copyWith(isSyncing: true, errorMessage: null));
    try {
      final detail = await _songSyncService.syncSongState(_songId);
      emit(state.copyWith(detail: detail, isSyncing: false));
    } catch (_) {
      emit(
        state.copyWith(
          isSyncing: false,
          errorMessage: 'Could not sync latest mix state.',
        ),
      );
    }
  }

  Future<void> addMemberByEmail(String email) async {
    emit(state.copyWith(errorMessage: null));
    try {
      await _songRepository.addMemberByEmail(songId: _songId, email: email);
      await load();
    } catch (_) {
      emit(state.copyWith(errorMessage: 'Failed to add member by email.'));
    }
  }

  Future<void> requestMp3Export() async {
    emit(state.copyWith(errorMessage: null));
    final mixVersionId = state.detail?.song.currentMixVersionId;
    if (mixVersionId == null || mixVersionId.isEmpty) {
      emit(
        state.copyWith(
          errorMessage:
              'Export unavailable: no rendered mix exists yet. Submit a take and wait for render completion.',
        ),
      );
      return;
    }
    try {
      await _exportService.requestMp3Export(_songId);
      await load();
    } catch (_) {
      emit(state.copyWith(errorMessage: 'Failed to queue MP3 export.'));
    }
  }

  Future<void> requestWavExport() async {
    emit(state.copyWith(errorMessage: null));
    final mixVersionId = state.detail?.song.currentMixVersionId;
    if (mixVersionId == null || mixVersionId.isEmpty) {
      emit(
        state.copyWith(
          errorMessage:
              'Export unavailable: no rendered mix exists yet. Submit a take and wait for render completion.',
        ),
      );
      return;
    }
    try {
      await _exportService.requestWavExport(_songId);
      await load();
    } catch (_) {
      emit(state.copyWith(errorMessage: 'Failed to queue WAV export.'));
    }
  }

  Future<void> retryQueuedUploads() async {
    emit(state.copyWith(errorMessage: null));
    try {
      await _songRepository.flushPendingUploads();
      await load();
    } catch (_) {
      emit(state.copyWith(errorMessage: 'Retry failed for queued uploads.'));
    }
  }

  Future<void> startRecording({
    required String trackSlotId,
    required int slotIndex,
  }) async {
    emit(
      state.copyWith(
        isRecording: true,
        pendingTrackSlotId: trackSlotId,
        pendingSlotIndex: slotIndex,
        pendingRecordingPath: null,
        errorMessage: null,
      ),
    );

    try {
      await _recordingService.start(songId: _songId, slotIndex: slotIndex);
    } catch (error) {
      emit(
        state.copyWith(
          isRecording: false,
          pendingTrackSlotId: null,
          pendingSlotIndex: null,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> stopRecording() async {
    try {
      final outputPath = await _recordingService.stop();
      if (outputPath == null || outputPath.isEmpty) {
        emit(
          state.copyWith(
            isRecording: false,
            errorMessage: 'No recording was captured.',
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          isRecording: false,
          pendingRecordingPath: outputPath,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isRecording: false,
          errorMessage: 'Could not stop recording.',
        ),
      );
    }
  }

  Future<void> redoRecording() async {
    final existing = state.pendingRecordingPath;
    if (existing != null) {
      final file = File(existing);
      if (file.existsSync()) {
        await file.delete();
      }
    }

    final trackSlotId = state.pendingTrackSlotId;
    final slotIndex = state.pendingSlotIndex;
    if (trackSlotId == null || slotIndex == null) {
      return;
    }
    await startRecording(trackSlotId: trackSlotId, slotIndex: slotIndex);
  }

  Future<void> submitRecording() async {
    final detail = state.detail;
    final recordingPath = state.pendingRecordingPath;
    final trackSlotId = state.pendingTrackSlotId;
    if (detail == null || recordingPath == null || trackSlotId == null) {
      return;
    }

    emit(state.copyWith(isSubmittingTake: true, errorMessage: null));
    try {
      final result = await _songRepository.submitTake(
        songId: _songId,
        trackSlotId: trackSlotId,
        localFilePath: recordingPath,
        basedOnMixVersionId: detail.song.currentMixVersionId,
      );

      emit(
        state.copyWith(
          isSubmittingTake: false,
          pendingRecordingPath: null,
          pendingTrackSlotId: null,
          pendingSlotIndex: null,
          lastSubmitQueued: result.queuedForRetry,
        ),
      );
      await syncLatest();
      await load();
    } catch (error) {
      emit(
        state.copyWith(
          isSubmittingTake: false,
          errorMessage: 'Failed to submit take: $error',
        ),
      );
    }
  }
}
