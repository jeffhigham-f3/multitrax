import 'dart:async';
import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:just_audio/just_audio.dart';

import 'package:multitrax_app/playback/cubit/playback_state.dart';
import 'package:multitrax_app/playback/models/waveform_data.dart';
import 'package:multitrax_app/playback/services/waveform_service.dart';
import 'package:multitrax_app/songs/models/song_models.dart';
import 'package:multitrax_app/songs/repositories/song_repository.dart';

typedef AudioPlayerFactory = AudioPlayer Function();

class PlaybackCubit extends Cubit<PlaybackState> {
  PlaybackCubit({
    required String songId,
    required SongRepository songRepository,
    required WaveformService waveformService,
    AudioPlayerFactory? playerFactory,
    AudioPlayer? singlePlayer,
  }) : _songId = songId,
       _songRepository = songRepository,
       _waveformService = waveformService,
       _playerFactory = playerFactory ?? AudioPlayer.new,
       _singlePlayer = singlePlayer ?? (playerFactory ?? AudioPlayer.new)(),
       super(const PlaybackState()) {
    _bindSinglePlayerStreams();
  }

  final String _songId;
  final SongRepository _songRepository;
  final WaveformService _waveformService;
  final AudioPlayerFactory _playerFactory;
  final AudioPlayer _singlePlayer;
  final Map<String, AudioPlayer> _trackPlayers = <String, AudioPlayer>{};
  final Map<String, String> _trackPlayerPaths = <String, String>{};
  final Map<String, List<StreamSubscription<dynamic>>> _trackPlayerSubscriptions =
      <String, List<StreamSubscription<dynamic>>>{};

  final List<AudioPlayer> _allPlayers = <AudioPlayer>[];
  final List<StreamSubscription<dynamic>> _allPlayerSubscriptions =
      <StreamSubscription<dynamic>>[];

  StreamSubscription<Duration>? _singlePositionSubscription;
  StreamSubscription<Duration?>? _singleDurationSubscription;
  StreamSubscription<PlayerState>? _singlePlayerStateSubscription;

  bool _initializedSelection = false;

  void _bindSinglePlayerStreams() {
    _singlePositionSubscription = _singlePlayer.positionStream.listen((
      position,
    ) {
      if (isClosed) return;
      emit(state.copyWith(singlePosition: position));
    });

    _singleDurationSubscription = _singlePlayer.durationStream.listen((
      duration,
    ) {
      if (isClosed) return;
      emit(state.copyWith(singleDuration: duration));
    });

    _singlePlayerStateSubscription = _singlePlayer.playerStateStream.listen((
      playerState,
    ) {
      if (isClosed) return;
      final hasCompleted =
          playerState.processingState == ProcessingState.completed;
      final isPlaying = playerState.playing && !hasCompleted;

      if (hasCompleted) {
        emit(
          state.copyWith(
            isSinglePlaying: false,
            isPlayingMix: false,
            clearActiveTrackSlotId: true,
            singlePosition: state.singleDuration ?? state.singlePosition,
          ),
        );
        return;
      }

      if (isPlaying != state.isSinglePlaying) {
        emit(state.copyWith(isSinglePlaying: isPlaying));
      }
    });
  }

  Future<void> hydrateFromSongDetail(SongDetail detail) async {
    final submittedTrackSlots = detail.trackSlots
        .where(
          (slot) =>
              slot.currentTakeId != null &&
              (slot.currentTakeFilePath ?? '').isNotEmpty,
        )
        .toList();
    final availableTrackIds = submittedTrackSlots
        .map((slot) => slot.id)
        .toSet();

    Set<String> selectedTrackIds;
    if (!_initializedSelection) {
      selectedTrackIds = {...availableTrackIds};
      _initializedSelection = true;
    } else {
      selectedTrackIds = state.selectedTrackSlotIds.intersection(
        availableTrackIds,
      );
    }
    emit(
      state.copyWith(
        selectedTrackSlotIds: selectedTrackIds,
        clearErrorMessage: true,
      ),
    );

    for (final slot in submittedTrackSlots) {
      unawaited(_loadWaveformForTrack(slot: slot));
    }
    _emitPlayAllWaveform();
  }

