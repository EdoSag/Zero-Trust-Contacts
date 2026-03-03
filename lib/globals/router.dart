import 'package:go_router/go_router.dart';
import 'package:zerotrust_contacts/auth_service.dart';
import 'package:zerotrust_contacts/integrations/supabase_service.dart';
import 'package:zerotrust_contacts/pages/home_page.dart';
import 'package:zerotrust_contacts/pages/account_page.dart';
import 'package:zerotrust_contacts/pages/login_screen.dart';
import 'package:zerotrust_contacts/pages/create_contact_page.dart';
import 'package:nowa_runtime/nowa_runtime.dart';

@NowaGenerated()
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) async {
    final bool isAuthenticated = SupabaseService().currentUser != null;
    final bool isVaultInitialized =
        await AuthService().isLocalVaultInitialized();
    final bool onOnboarding = state.matchedLocation == '/onboarding';

    if (!isAuthenticated || !isVaultInitialized) {
      return onOnboarding ? null : '/onboarding';
    }

    if (onOnboarding) {
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
    GoRoute(path: '/account', builder: (context, state) => const AccountPage()),
  ],
);
