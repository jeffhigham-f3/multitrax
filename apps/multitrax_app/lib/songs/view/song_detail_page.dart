import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:formz/formz.dart';
import 'package:very_good_infinite_list/very_good_infinite_list.dart';

import 'package:multitrax_app/exports/export_service.dart';
import 'package:multitrax_app/playback/cubit/playback_cubit.dart';
import 'package:multitrax_app/playback/cubit/playback_state.dart';
import 'package:multitrax_app/playback/services/waveform_service.dart';
import 'package:multitrax_app/playback/widgets/timeline_waveform_view.dart';
import 'package:multitrax_app/playback/widgets/track_waveform_view.dart';
import 'package:multitrax_app/recording/recording_service.dart';
import 'package:multitrax_app/songs/cubit/song_detail_cubit.dart';
import 'package:multitrax_app/songs/forms/song_forms.dart';
import 'package:multitrax_app/songs/models/song_models.dart';
import 'package:multitrax_app/songs/repositories/song_repository.dart';
import 'package:multitrax_app/sync/song_sync_service.dart';

class SongDetailPage extends StatelessWidget {
  const SongDetailPage({
    required this.songId,
    super.key,
  });

  final String songId;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) {
            final cubit = SongDetailCubit(
              songId: songId,
              songRepository: context.read<SongRepository>(),
              songSyncService: context.read<SongSyncService>(),
              recordingService: context.read<RecordingService>(),
              exportService: context.read<ExportService>(),
            );
            unawaited(cubit.load());
            return cubit;
          },
        ),
        BlocProvider(
          create: (_) => PlaybackCubit(
            songId: songId,
            songRepository: context.read<SongRepository>(),
            waveformService: context.read<WaveformService>(),
          ),
        ),
      ],
      child: const _SongDetailView(),
    );
  }
}

