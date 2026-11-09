import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/app_gate.dart';

const ZtAppConfig contactsAppConfig = ZtAppConfig(
  appId: 'contacts',
  displayName: 'Zero-Trust Contacts',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  runApp(
    ProviderScope(
      overrides: [ztAppConfigProvider.overrideWithValue(contactsAppConfig)],
      child: const ZeroTrustContactsApp(),
    ),
  );
}

class ZeroTrustContactsApp extends ConsumerWidget {
  const ZeroTrustContactsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ZtThemeBuilder(
      builder: (context, theme, darkTheme, mode) => MaterialApp(
        // On-device task switcher label; the store name is Zero-Trust Contacts.
        title: 'ZT Contacts',
        theme: theme,
        darkTheme: darkTheme,
        themeMode: mode,
        home: const AppGate(),
        // Any touch on any screen, including ones pushed over the list
        // (editor, settings, imports), counts as activity for auto-lock.
        builder: (BuildContext context, Widget? child) => Listener(
          onPointerDown: (_) =>
              ref.read(vaultControllerProvider.notifier).touch(),
          child: child,
        ),
      ),
    );
  }
}
