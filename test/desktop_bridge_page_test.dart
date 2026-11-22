import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/carddav/carddav_bridge.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';
import 'package:zerotrust_contacts/pages/desktop_bridge_page.dart';

class FakeBridge extends DesktopBridgeController {
  FakeBridge(this.initial);
  final DesktopBridgeState initial;

  @override
  DesktopBridgeState build() => initial;

  @override
  Future<void> refreshAddress() async {}
}

void main() {
  testWidgets('the page shows what to type, in order, each copyable', (
    WidgetTester tester,
  ) async {
    const BridgeCredentials creds = BridgeCredentials(
      username: 'zt',
      password: 'abcd-efgh-jkmn-pqrs-tuvw',
      certPem: '',
      keyPem: '',
      fingerprint: 'AB:CD',
    );
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopBridgeProvider.overrideWith(
            () => FakeBridge(
              const DesktopBridgeState(
                enabled: true,
                running: true,
                address: '192.168.1.20',
                credentials: creds,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ZtTheme.light(),
          localizationsDelegates: const <LocalizationsDelegate<Object?>>[
            AppL10n.delegate,
            ...ZtLanguages.delegates,
          ],
          supportedLocales: ZtLanguages.supported,
          home: const DesktopBridgePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder toggle = find.byType(SwitchListTile);
    final Finder address = find.text('https://192.168.1.20:8444/');
    final Finder user = find.text('zt');
    final Finder password = find.text(creds.password);
    for (final Finder f in <Finder>[toggle, address, user, password]) {
      expect(f, findsOneWidget);
    }
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(top(toggle), lessThan(top(address)));
    expect(top(address), lessThan(top(user)));
    expect(top(user), lessThan(top(password)));
    // Each value has its copy button on the same row, at the end.
    final Finder copies = find.byIcon(Icons.copy);
    expect(copies, findsNWidgets(3));
    for (final (int i, Finder value) in <(int, Finder)>[
      (0, address),
      (1, user),
      (2, password),
    ]) {
      final Rect button = tester.getRect(copies.at(i));
      final Rect text = tester.getRect(value);
      expect(button.left, greaterThan(text.right));
      expect(button.top, lessThan(text.bottom));
      expect(button.bottom, greaterThan(text.top));
      expect(button.right, lessThanOrEqualTo(1080 / 2.5));
    }
  });
}
