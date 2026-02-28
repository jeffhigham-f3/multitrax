import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:multitrax_app/playback/cubit/playback_state.dart';
import 'package:multitrax_app/playback/models/waveform_data.dart';
import 'package:multitrax_app/playback/widgets/track_waveform_view.dart';

void main() {
  group('TrackWaveformView', () {
    testWidgets('tap emits seek duration mapped from x position', (
      tester,
    ) async {
      Duration? seekedDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: TrackWaveformView(
                waveformState: const TrackWaveformState(
                  takeId: 'take-1',
                  waveform: WaveformData(
                    id: 'take-1',
                    durationMs: 1000,
                    samples: [0.1, 0.3, 0.6, 0.2],
                  ),
                ),
                position: Duration.zero,
                onSeek: (duration) => seekedDuration = duration,
              ),
            ),
          ),
        ),
      );

      final gestureDetector = find.byType(GestureDetector).first;
      final topLeft = tester.getTopLeft(gestureDetector);
      await tester.tapAt(topLeft + const Offset(150, 24));
      await tester.pump();

      expect(seekedDuration, isNotNull);
      expect(seekedDuration!.inMilliseconds, inInclusiveRange(700, 800));
    });
  });
}
