import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';

import 'package:multitrax_app/playback/cubit/playback_cubit.dart';
import 'package:multitrax_app/playback/models/waveform_data.dart';
import 'package:multitrax_app/playback/services/waveform_service.dart';
import 'package:multitrax_app/songs/models/song_models.dart';
import 'package:multitrax_app/songs/repositories/song_repository.dart';

class _MockSongRepository extends Mock implements SongRepository {}

class _MockWaveformService extends Mock implements WaveformService {}

class _MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  group('PlaybackCubit', () {
    late _MockSongRepository songRepository;
    late _MockWaveformService waveformService;
    late _MockAudioPlayer singlePlayer;
    late StreamController<PlayerState> playerStateController;
    late StreamController<Duration> positionController;
    late StreamController<Duration?> durationController;

    setUp(() {
      songRepository = _MockSongRepository();
      waveformService = _MockWaveformService();
      singlePlayer = _MockAudioPlayer();

      playerStateController = StreamController<PlayerState>.broadcast();
      positionController = StreamController<Duration>.broadcast();
      durationController = StreamController<Duration?>.broadcast();

      when(
        () => singlePlayer.playerStateStream,
      ).thenAnswer((_) => playerStateController.stream);
      when(
        () => singlePlayer.positionStream,
      ).thenAnswer((_) => positionController.stream);
      when(
        () => singlePlayer.durationStream,
      ).thenAnswer((_) => durationController.stream);
      when(
        () => singlePlayer.setFilePath(any()),
      ).thenAnswer((_) async => Duration.zero);
      when(singlePlayer.play).thenAnswer((_) async {});
      when(singlePlayer.pause).thenAnswer((_) async {});
      when(singlePlayer.stop).thenAnswer((_) async {});
      when(() => singlePlayer.seek(any())).thenAnswer((_) async {});
      when(singlePlayer.dispose).thenAnswer((_) async {});
      when(() => singlePlayer.processingState).thenReturn(ProcessingState.idle);
      when(() => singlePlayer.playing).thenReturn(false);
      when(() => singlePlayer.duration).thenReturn(const Duration(seconds: 3));
    });

    tearDown(() async {
      await playerStateController.close();
      await positionController.close();
      await durationController.close();
    });

    test('individual track completion removes it from playing set', () async {
      when(
        () => songRepository.cacheTakeForPlayback(
          songId: any(named: 'songId'),
          takePath: any(named: 'takePath'),
        ),
      ).thenAnswer((_) async => '/tmp/track.m4a');

      final trackPlayer = _MockAudioPlayer();
      final trackPlayerStateController = StreamController<PlayerState>.broadcast();
      final trackPositionController = StreamController<Duration>.broadcast();
      final trackDurationController = StreamController<Duration?>.broadcast();
      addTearDown(trackPlayerStateController.close);
      addTearDown(trackPositionController.close);
      addTearDown(trackDurationController.close);

      when(
        () => trackPlayer.playerStateStream,
      ).thenAnswer((_) => trackPlayerStateController.stream);
      when(
        () => trackPlayer.positionStream,
      ).thenAnswer((_) => trackPositionController.stream);
      when(
        () => trackPlayer.durationStream,
      ).thenAnswer((_) => trackDurationController.stream);
      when(
        () => trackPlayer.setFilePath(any()),
      ).thenAnswer((_) async => Duration.zero);
      when(trackPlayer.play).thenAnswer((_) async {});
      when(trackPlayer.pause).thenAnswer((_) async {});
      when(trackPlayer.stop).thenAnswer((_) async {});
      when(() => trackPlayer.seek(any())).thenAnswer((_) async {});
      when(trackPlayer.dispose).thenAnswer((_) async {});
      when(() => trackPlayer.duration).thenReturn(const Duration(seconds: 3));
      when(() => trackPlayer.processingState).thenReturn(ProcessingState.ready);
      when(() => trackPlayer.playing).thenReturn(true);

      final cubit = PlaybackCubit(
        songId: 'song-1',
        songRepository: songRepository,
        waveformService: waveformService,
        singlePlayer: singlePlayer,
        playerFactory: () => trackPlayer,
      );
      addTearDown(cubit.close);

      final slot = TrackSlot(
        id: 'slot-1',
        slotIndex: 1,
        label: 'Track 1',
        currentTakeId: 'take-1',
        currentTakeFilePath: 'song-1/takes/take-1.m4a',
      );

      await cubit.playTrack(trackSlot: slot);
      expect(cubit.state.playingTrackSlotIds, contains(slot.id));

      trackPlayerStateController.add(PlayerState(false, ProcessingState.completed));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.playingTrackSlotIds, isNot(contains(slot.id)));
    });

    test(
      'hydrates selection and recomputes play-all waveform on toggle',
      () async {
        when(
          () => songRepository.cacheTakeForPlayback(
            songId: any(named: 'songId'),
            takePath: any(named: 'takePath'),
          ),
        ).thenAnswer((_) async => '/tmp/track.m4a');

        when(
          () => waveformService.loadTrackWaveform(
            songId: any(named: 'songId'),
            takeId: any(named: 'takeId'),
            localAudioPath: any(named: 'localAudioPath'),
            targetSampleCount: any(named: 'targetSampleCount'),
          ),
        ).thenAnswer((invocation) async {
          final takeId = invocation.namedArguments[#takeId] as String;
          if (takeId == 'take-1') {
            return const WaveformData(
              id: 'take-1',
              durationMs: 1000,
              samples: [0.2, 0.4, 0.6],
            );
          }
          return const WaveformData(
            id: 'take-2',
            durationMs: 1000,
            samples: [0.8, 0.6, 0.4],
          );
        });

        final cubit = PlaybackCubit(
          songId: 'song-1',
          songRepository: songRepository,
          waveformService: waveformService,
          singlePlayer: singlePlayer,
          playerFactory: () => _MockAudioPlayer(),
        );
        addTearDown(cubit.close);

        final detail = SongDetail(
          song: SongSummary(
            id: 'song-1',
            title: 'Song',
            createdAt: DateTime(2026),
          ),
          trackSlots: [
            TrackSlot(
              id: 'slot-1',
              slotIndex: 1,
              label: 'Track 1',
              currentTakeId: 'take-1',
              currentTakeFilePath: 'song-1/takes/take-1.m4a',
            ),
            TrackSlot(
              id: 'slot-2',
              slotIndex: 2,
              label: 'Track 2',
              currentTakeId: 'take-2',
              currentTakeFilePath: 'song-1/takes/take-2.m4a',
            ),
          ],
          members: const [],
          renderJobs: const [],
          exportJobs: const [],
        );

        await cubit.hydrateFromSongDetail(detail);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(cubit.state.selectedTrackSlotIds, {'slot-1', 'slot-2'});
        expect(cubit.state.playAllWaveform, isNotNull);

        cubit.toggleTrackSelection(trackSlotId: 'slot-2', selected: false);
        expect(cubit.state.selectedTrackSlotIds, {'slot-1'});
        expect(
          cubit.state.playAllWaveform?.samples,
          const [0.2, 0.4, 0.6],
        );
      },
    );
  });
}
