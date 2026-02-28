import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:multitrax_app/playback/cubit/playback_state.dart';

class TrackWaveformView extends StatelessWidget {
  const TrackWaveformView({
    required this.waveformState,
    required this.position,
    required this.onSeek,
    super.key,
  });

  final TrackWaveformState waveformState;
  final Duration position;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    if (waveformState.isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    if (waveformState.errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Waveform unavailable',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      );
    }

    final waveform = waveformState.waveform;
    if (waveform == null || waveform.samples.isEmpty) {
      return const SizedBox.shrink();
    }

    final durationMs = waveform.durationMs <= 0 ? 1 : waveform.durationMs;
    final clampedMs = position.inMilliseconds.clamp(0, durationMs);
    final playheadX = waveform.samples.length <= 1
        ? 0.0
        : clampedMs / durationMs * (waveform.samples.length - 1);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 72,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              onTapDown: (details) => _seekForDx(
                localDx: details.localPosition.dx,
                width: constraints.maxWidth,
                durationMs: durationMs,
              ),
              onHorizontalDragUpdate: (details) => _seekForDx(
                localDx: details.localPosition.dx,
                width: constraints.maxWidth,
                durationMs: durationMs,
              ),
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (waveform.samples.length - 1).toDouble(),
                  minY: 0,
                  maxY: 1,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                  extraLinesData: ExtraLinesData(
                    verticalLines: [
                      VerticalLine(
                        x: playheadX,
                        color: Theme.of(context).colorScheme.primary,
                        strokeWidth: 2,
                      ),
                    ],
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List<FlSpot>.generate(
                        waveform.samples.length,
                        (index) =>
                            FlSpot(index.toDouble(), waveform.samples[index]),
                      ),
                      isCurved: false,
                      barWidth: 1,
                      isStrokeCapRound: true,
                      color: Theme.of(context).colorScheme.secondary,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Theme.of(
                          context,
                        ).colorScheme.secondary.withValues(alpha: 0.15),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _seekForDx({
    required double localDx,
    required double width,
    required int durationMs,
  }) {
    if (width <= 0) return;
    final ratio = (localDx / width).clamp(0.0, 1.0);
    final targetMs = (durationMs * ratio).round();
    onSeek(Duration(milliseconds: targetMs));
  }
}
