import 'package:multitrax_app/songs/repositories/song_repository.dart';

class ExportService {
  ExportService(this._songRepository);

  final SongRepository _songRepository;

  Future<void> requestMp3Export(String songId) async {
    await _songRepository.queueExportJob(songId: songId, outputFormat: 'mp3');
  }

  Future<void> requestWavExport(String songId) async {
    await _songRepository.queueExportJob(songId: songId, outputFormat: 'wav');
  }
}
