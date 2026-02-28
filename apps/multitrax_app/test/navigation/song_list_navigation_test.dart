import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockingjay/mockingjay.dart';
import 'package:multitrax_app/core/storage/upload_queue_store.dart';
import 'package:multitrax_app/songs/models/song_models.dart';
import 'package:multitrax_app/songs/repositories/song_repository.dart';
import 'package:multitrax_app/songs/view/song_list_page.dart';

class _StubSongRepository implements SongRepository {
  @override
  Future<void> addMemberByEmail({
    required String songId,
    required String email,
    String role = 'editor',
  }) async {}

  @override
  Future<void> createSong(String title) async {}

  @override
  Future<SongDetail> fetchSongDetail(String songId) {
    throw UnimplementedError();
  }

  @override
  Future<List<SongSummary>> fetchSongs({
    required int page,
    int pageSize = 20,
  }) async {
    if (page == 0) {
      return [
        SongSummary(
          id: 'song-1',
          title: 'Song One',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ];
    }
    return const [];
  }

  @override
  Future<void> flushPendingUploads() async {}

  @override
  Future<List<PendingUpload>> pendingUploads() async => const [];

  @override
  Future<String> cacheTakeForPlayback({
    required String songId,
    required String takePath,
  }) async {
    return '/tmp/$songId-take.wav';
  }

  @override
  Future<void> queueExportJob({
    required String songId,
    required String outputFormat,
  }) async {}

  @override
  Future<void> queueRenderJob(String songId) async {}

  @override
  Future<TakeSubmissionResult> submitTake({
    required String songId,
    required String trackSlotId,
    required String localFilePath,
    String? basedOnMixVersionId,
  }) async {
    return TakeSubmissionResult(queuedForRetry: false);
  }

  @override
  Future<String?> syncLatestMix({
    required String songId,
    String? mixPath,
  }) async {
    return null;
  }
}

void main() {
  testWidgets('tapping song pushes a new route', (tester) async {
    final navigator = MockNavigator();
    final repository = _StubSongRepository();

    when(() => navigator.canPop()).thenReturn(false);
    when(() => navigator.push<Object?>(any())).thenAnswer((_) async => null);

    await tester.pumpWidget(
      MaterialApp(
        home: MockNavigatorProvider(
          navigator: navigator,
          child: RepositoryProvider<SongRepository>.value(
            value: repository,
            child: const SongListPage(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Song One'));
    await tester.pump();

    verify(
      () => navigator.push<Object?>(
        any(that: isRoute<Object?>()),
      ),
    ).called(1);
  });
}
