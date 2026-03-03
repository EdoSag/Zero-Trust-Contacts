import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:zerotrust_contacts/integrations/supabase_service.dart';
import 'package:zerotrust_contacts/config/app_config.dart';
import 'package:zerotrust_contacts/auth_service.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zerotrust_contacts/globals/app_state.dart';
import 'package:zerotrust_contacts/globals/router.dart';
import 'package:zerotrust_contacts/services/app_lock_service.dart';
import 'package:zerotrust_contacts/services/vault_sync_scheduler.dart';

@NowaGenerated()
late final SharedPreferences sharedPrefs;

@NowaGenerated()
main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  AppConfig.loadFromEnvOrThrow();
  sharedPrefs = await SharedPreferences.getInstance();
  await SupabaseService().initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  await AuthService().restoreLocalVaultForActiveSession();
  await AppLockService().initialize();
  await VaultSyncScheduler().start();
  runApp(const MyApp());
}

@NowaGenerated({'visibleInNowa': false})
class MyApp extends StatelessWidget {
  @NowaGenerated({'loader': 'auto-constructor'})
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>(create: (context) => AppState()),
      ],
      builder: (context, child) => Listener(
        onPointerDown: (_) => AppLockService().recordInteraction(),
        child: MaterialApp.router(
          theme: AppState.of(context).theme,
          routerConfig: appRouter,
        ),
      ),
    );
  }
}