class _SongDetailView extends StatelessWidget {
  const _SongDetailView();

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<SongDetailCubit, SongDetailState>(
          listenWhen: (previous, current) => previous.detail != current.detail,
          listener: (context, state) {
            final detail = state.detail;
            if (detail == null) return;
            unawaited(
              context.read<PlaybackCubit>().hydrateFromSongDetail(detail),
            );
          },
        ),
      ],
      child: BlocBuilder<SongDetailCubit, SongDetailState>(
        builder: (context, songState) {
          final detail = songState.detail;
          return BlocBuilder<PlaybackCubit, PlaybackState>(
            builder: (context, playbackState) {
              final orderedTrackSlots =
                  (detail?.trackSlots.toList(growable: true) ?? <TrackSlot>[])
                    ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
              final canPlayAllTracks = orderedTrackSlots.any(
                (slot) =>
                    playbackState.selectedTrackSlotIds.contains(slot.id) &&
                    (slot.currentTakeFilePath ?? '').isNotEmpty,
              );

              return Scaffold(
                appBar: AppBar(
                  title: Text(detail?.song.title ?? 'Song'),
                  actions: [
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: context.read<SongDetailCubit>().load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                body: detail == null
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: context.read<SongDetailCubit>().syncLatest,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _ActionsCard(
                              detail: detail,
                              songState: songState,
                              playbackState: playbackState,
                              canPlayAllTracks: canPlayAllTracks,
                              onSyncLatest: context
                                  .read<SongDetailCubit>()
                                  .syncLatest,
                              onAddMember: () async {
                                final email = await _showAddMemberDialog(
                                  context,
                                );
                                if (email == null || !context.mounted) return;
                                await context
                                    .read<SongDetailCubit>()
                                    .addMemberByEmail(email);
                              },
                              onExportMp3: context
                                  .read<SongDetailCubit>()
                                  .requestMp3Export,
                              onExportWav: context
                                  .read<SongDetailCubit>()
                                  .requestWavExport,
                              onPlayMix: detail.localMixPath == null
                                  ? null
                                  : () => context.read<PlaybackCubit>().playMix(
                                      detail.localMixPath!,
                                    ),
                              onPauseMix: context
                                  .read<PlaybackCubit>()
                                  .pauseSingle,
                              onPlayAllTracks: () =>
                                  context.read<PlaybackCubit>().playAllTracks(
                                    trackSlots: orderedTrackSlots,
                                  ),
                              onStopAllTracks: context
                                  .read<PlaybackCubit>()
                                  .stopAllTracks,
                              onSeekAllTracks: context
                                  .read<PlaybackCubit>()
                                  .seekAllTracks,
                              onRetryQueued: context
                                  .read<SongDetailCubit>()
                                  .retryQueuedUploads,
                            ),
                            const SizedBox(height: 12),
                            _MembersCard(members: detail.members),
                            const SizedBox(height: 12),
                            Text(
                              'Track Slots',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            ...orderedTrackSlots.map(
                              (slot) => _TrackSlotCard(
                                songId: detail.song.id,
                                slot: slot,
                                songState: songState,
                                playbackState: playbackState,
                                onToggleInclude: (selected) {
                                  context
                                      .read<PlaybackCubit>()
                                      .toggleTrackSelection(
                                        trackSlotId: slot.id,
                                        selected: selected,
                                      );
                                },
                                onStartRecording: () => context
                                    .read<SongDetailCubit>()
                                    .startRecording(
                                      trackSlotId: slot.id,
                                      slotIndex: slot.slotIndex,
                                    ),
                                onStopRecording: context
                                    .read<SongDetailCubit>()
                                    .stopRecording,
                                onRedoRecording: context
                                    .read<SongDetailCubit>()
                                    .redoRecording,
                                onSubmitRecording: context
                                    .read<SongDetailCubit>()
                                    .submitRecording,
                                onPlayTrack: () =>
                                    context.read<PlaybackCubit>().playTrack(
                                      trackSlot: slot,
                                    ),
                                onPauseTrack: context
                                    .read<PlaybackCubit>()
                                    .pauseTrack,
                                onSeekTrack: (position) =>
                                    context.read<PlaybackCubit>().seekTrack(
                                      trackSlot: slot,
                                      position: position,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Activity',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            _ActivityList(detail: detail),
                            if (songState.lastSubmitQueued)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  'Upload queued. It will retry when connectivity is restored.',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              ),
                            if (songState.errorMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  songState.errorMessage!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            if (playbackState.errorMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  playbackState.errorMessage!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}

Future<String?> _showAddMemberDialog(BuildContext context) async {
  var input = const MemberEmailInput.pure();
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add Member'),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Member email',
                errorText: input.displayError == null
                    ? null
                    : 'Enter a valid email',
              ),
              onChanged: (value) => setState(() {
                input = MemberEmailInput.dirty(value);
              }),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final validated = MemberEmailInput.dirty(
                    controller.text.trim(),
                  );
                  if (Formz.validate([validated])) {
                    Navigator.of(context).pop(validated.value.trim());
                  } else {
                    setState(() => input = validated);
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      );
    },
  );
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({
    required this.detail,
    required this.songState,
    required this.playbackState,
    required this.canPlayAllTracks,
    required this.onSyncLatest,
    required this.onAddMember,
    required this.onExportMp3,
    required this.onExportWav,
    required this.onPlayMix,
    required this.onPauseMix,
    required this.onPlayAllTracks,
    required this.onStopAllTracks,
    required this.onSeekAllTracks,
    required this.onRetryQueued,
  });

  final SongDetail detail;
  final SongDetailState songState;
  final PlaybackState playbackState;
  final bool canPlayAllTracks;
  final Future<void> Function() onSyncLatest;
  final Future<void> Function() onAddMember;
  final Future<void> Function() onExportMp3;
  final Future<void> Function() onExportWav;
  final Future<void> Function()? onPlayMix;
  final Future<void> Function() onPauseMix;
  final Future<void> Function() onPlayAllTracks;
  final Future<void> Function() onStopAllTracks;
  final Future<void> Function(Duration) onSeekAllTracks;
  final Future<void> Function() onRetryQueued;

  @override
  Widget build(BuildContext context) {
    final isMixPlaying =
        playbackState.isSinglePlaying && playbackState.isPlayingMix;
    final hasRenderedMix = detail.song.currentMixVersionId != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Latest mix: ${detail.song.currentMixPath ?? "none"}'),
            if (detail.localMixPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Local mix cache: ${detail.localMixPath}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: songState.isSyncing ? null : onSyncLatest,
                  icon: const Icon(Icons.sync),
                  label: Text(
                    songState.isSyncing ? 'Syncing...' : 'Sync latest',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onAddMember,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add member'),
                ),
                OutlinedButton.icon(
                  onPressed: hasRenderedMix ? onExportMp3 : null,
                  icon: const Icon(Icons.file_download),
                  label: Text(
                    hasRenderedMix ? 'Export MP3' : 'Export MP3 (mix required)',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: hasRenderedMix ? onExportWav : null,
                  icon: const Icon(Icons.file_download),
                  label: Text(
                    hasRenderedMix ? 'Export WAV' : 'Export WAV (mix required)',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onRetryQueued,
                  icon: const Icon(Icons.upload),
                  label: const Text('Retry uploads'),
                ),
                OutlinedButton.icon(
                  onPressed: isMixPlaying ? onPauseMix : onPlayMix,
                  icon: Icon(isMixPlaying ? Icons.pause : Icons.play_arrow),
                  label: Text(isMixPlaying ? 'Pause mix' : 'Play mix'),
                ),
                OutlinedButton.icon(
                  onPressed: playbackState.isPreparingAllTracks
                      ? null
                      : (playbackState.isPlayingAllTracks
                            ? onStopAllTracks
                            : (canPlayAllTracks ? onPlayAllTracks : null)),
                  icon: Icon(
                    playbackState.isPlayingAllTracks
                        ? Icons.stop
                        : Icons.play_circle,
                  ),
                  label: Text(
                    playbackState.isPreparingAllTracks
                        ? 'Preparing tracks...'
                        : (playbackState.isPlayingAllTracks
                              ? 'Stop all tracks'
                              : 'Play all tracks'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TimelineWaveformView(
              waveform: playbackState.playAllWaveform,
              position: playbackState.playAllPosition,
              isPreparing: playbackState.isPreparingAllTracks,
              onSeek: (duration) {
                unawaited(onSeekAllTracks(duration));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MembersCard extends StatelessWidget {
  const _MembersCard({
    required this.members,
  });

  final List<SongMember> members;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Members',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (members.isEmpty)
              const Text('No members found.')
            else
              ...members.map(
                (member) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person),
                  title: Text(member.userId),
                  subtitle: Text(member.role),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrackSlotCard extends StatelessWidget {
  const _TrackSlotCard({
    required this.songId,
    required this.slot,
    required this.songState,
    required this.playbackState,
    required this.onToggleInclude,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onRedoRecording,
    required this.onSubmitRecording,
    required this.onPlayTrack,
    required this.onPauseTrack,
    required this.onSeekTrack,
  });

  final String songId;
  final TrackSlot slot;
  final SongDetailState songState;
  final PlaybackState playbackState;
  final ValueChanged<bool> onToggleInclude;
  final Future<void> Function() onStartRecording;
  final Future<void> Function() onStopRecording;
  final Future<void> Function() onRedoRecording;
  final Future<void> Function() onSubmitRecording;
  final Future<void> Function() onPlayTrack;
  final Future<void> Function(String) onPauseTrack;
  final ValueChanged<Duration> onSeekTrack;

  @override
  Widget build(BuildContext context) {
    final isCurrentSlot = songState.pendingTrackSlotId == slot.id;
    final isRecordingThisSlot = isCurrentSlot && songState.isRecording;
    final hasPendingRecording =
        isCurrentSlot && songState.pendingRecordingPath != null;
    final hasSubmittedTake = (slot.currentTakeFilePath ?? '').isNotEmpty;
    final isIncludedInPlayAll = playbackState.selectedTrackSlotIds.contains(
      slot.id,
    );
    final isTrackPlaying = playbackState.playingTrackSlotIds.contains(slot.id);
    final isTrackInActivePlayAll =
        playbackState.isPlayingAllTracks &&
        hasSubmittedTake &&
        playbackState.selectedTrackSlotIds.contains(slot.id);
    final waveformState =
        playbackState.trackWaveforms[slot.id] ??
        const TrackWaveformState.initial();
    final trackPosition = isTrackInActivePlayAll
        ? playbackState.playAllPosition
        : (playbackState.trackPositions[slot.id] ?? Duration.zero);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Track ${slot.slotIndex}: ${slot.label}'),
            if (slot.currentTakeId != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Current take: ${slot.currentTakeId}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isRecordingThisSlot)
                  FilledButton.icon(
                    onPressed: onStopRecording,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  )
                else
                  FilledButton.icon(
                    onPressed: onStartRecording,
                    icon: const Icon(Icons.mic),
                    label: Text(hasSubmittedTake ? 'Record / Redo' : 'Record'),
                  ),
                if (hasPendingRecording)
                  OutlinedButton.icon(
                    onPressed: onRedoRecording,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Redo'),
                  ),
                if (hasPendingRecording)
                  OutlinedButton.icon(
                    onPressed: songState.isSubmittingTake
                        ? null
                        : onSubmitRecording,
                    icon: const Icon(Icons.cloud_upload),
                    label: Text(
                      songState.isSubmittingTake ? 'Submitting...' : 'Submit',
                    ),
                  ),
                if (hasSubmittedTake)
                  OutlinedButton.icon(
                    onPressed: isTrackPlaying
                        ? () => onPauseTrack(slot.id)
                        : onPlayTrack,
                    icon: Icon(isTrackPlaying ? Icons.pause : Icons.play_arrow),
                    label: Text(isTrackPlaying ? 'Pause track' : 'Play track'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: isIncludedInPlayAll,
                  onChanged: hasSubmittedTake
                      ? (value) => onToggleInclude(value ?? false)
                      : null,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Include in Play All',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (hasSubmittedTake)
              TrackWaveformView(
                waveformState: waveformState,
                position: trackPosition,
                onSeek: onSeekTrack,
              ),
            if (hasPendingRecording)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Pending local take: ${songState.pendingRecordingPath}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({
    required this.detail,
  });

  final SongDetail detail;

  @override
  Widget build(BuildContext context) {
    final rows = <_ActivityRow>[
      ...detail.renderJobs.map(_ActivityRow.render),
      ...detail.exportJobs.map(_ActivityRow.export),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return SizedBox(
      height: 220,
      child: InfiniteList(
        itemCount: rows.length,
        hasReachedMax: true,
        onFetchData: () async {},
        emptyBuilder: (context) => const Center(child: Text('No jobs yet.')),
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final row = rows[index];
          return ListTile(
            dense: true,
            title: Text(row.title),
            subtitle: Text(row.subtitle),
            trailing: Text(row.status.toUpperCase()),
          );
        },
      ),
    );
  }
}

class _ActivityRow {
  _ActivityRow({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.createdAt,
  });

  factory _ActivityRow.render(RenderJob job) {
    return _ActivityRow(
      title: 'Render job',
      subtitle: job.errorText ?? job.id,
      status: job.status,
      createdAt: job.createdAt,
    );
  }

  factory _ActivityRow.export(ExportJob job) {
    return _ActivityRow(
      title: 'Export ${job.outputFormat.toUpperCase()}',
      subtitle: job.outputFilePath ?? job.errorText ?? job.id,
      status: job.status,
      createdAt: job.createdAt,
    );
  }

  final String title;
  final String subtitle;
  final String status;
  final DateTime createdAt;
}
