import 'package:multitrax_app/playback/models/waveform_data.dart';

class TrackWaveformState {
  const TrackWaveformState({
    required this.takeId,
    this.isLoading = false,
    this.waveform,
    this.errorMessage,
  });

  const TrackWaveformState.initial()
    : takeId = null,
      isLoading = false,
      waveform = null,
      errorMessage = null;

  final String? takeId;
  final bool isLoading;
  final WaveformData? waveform;
  final String? errorMessage;

  TrackWaveformState copyWith({
    String? takeId,
    bool? isLoading,
    WaveformData? waveform,
    String? errorMessage,
  }) {
    return TrackWaveformState(
      takeId: takeId ?? this.takeId,
      isLoading: isLoading ?? this.isLoading,
      waveform: waveform ?? this.waveform,
      errorMessage: errorMessage,
    );
  }
}

class PlaybackState {
  const PlaybackState({
    this.isSinglePlaying = false,
    this.isPlayingMix = false,
    this.activeTrackSlotId,
    this.singlePosition = Duration.zero,
    this.singleDuration,
    this.isPreparingAllTracks = false,
    this.isPlayingAllTracks = false,
    this.playAllPosition = Duration.zero,
    this.playAllDuration,
    this.selectedTrackSlotIds = const <String>{},
    this.playingTrackSlotIds = const <String>{},
    this.trackPositions = const <String, Duration>{},
    this.trackWaveforms = const <String, TrackWaveformState>{},
    this.playAllWaveform,
    this.errorMessage,
  });

  final bool isSinglePlaying;
  final bool isPlayingMix;
  final String? activeTrackSlotId;
  final Duration singlePosition;
  final Duration? singleDuration;
  final bool isPreparingAllTracks;
  final bool isPlayingAllTracks;
  final Duration playAllPosition;
  final Duration? playAllDuration;
  final Set<String> selectedTrackSlotIds;
  final Set<String> playingTrackSlotIds;
  final Map<String, Duration> trackPositions;
  final Map<String, TrackWaveformState> trackWaveforms;
  final WaveformData? playAllWaveform;
  final String? errorMessage;

  PlaybackState copyWith({
    bool? isSinglePlaying,
    bool? isPlayingMix,
    String? activeTrackSlotId,
    bool clearActiveTrackSlotId = false,
    Duration? singlePosition,
    Duration? singleDuration,
    bool clearSingleDuration = false,
    bool? isPreparingAllTracks,
    bool? isPlayingAllTracks,
    Duration? playAllPosition,
    Duration? playAllDuration,
    bool clearPlayAllDuration = false,
    Set<String>? selectedTrackSlotIds,
    Set<String>? playingTrackSlotIds,
    Map<String, Duration>? trackPositions,
    Map<String, TrackWaveformState>? trackWaveforms,
    WaveformData? playAllWaveform,
    bool clearPlayAllWaveform = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return PlaybackState(
      isSinglePlaying: isSinglePlaying ?? this.isSinglePlaying,
      isPlayingMix: isPlayingMix ?? this.isPlayingMix,
      activeTrackSlotId: clearActiveTrackSlotId
          ? null
          : (activeTrackSlotId ?? this.activeTrackSlotId),
      singlePosition: singlePosition ?? this.singlePosition,
      singleDuration: clearSingleDuration
          ? null
          : (singleDuration ?? this.singleDuration),
      isPreparingAllTracks: isPreparingAllTracks ?? this.isPreparingAllTracks,
      isPlayingAllTracks: isPlayingAllTracks ?? this.isPlayingAllTracks,
      playAllPosition: playAllPosition ?? this.playAllPosition,
      playAllDuration: clearPlayAllDuration
          ? null
          : (playAllDuration ?? this.playAllDuration),
      selectedTrackSlotIds: selectedTrackSlotIds ?? this.selectedTrackSlotIds,
      playingTrackSlotIds: playingTrackSlotIds ?? this.playingTrackSlotIds,
      trackPositions: trackPositions ?? this.trackPositions,
      trackWaveforms: trackWaveforms ?? this.trackWaveforms,
      playAllWaveform: clearPlayAllWaveform
          ? null
          : (playAllWaveform ?? this.playAllWaveform),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}