  void toggleTrackSelection({
    required String trackSlotId,
    required bool selected,
  }) {
    final nextSelection = {...state.selectedTrackSlotIds};
    if (selected) {
      nextSelection.add(trackSlotId);
    } else {
      nextSelection.remove(trackSlotId);
    }
    emit(
      state.copyWith(
        selectedTrackSlotIds: nextSelection,
        clearErrorMessage: true,
      ),
    );
    _emitPlayAllWaveform();
  }

  Future<void> playMix(String localMixPath) async {
    try {
      await stopAllTracks();
      await _singlePlayer.setFilePath(localMixPath);
      await _singlePlayer.seek(Duration.zero);
      await _singlePlayer.play();
      emit(
        state.copyWith(
          isSinglePlaying: true,
          isPlayingMix: true,
          clearActiveTrackSlotId: true,
          singlePosition: Duration.zero,
          clearErrorMessage: true,
        ),
      );
    } catch (error) {
      emit(state.copyWith(errorMessage: 'Unable to play mix: $error'));
    }
  }

  Future<void> playTrack({
    required TrackSlot trackSlot,
    Duration? startAt,
    bool autoplay = true,
  }) async {
    final takePath = trackSlot.currentTakeFilePath;
    if (takePath == null || takePath.isEmpty) return;
    try {
      // Avoid doubled audio from mixed playback modes.
      if (state.isPlayingAllTracks || state.isPreparingAllTracks) {
        await _stopPlayAllPlayers();
      }
      await _singlePlayer.stop();
      emit(
        state.copyWith(
          isSinglePlaying: false,
          isPlayingMix: false,
          clearActiveTrackSlotId: true,
        ),
      );

      final localPath = await _songRepository.cacheTakeForPlayback(
        songId: _songId,
        takePath: takePath,
      );
      final player = await _ensureTrackPlayer(
        trackSlotId: trackSlot.id,
        localPath: localPath,
      );

      if (startAt != null) {
        await player.seek(startAt);
      }
      emit(
        state.copyWith(
          trackPositions: {
            ...state.trackPositions,
            trackSlot.id: startAt ?? state.trackPositions[trackSlot.id] ?? Duration.zero,
          },
          clearErrorMessage: true,
        ),
      );
      if (autoplay) {
        await player.play();
        emit(
          state.copyWith(
            playingTrackSlotIds: {...state.playingTrackSlotIds, trackSlot.id},
          ),
        );
      }
    } catch (error) {
      emit(state.copyWith(errorMessage: 'Unable to play track: $error'));
    }
  }

  Future<void> seekTrack({
    required TrackSlot trackSlot,
    required Duration position,
  }) async {
    if (state.isPlayingAllTracks &&
        state.selectedTrackSlotIds.contains(trackSlot.id)) {
      await seekAllTracks(position);
      return;
    }

    final takePath = trackSlot.currentTakeFilePath;
    if (takePath == null || takePath.isEmpty) return;

    final localPath = await _songRepository.cacheTakeForPlayback(
      songId: _songId,
      takePath: takePath,
    );
    final player = await _ensureTrackPlayer(
      trackSlotId: trackSlot.id,
      localPath: localPath,
    );
    await player.seek(position);
    emit(
      state.copyWith(
        trackPositions: {
          ...state.trackPositions,
          trackSlot.id: position,
        },
      ),
    );
  }

  Future<void> pauseSingle() async {
    await _singlePlayer.pause();
    emit(
      state.copyWith(
        isSinglePlaying: false,
        isPlayingMix: false,
      ),
    );
  }

