import 'package:go_router/go_router.dart';
import 'package:zerotrust_contacts/auth_service.dart';
import 'package:zerotrust_contacts/integrations/supabase_service.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/pages/home_page.dart';
import 'package:zerotrust_contacts/pages/account_page.dart';
import 'package:zerotrust_contacts/pages/contact_detail_page.dart';
import 'package:zerotrust_contacts/pages/login_screen.dart';
import 'package:zerotrust_contacts/pages/merge_conflicts_page.dart';
import 'package:zerotrust_contacts/pages/create_contact_page.dart';
import 'package:zerotrust_contacts/pages/unlock_screen.dart';
import 'package:zerotrust_contacts/services/app_lock_service.dart';
import 'package:nowa_runtime/nowa_runtime.dart';

@NowaGenerated()
final GoRouter appRouter = GoRouter(
  refreshListenable: AppLockService(),
  initialLocation: '/',
  redirect: (context, state) async {
    final bool isAuthenticated = SupabaseService().currentUser != null;
    final bool isVaultInitialized =
        await AuthService().isLocalVaultInitialized();
    final bool onOnboarding = state.matchedLocation == '/onboarding';
    final bool onUnlock = state.matchedLocation == '/unlock';

    if (!isAuthenticated || !isVaultInitialized) {
      return onOnboarding ? null : '/onboarding';
    }

    if (AppLockService().isLockRequired && AppLockService().isLocked) {
      return onUnlock ? null : '/unlock';
    }

    if (onOnboarding || onUnlock) {
      return '/';
    }

    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomePage()),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/create-contact',
      builder: (context, state) => const CreateContactPage(),
    ),
    GoRoute(
      path: '/contact-detail',
      builder: (context, state) {
        final dynamic extra = state.extra;
        final Map<String, dynamic> payload = extra is Map
            ? Map<String, dynamic>.from(extra)
            : <String, dynamic>{};
        return ContactDetailPage(
          contact: VaultContact.fromJson(payload),
        );
      },
    ),
    GoRoute(path: '/account', builder: (context, state) => const AccountPage()),
    GoRoute(path: '/unlock', builder: (context, state) => const UnlockScreen()),
    GoRoute(
      path: '/merge-conflicts',
      builder: (context, state) => const MergeConflictsPage(),
    ),
  ],
);
