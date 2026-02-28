import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:multitrax_app/auth/view/auth_gate.dart';
import 'package:multitrax_app/core/storage/song_cache_store.dart';
import 'package:multitrax_app/core/storage/upload_queue_store.dart';
import 'package:multitrax_app/exports/export_service.dart';
import 'package:multitrax_app/l10n/l10n.dart';
import 'package:multitrax_app/playback/services/waveform_service.dart';
import 'package:multitrax_app/recording/recording_service.dart';
import 'package:multitrax_app/songs/repositories/song_repository.dart';
import 'package:multitrax_app/songs/repositories/supabase_song_repository.dart';
import 'package:multitrax_app/sync/song_sync_service.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(
          create: (_) => SongCacheStore(),
        ),
        RepositoryProvider(
          create: (_) => UploadQueueStore(),
        ),
        RepositoryProvider<SongRepository>(
          create: (context) => SupabaseSongRepository(
            client: Supabase.instance.client,
            cacheStore: context.read<SongCacheStore>(),
            uploadQueueStore: context.read<UploadQueueStore>(),
          ),
        ),
        RepositoryProvider(
          create: (context) => SongSyncService(context.read<SongRepository>()),
        ),
        RepositoryProvider(
          create: (context) => ExportService(context.read<SongRepository>()),
        ),
        RepositoryProvider(
          create: (context) => WaveformService(
            cacheStore: context.read<SongCacheStore>(),
          ),
        ),
        RepositoryProvider(
          create: (_) => RecordingService(),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(
          appBarTheme: AppBarTheme(
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          ),
          useMaterial3: true,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AuthGate(),
      ),
    );
  }
}
