import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:multitrax_app/core/storage/upload_queue_store.dart';
import 'package:multitrax_app/songs/cubit/song_list_cubit.dart';
import 'package:multitrax_app/songs/models/song_models.dart';
import 'package:multitrax_app/songs/repositories/song_repository.dart';

class _MockSongRepository extends Mock implements SongRepository {}

void main() {
  late _MockSongRepository repository;

  setUp(() {
    repository = _MockSongRepository();
    when(() => repository.flushPendingUploads()).thenAnswer((_) async {});
    when(() => repository.pendingUploads()).thenAnswer(
      (_) async => [
        PendingUpload(
          songId: 'song-1',
          trackSlotId: 'slot-1',
          localFilePath: '/tmp/queued.m4a',
          submissionId: 'submission-1',
        ),
      ],
    );
    when(() => repository.createSong(any())).thenAnswer((_) async {});
  });

  test('initialize loads first page and pending uploads', () async {
    when(
      () => repository.fetchSongs(
        page: 0,
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer(
      (_) async => [
        SongSummary(
          id: 'song-1',
          title: 'Song One',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    );

    final cubit = SongListCubit(songRepository: repository);
    await cubit.initialize();

    expect(cubit.state.songs, hasLength(1));
    expect(cubit.state.pendingUploads, 1);
    expect(cubit.state.errorMessage, isNull);
  });

  test('fetchNextPage appends songs', () async {
    final firstPage = List.generate(
      20,
      (index) => SongSummary(
        id: 'song-${index + 1}',
        title: 'Song ${index + 1}',
        createdAt: DateTime.utc(2026, 1, 1).add(Duration(days: index)),
      ),
    );

    when(
      () => repository.fetchSongs(
        page: 0,
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) async => firstPage);
    when(
      () => repository.fetchSongs(
        page: 1,
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer(
      (_) async => [
        SongSummary(
          id: 'song-2',
          title: 'Song Two',
          createdAt: DateTime.utc(2026, 1, 2),
        ),
      ],
    );

    final cubit = SongListCubit(songRepository: repository);
    await cubit.initialize();
    await cubit.fetchNextPage();

    expect(cubit.state.songs, hasLength(21));
    expect(cubit.state.songs.last.id, 'song-2');
  });

  test('createSong refreshes list', () async {
    when(
      () => repository.fetchSongs(
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer(
      (_) async => [
        SongSummary(
          id: 'song-1',
          title: 'Song One',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    );

    final cubit = SongListCubit(songRepository: repository);
    await cubit.initialize();
    await cubit.createSong('New Song');

    verify(() => repository.createSong('New Song')).called(1);
  });

  test('initialize does not block on queued upload flush', () async {
    final flushCompleter = Completer<void>();
    when(() => repository.flushPendingUploads()).thenAnswer((_) => flushCompleter.future);
    when(() => repository.pendingUploads()).thenAnswer((_) async => const []);
    when(
      () => repository.fetchSongs(
        page: 0,
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) async => const []);

    final cubit = SongListCubit(songRepository: repository);
    final initializeFuture = cubit.initialize();

    await expectLater(
      initializeFuture.timeout(const Duration(milliseconds: 200)),
      completes,
    );
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.isFlushingUploads, isTrue);

    flushCompleter.complete();
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.isFlushingUploads, isFalse);
  });
}
