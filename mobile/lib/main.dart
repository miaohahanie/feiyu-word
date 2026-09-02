import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'app_state.dart';
import 'data/app_database.dart';
import 'data/settings_repository.dart';
import 'data/word_repository.dart';
import 'sync/pairing_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.instance.database;

  final settings = SettingsRepository();
  final repository = WordRepository();
  final pairing = PairingService(settings: settings, repository: repository);
  final state = AppState(repository: repository, settings: settings, pairing: pairing);
  await state.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        Provider.value(value: settings),
        Provider.value(value: repository),
        Provider.value(value: pairing),
      ],
      child: const WordPetApp(),
    ),
  );
}
