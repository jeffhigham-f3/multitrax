import 'package:multitrax_app/songs/models/song_models.dart';
import 'package:multitrax_app/songs/repositories/song_repository.dart';

class SongSyncService {
  SongSyncService(this._songRepository);

  final SongRepository _songRepository;

  Future<SongDetail> syncSongState(String songId) async {
    final detail = await _songRepository.fetchSongDetail(songId);
    final localMixPath = await _songRepository.syncLatestMix(
      songId: songId,
      mixPath: detail.song.currentMixPath,
    );

    if (localMixPath == null) {
      return detail;
    }

    return detail.copyWith(localMixPath: localMixPath);
  }
}
