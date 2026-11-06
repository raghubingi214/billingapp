import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/env/app_environment.dart';
import '../core/widgets/status_view.dart';
import 'app.dart';
import 'theme/app_theme.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final environment = AppEnvironment.fromDefines()..validate();
    await Supabase.initialize(
      url: environment.supabaseUrl,
      publishableKey: environment.publishableKey,
    );
    runApp(const ProviderScope(child: SmartBillingApp()));
  } catch (_) {
    runApp(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: StatusView(
            title: 'Unable to start',
            message:
                'The app configuration could not be loaded. Please contact support.',
          ),
        ),
      ),
    );
  }
}
