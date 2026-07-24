import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _loadEnv();
  runApp(const ProviderScope(child: EpdfToolApp()));
}

/// Load `.env.local` when present (developer override, gitignored),
/// otherwise fall back to the tracked `.env.prod`. Missing files throw
/// on `rootBundle.loadString`, which is what we use to probe for local.
Future<void> _loadEnv() async {
  const localPath = 'assets/env/.env.local';
  const prodPath = 'assets/env/.env.prod';
  try {
    await rootBundle.loadString(localPath);
    await dotenv.load(fileName: localPath);
  } on Object {
    await dotenv.load(fileName: prodPath);
  }
}
