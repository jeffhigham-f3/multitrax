import 'package:flutter_test/flutter_test.dart';
import 'package:multitrax_app/songs/cubit/song_detail_cubit.dart';

void main() {
  test('copyWith allows clearing nullable recording fields', () {
    const initial = SongDetailState(
      pendingTrackSlotId: 'slot-1',
      pendingSlotIndex: 3,
      pendingRecordingPath: '/tmp/take.m4a',
      errorMessage: 'old error',
    );

    final updated = initial.copyWith(
      pendingTrackSlotId: null,
      pendingSlotIndex: null,
      pendingRecordingPath: null,
      errorMessage: null,
    );

    expect(updated.pendingTrackSlotId, isNull);
    expect(updated.pendingSlotIndex, isNull);
    expect(updated.pendingRecordingPath, isNull);
    expect(updated.errorMessage, isNull);
  });

  test('copyWith keeps nullable fields when omitted', () {
    const initial = SongDetailState(
      pendingTrackSlotId: 'slot-1',
      pendingSlotIndex: 3,
      pendingRecordingPath: '/tmp/take.m4a',
      errorMessage: 'old error',
    );

    final updated = initial.copyWith(isRecording: true);

    expect(updated.pendingTrackSlotId, 'slot-1');
    expect(updated.pendingSlotIndex, 3);
    expect(updated.pendingRecordingPath, '/tmp/take.m4a');
    expect(updated.errorMessage, 'old error');
    expect(updated.isRecording, isTrue);
  });
}
