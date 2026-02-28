import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:formz/formz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:very_good_infinite_list/very_good_infinite_list.dart';

import 'package:multitrax_app/songs/cubit/song_list_cubit.dart';
import 'package:multitrax_app/songs/forms/song_forms.dart';
import 'package:multitrax_app/songs/repositories/song_repository.dart';
import 'package:multitrax_app/songs/view/song_detail_page.dart';

class SongListPage extends StatelessWidget {
  const SongListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final cubit = SongListCubit(
          songRepository: context.read<SongRepository>(),
        );
        unawaited(cubit.initialize());
        return cubit;
      },
      child: const _SongListView(),
    );
  }
}

class _SongListView extends StatelessWidget {
  const _SongListView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Songs'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => Supabase.instance.client.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final title = await _showCreateSongDialog(context);
          if (title == null || !context.mounted) return;
          await context.read<SongListCubit>().createSong(title);
        },
        icon: const Icon(Icons.add),
        label: const Text('New Song'),
      ),
      body: BlocBuilder<SongListCubit, SongListState>(
        builder: (context, state) {
          return Column(
            children: [
              if (state.pendingUploads > 0 || state.isFlushingUploads)
                MaterialBanner(
                  content: Text(
                    state.isFlushingUploads
                        ? 'Retrying queued uploads in background...'
                        : '${state.pendingUploads} take(s) queued for retry upload.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: state.isFlushingUploads
                          ? null
                          : () => context.read<SongListCubit>().initialize(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: context.read<SongListCubit>().refresh,
                  child: InfiniteList(
                    isLoading: state.isLoading,
                    hasReachedMax: state.hasReachedMax,
                    itemCount: state.songs.length,
                    onFetchData: context.read<SongListCubit>().fetchNextPage,
                    emptyBuilder: (context) {
                      if (state.errorMessage != null) {
                        return Center(child: Text(state.errorMessage!));
                      }
                      return const Center(
                        child: Text('No songs yet. Create your first song.'),
                      );
                    },
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final song = state.songs[index];
                      return ListTile(
                        title: Text(song.title),
                        subtitle: Text(
                          song.currentMixPath == null
                              ? 'No guide mix yet'
                              : 'Guide mix ready',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          unawaited(
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SongDetailPage(songId: song.id),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<String?> _showCreateSongDialog(BuildContext context) async {
    var input = const SongTitleInput.pure();
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Create Song'),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Song title',
                  errorText: input.displayError == null ? null : 'Title is required',
                ),
                onChanged: (value) {
                  setState(() {
                    input = SongTitleInput.dirty(value);
                  });
                },
                onSubmitted: (_) {
                  final validated = SongTitleInput.dirty(controller.text);
                  if (Formz.validate([validated])) {
                    Navigator.of(context).pop(validated.value.trim());
                  } else {
                    setState(() => input = validated);
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final validated = SongTitleInput.dirty(controller.text);
                    if (Formz.validate([validated])) {
                      Navigator.of(context).pop(validated.value.trim());
                    } else {
                      setState(() => input = validated);
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
