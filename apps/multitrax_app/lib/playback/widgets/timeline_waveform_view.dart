import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:multitrax_app/playback/models/waveform_data.dart';

class TimelineWaveformView extends StatelessWidget {
  const TimelineWaveformView({
    required this.waveform,
    required this.position,
    required this.onSeek,
    this.isPreparing = false,
    super.key,
  });

  final WaveformData? waveform;
  final Duration position;
  final bool isPreparing;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    if (isPreparing) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    final data = waveform;
    if (data == null || data.samples.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Waveform appears after track analysis.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final durationMs = data.durationMs <= 0 ? 1 : data.durationMs;
    final clampedMs = position.inMilliseconds.clamp(0, durationMs);
    final playheadX = data.samples.length <= 1
        ? 0.0
        : clampedMs / durationMs * (data.samples.length - 1);

    return SizedBox(
      height: 96,
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
                maxX: (data.samples.length - 1).toDouble(),
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
                      data.samples.length,
                      (index) => FlSpot(index.toDouble(), data.samples[index]),
                    ),
                    isCurved: false,
                    barWidth: 1,
                    color: Theme.of(context).colorScheme.primary,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