  Future<void> pauseTrack(String trackSlotId) async {
    final player = _trackPlayers[trackSlotId];
    if (player == null) return;
    await player.pause();
    final playingTrackIds = {...state.playingTrackSlotIds}..remove(trackSlotId);
    emit(state.copyWith(playingTrackSlotIds: playingTrackIds));
  }

  Future<void> seekSingle(Duration position) async {
    await _singlePlayer.seek(position);
    emit(state.copyWith(singlePosition: position));
  }

  Future<void> playAllTracks({
    required List<TrackSlot> trackSlots,
  }) async {
    if (state.isPreparingAllTracks) return;

    final selectedSlots =
        trackSlots
            .where(
              (slot) =>
                  state.selectedTrackSlotIds.contains(slot.id) &&
                  (slot.currentTakeFilePath ?? '').isNotEmpty,
            )
            .toList()
          ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));

    if (selectedSlots.isEmpty) return;

    await _singlePlayer.stop();
    await _stopIndividualTrackPlayers();
    await _stopPlayAllPlayers();
    emit(
      state.copyWith(
        isPreparingAllTracks: true,
        isPlayingAllTracks: false,
        isSinglePlaying: false,
        isPlayingMix: false,
        clearActiveTrackSlotId: true,
        playingTrackSlotIds: const <String>{},
        clearErrorMessage: true,
      ),
    );

    final createdPlayers = <AudioPlayer>[];
    try {
      for (final slot in selectedSlots) {
        final localPath = await _songRepository.cacheTakeForPlayback(
          songId: _songId,
          takePath: slot.currentTakeFilePath!,
        );
        final player = _playerFactory();
        await player.setFilePath(localPath);
        await player.seek(state.playAllPosition);
        createdPlayers.add(player);
      }
      _allPlayers.addAll(createdPlayers);
      _bindAllPlayers();

      emit(
        state.copyWith(
          isPreparingAllTracks: false,
          isPlayingAllTracks: true,
          playAllDuration: _maxDuration(createdPlayers),
        ),
      );
      for (final player in _allPlayers) {
        unawaited(player.play());
      }
    } catch (error) {
      for (final player in createdPlayers) {
        unawaited(player.dispose());
      }
      emit(
        state.copyWith(
          isPreparingAllTracks: false,
          isPlayingAllTracks: false,
          errorMessage: 'Unable to play all tracks: $error',
        ),
      );
    }
  }

  Future<void> seekAllTracks(Duration position) async {
    if (_allPlayers.isEmpty) {
      emit(state.copyWith(playAllPosition: position));
      return;
    }
    for (final player in _allPlayers) {
      await player.seek(position);
    }
    emit(state.copyWith(playAllPosition: position));
  }

  Future<void> stopAllTracks() async {
    await _stopPlayAllPlayers();
    await _stopIndividualTrackPlayers();
    emit(
      state.copyWith(
        isPreparingAllTracks: false,
        isPlayingAllTracks: false,
        playingTrackSlotIds: const <String>{},
      ),
    );
  }

  void _bindAllPlayers() {
    for (var i = 0; i < _allPlayers.length; i++) {
      final player = _allPlayers[i];
      _allPlayerSubscriptions.add(
        player.playerStateStream.listen((_) => _syncPlayAllState()),
      );
      if (i == 0) {
        _allPlayerSubscriptions.add(
          player.positionStream.listen((position) {
            if (isClosed) return;
            emit(state.copyWith(playAllPosition: position));
          }),
        );
      }
    }
  }

  void _syncPlayAllState() {
    if (isClosed) return;
    final hasAnyPlaying = _allPlayers.any(
      (player) =>
          player.playing && player.processingState != ProcessingState.completed,
    );
    if (hasAnyPlaying != state.isPlayingAllTracks) {
      emit(state.copyWith(isPlayingAllTracks: hasAnyPlaying));
    }
    if (!hasAnyPlaying &&
        _allPlayers.isNotEmpty &&
        !state.isPreparingAllTracks) {
      unawaited(_stopPlayAllPlayers());
    }
  }

  Future<void> _loadWaveformForTrack({
    required TrackSlot slot,
  }) async {
    final takeId = slot.currentTakeId;
    final takePath = slot.currentTakeFilePath;
    if (takeId == null || takePath == null || takePath.isEmpty) return;

    final existing = state.trackWaveforms[slot.id];
    if (existing != null &&
        existing.takeId == takeId &&
        existing.waveform != null) {
      return;
    }

    final loadingMap = {
      ...state.trackWaveforms,
      slot.id: TrackWaveformState(
        takeId: takeId,
        isLoading: true,
      ),
    };
    emit(state.copyWith(trackWaveforms: loadingMap));

    try {
      final localPath = await _songRepository.cacheTakeForPlayback(
        songId: _songId,
        takePath: takePath,
      );
      final waveform = await _waveformService.loadTrackWaveform(
        songId: _songId,
        takeId: takeId,
        localAudioPath: localPath,
      );
      final updatedMap = {
        ...state.trackWaveforms,
        slot.id: TrackWaveformState(
          takeId: takeId,
          isLoading: false,
          waveform: waveform,
        ),
      };
      emit(state.copyWith(trackWaveforms: updatedMap));
      _emitPlayAllWaveform();
    } catch (error) {
      final errorMap = {
        ...state.trackWaveforms,
        slot.id: TrackWaveformState(
          takeId: takeId,
          isLoading: false,
          errorMessage: '$error',
        ),
      };
      emit(state.copyWith(trackWaveforms: errorMap));
    }
  }

  void _emitPlayAllWaveform() {
    final selectedWaveforms = state.selectedTrackSlotIds
        .map((slotId) => state.trackWaveforms[slotId]?.waveform)
        .whereType<WaveformData>()
        .toList();
    if (selectedWaveforms.isEmpty) {
      emit(state.copyWith(clearPlayAllWaveform: true));
      return;
    }
    emit(state.copyWith(playAllWaveform: _mergeWaveforms(selectedWaveforms)));
  }

  WaveformData _mergeWaveforms(List<WaveformData> waveforms) {
    if (waveforms.length == 1) {
      return WaveformData(
        id: 'play_all',
        durationMs: waveforms.first.durationMs,
        samples: waveforms.first.samples,
      );
    }

    final maxSamples = waveforms.fold<int>(
      0,
      (maxValue, waveform) => max(maxValue, waveform.samples.length),
    );
    final maxDurationMs = waveforms.fold<int>(
      0,
      (maxValue, waveform) => max(maxValue, waveform.durationMs),
    );
    final accum = List<double>.filled(maxSamples, 0);
    final counts = List<int>.filled(maxSamples, 0);

    for (final waveform in waveforms) {
      final resampled = _resample(waveform.samples, maxSamples);
      for (var i = 0; i < maxSamples; i++) {
        accum[i] += resampled[i];
        counts[i] += 1;
      }
    }

    final merged = List<double>.generate(maxSamples, (i) {
      final count = counts[i];
      if (count == 0) return 0;
      return accum[i] / count;
    });

    return WaveformData(
      id: 'play_all',
      durationMs: maxDurationMs,
      samples: merged,
    );
  }

  List<double> _resample(List<double> source, int targetLength) {
    if (targetLength <= 0) return const [];
    if (source.isEmpty) {
      return List<double>.filled(targetLength, 0);
    }
    if (source.length == targetLength) {
      return source;
    }
    return List<double>.generate(targetLength, (index) {
      final ratio = targetLength == 1 ? 0.0 : index / (targetLength - 1);
      final sourceIndex = (ratio * (source.length - 1)).round();
      return source[sourceIndex];
    });
  }

  Duration? _maxDuration(List<AudioPlayer> players) {
    final durations = players
        .map((player) => player.duration)
        .whereType<Duration>()
        .toList();
    if (durations.isEmpty) return null;
    var maxDuration = Duration.zero;
    for (final duration in durations) {
      if (duration > maxDuration) {
        maxDuration = duration;
      }
    }
    return maxDuration;
  }

  Future<AudioPlayer> _ensureTrackPlayer({
    required String trackSlotId,
    required String localPath,
  }) async {
    final existing = _trackPlayers[trackSlotId];
    if (existing == null) {
      final player = _playerFactory();
      _trackPlayers[trackSlotId] = player;
      _bindIndividualTrackPlayer(trackSlotId: trackSlotId, player: player);
      await player.setFilePath(localPath);
      _trackPlayerPaths[trackSlotId] = localPath;
      return player;
    }

    final loadedPath = _trackPlayerPaths[trackSlotId];
    if (loadedPath != localPath) {
      await existing.setFilePath(localPath);
      _trackPlayerPaths[trackSlotId] = localPath;
    }
    return existing;
  }

  void _bindIndividualTrackPlayer({
    required String trackSlotId,
    required AudioPlayer player,
  }) {
    final subscriptions = <StreamSubscription<dynamic>>[
      player.positionStream.listen((position) {
        if (isClosed) return;
        emit(
          state.copyWith(
            trackPositions: {
              ...state.trackPositions,
              trackSlotId: position,
            },
          ),
        );
      }),
      player.playerStateStream.listen((playerState) {
        if (isClosed) return;
        final hasCompleted =
            playerState.processingState == ProcessingState.completed;
        final isPlaying = playerState.playing && !hasCompleted;
        final playingTrackIds = {...state.playingTrackSlotIds};
        if (isPlaying) {
          playingTrackIds.add(trackSlotId);
        } else {
          playingTrackIds.remove(trackSlotId);
        }
        emit(state.copyWith(playingTrackSlotIds: playingTrackIds));

        if (hasCompleted) {
          final duration = player.duration;
          if (duration != null) {
            emit(
              state.copyWith(
                trackPositions: {
                  ...state.trackPositions,
                  trackSlotId: duration,
                },
              ),
            );
          }
        }
      }),
    ];
    _trackPlayerSubscriptions[trackSlotId] = subscriptions;
  }

  Future<void> _stopPlayAllPlayers() async {
    for (final player in _allPlayers) {
      await player.stop();
    }
    await _disposePlayAllTrackPlayers();
    emit(
      state.copyWith(
        isPreparingAllTracks: false,
        isPlayingAllTracks: false,
      ),
    );
  }

  Future<void> _stopIndividualTrackPlayers() async {
    for (final player in _trackPlayers.values) {
      await player.stop();
    }
    final updatedPositions = <String, Duration>{
      ...state.trackPositions,
      for (final entry in _trackPlayers.entries) entry.key: Duration.zero,
    };
    emit(
      state.copyWith(
        trackPositions: updatedPositions,
        playingTrackSlotIds: const <String>{},
      ),
    );
  }

  Future<void> _disposePlayAllTrackPlayers() async {
    for (final subscription in _allPlayerSubscriptions) {
      await subscription.cancel();
    }
    _allPlayerSubscriptions.clear();
    for (final player in _allPlayers) {
      await player.dispose();
    }
    _allPlayers.clear();
  }

  @override
  Future<void> close() async {
    await _singlePositionSubscription?.cancel();
    await _singleDurationSubscription?.cancel();
    await _singlePlayerStateSubscription?.cancel();
    await _disposePlayAllTrackPlayers();
    for (final subscriptions in _trackPlayerSubscriptions.values) {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
    _trackPlayerSubscriptions.clear();
    for (final player in _trackPlayers.values) {
      await player.dispose();
    }
    _trackPlayers.clear();
    _trackPlayerPaths.clear();
    await _singlePlayer.dispose();
    return super.close();
  }
}
