import 'dart:async';

import 'package:bloc/bloc.dart';

import 'package:multitrax_app/songs/models/song_models.dart';
import 'package:multitrax_app/songs/repositories/song_repository.dart';

class SongListState {
  static const _unset = Object();

  const SongListState({
    this.songs = const [],
    this.page = 0,
    this.isLoading = false,
    this.isFlushingUploads = false,
    this.hasReachedMax = false,
    this.errorMessage,
    this.pendingUploads = 0,
  });

  final List<SongSummary> songs;
  final int page;
  final bool isLoading;
  final bool isFlushingUploads;
  final bool hasReachedMax;
  final String? errorMessage;
  final int pendingUploads;

  SongListState copyWith({
    List<SongSummary>? songs,
    int? page,
    bool? isLoading,
    bool? isFlushingUploads,
    bool? hasReachedMax,
    Object? errorMessage = _unset,
    int? pendingUploads,
  }) {
    return SongListState(
      songs: songs ?? this.songs,
      page: page ?? this.page,
      isLoading: isLoading ?? this.isLoading,
      isFlushingUploads: isFlushingUploads ?? this.isFlushingUploads,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      pendingUploads: pendingUploads ?? this.pendingUploads,
    );
  }
}

class SongListCubit extends Cubit<SongListState> {
  SongListCubit({
    required SongRepository songRepository,
  })  : _songRepository = songRepository,
        super(const SongListState());

  final SongRepository _songRepository;

  static const _pageSize = 20;

  Future<void> initialize() async {
    await _loadPage(0, reset: true);
    await refreshPendingUploads();
    unawaited(_flushPendingUploadsInBackground());
  }

  Future<void> refresh() async {
    await _loadPage(0, reset: true);
    await refreshPendingUploads();
  }

  Future<void> fetchNextPage() async {
    if (state.isLoading || state.hasReachedMax) return;
    await _loadPage(state.page + 1);
  }

  Future<void> createSong(String title) async {
    await _songRepository.createSong(title);
    await refresh();
  }

  Future<void> refreshPendingUploads() async {
    final pending = await _songRepository.pendingUploads();
    emit(state.copyWith(pendingUploads: pending.length));
  }

  Future<void> _loadPage(
    int page, {
    bool reset = false,
  }) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));

    try {
      final songs = await _songRepository.fetchSongs(page: page, pageSize: _pageSize);
      emit(
        state.copyWith(
          songs: reset ? songs : [...state.songs, ...songs],
          page: page,
          isLoading: false,
          hasReachedMax: songs.length < _pageSize,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load songs.',
        ),
      );
    }
  }

  Future<void> _flushPendingUploadsInBackground() async {
    if (isClosed) return;
    emit(state.copyWith(isFlushingUploads: true));
    try {
      await _songRepository.flushPendingUploads();
      await refreshPendingUploads();
    } catch (_) {
      if (isClosed) return;
      emit(
        state.copyWith(
          isFlushingUploads: false,
          errorMessage: 'Some queued uploads still need retry.',
        ),
      );
      return;
    }

    if (isClosed) return;
    emit(state.copyWith(isFlushingUploads: false));
  }
}
