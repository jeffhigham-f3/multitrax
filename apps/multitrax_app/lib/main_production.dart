import 'package:multitrax_app/app/app.dart';
import 'package:multitrax_app/bootstrap.dart';

Future<void> main() async {
  await bootstrap(() => const App());
}
