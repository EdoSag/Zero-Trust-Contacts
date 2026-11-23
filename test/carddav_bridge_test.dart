import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_contacts/carddav/carddav_bridge.dart';
import 'package:zerotrust_contacts/carddav/carddav_responder.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

VaultContact contact(String id, String name, [Map<String, dynamic>? more]) =>
    VaultContact.fromJson(<String, dynamic>{
      'id': id,
      'displayName': name,
      'firstName': name.split(' ').first,
      'lastName': name.split(' ').last,
      ...?more,
    });

void main() {
  final List<DavCard> cards = <DavCard>[
    DavCard.of(
      contact('ada', 'Ada Lovelace', <String, dynamic>{
        'phones': <String>['+44 7700 900123'],
        'emails': <String>['ada@example.com'],
      }),
    ),
    DavCard.of(contact('id/with:odd chars', 'Grace <Hopper> & Co')),
    DavCard.of(
      contact('alan', 'Alan Turing'),
      photo: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD9]),
    ),
  ];
  final CardDavResponder responder = CardDavResponder(cards);

  DavResponse ask(
    String method,
    String path, {
    String? depth,
    String body = '',
  }) => responder.handle(
    DavRequest(method: method, path: path, depth: depth, body: body),
  );

  test('cards carry a UID and a stable, safe file name', () {
    expect(cards[0].name, 'ada.vcf');
    expect(cards[0].vcf, contains('VERSION:3.0\r\nUID:ada\r\n'));
    expect(cards[0].vcf, contains('TEL;TYPE=CELL:+44 7700 900123'));
    expect(cards[1].name, 'id-with-odd-chars.vcf');
    expect(cards[2].vcf, contains('PHOTO;ENCODING=b;TYPE=JPEG:/9j/2Q=='));
    expect(
      DavCard.of(
        contact('ada', 'Ada Lovelace', <String, dynamic>{
          'phones': <String>['+44 7700 900123'],
          'emails': <String>['ada@example.com'],
        }),
      ).etag,
      cards[0].etag,
    );
    expect(DavCard.of(contact('ada', 'Ada King')).etag, isNot(cards[0].etag));
  });

  test('discovery: well-known, principal, home, address book', () {
    expect(
      ask('GET', '/.well-known/carddav').headers['Location'],
      '/principal/',
    );
    expect(ask('OPTIONS', '/').headers['DAV'], contains('addressbook'));
    final DavResponse root = ask('PROPFIND', '/', depth: '0');
    expect(root.status, 207);
    expect(
      root.body,
      contains('<card:addressbook-home-set><d:href>/addressbooks/</d:href>'),
    );
    final DavResponse home = ask('PROPFIND', '/addressbooks/', depth: '1');
    expect(home.body, contains('<d:href>/addressbooks/contacts/</d:href>'));
    expect(home.body, contains('<card:addressbook/>'));
    expect(home.body, contains('<d:displayname>ZT Contacts</d:displayname>'));
    expect(
      ask('PROPFIND', '/addressbooks/', depth: '0').body,
      isNot(contains('/addressbooks/contacts/')),
    );
  });

  test('the address book lists one vCard per contact', () {
    final DavResponse list = ask(
      'PROPFIND',
      '/addressbooks/contacts/',
      depth: '1',
    );
    expect(list.status, 207);
    for (final DavCard c in cards) {
      expect(list.body, contains('/addressbooks/contacts/${c.name}'));
      expect(list.body, contains('<d:getetag>"${c.etag}"</d:getetag>'));
    }
    final DavResponse one = ask('GET', '/addressbooks/contacts/ada.vcf');
    expect(one.status, 200);
    expect(one.headers['Content-Type'], startsWith('text/vcard'));
    expect(one.headers['ETag'], '"${cards[0].etag}"');
    expect(one.body, cards[0].vcf);
    final DavResponse all = ask('GET', '/addressbooks/contacts/');
    expect('BEGIN:VCARD'.allMatches(all.body).length, 3);
  });

  test('multiget returns the asked cards with data, escaped', () {
    final DavResponse r = ask(
      'REPORT',
      '/addressbooks/contacts/',
      body: '''
<card:addressbook-multiget xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
  <d:prop><d:getetag/><card:address-data/></d:prop>
  <d:href>/addressbooks/contacts/id-with-odd-chars.vcf</d:href>
  <d:href>/addressbooks/contacts/missing.vcf</d:href>
</card:addressbook-multiget>''',
    );
    expect(r.status, 207);
    expect(r.body, contains('FN:Grace &lt;Hopper&gt; &amp; Co'));
    expect(r.body, isNot(contains('Ada Lovelace')));
    expect(r.body, contains('404 Not Found'));
    final DavResponse query = ask(
      'REPORT',
      '/addressbooks/contacts/',
      body:
          '<card:addressbook-query xmlns:d="DAV:" '
          'xmlns:card="urn:ietf:params:xml:ns:carddav"><d:prop>'
          '<card:address-data/></d:prop></card:addressbook-query>',
    );
    expect('<card:address-data>'.allMatches(query.body).length, 3);
  });

  test('sync-collection: full list, then nothing, old tokens refused', () {
    String sync(String token) =>
        '<d:sync-collection xmlns:d="DAV:">'
        '<d:sync-token>$token</d:sync-token><d:sync-level>1</d:sync-level>'
        '<d:prop><d:getetag/></d:prop></d:sync-collection>';
    final DavResponse first = ask(
      'REPORT',
      '/addressbooks/contacts/',
      body: sync(''),
    );
    expect(first.status, 207);
    expect(first.body, contains('ada.vcf'));
    final String token = RegExp(
      r'<d:sync-token>([^<]+)</',
    ).firstMatch(first.body)!.group(1)!;
    expect(token, responder.syncToken);
    expect(token, startsWith('urn:'));
    final DavResponse same = ask(
      'REPORT',
      '/addressbooks/contacts/',
      body: sync(token),
    );
    expect(same.status, 207);
    expect(same.body, isNot(contains('ada.vcf')));
    expect(same.body, contains(token));
    // A contact deleted on the phone changes the token: the app starts
    // over and drops it.
    final CardDavResponder fewer = CardDavResponder(cards.sublist(1));
    expect(fewer.syncToken, isNot(token));
    final DavResponse stale = fewer.handle(
      DavRequest(
        method: 'REPORT',
        path: '/addressbooks/contacts/',
        body: sync(token),
      ),
    );
    expect(stale.status, 403);
    expect(stale.body, contains('valid-sync-token'));
  });

  test('read-only: writes are refused, unknown paths 404', () {
    for (final String m in <String>[
      'PUT',
      'DELETE',
      'MKCOL',
      'PROPPATCH',
      'MOVE',
    ]) {
      expect(ask(m, '/addressbooks/contacts/ada.vcf').status, 403);
    }
    expect(ask('GET', '/addressbooks/other/').status, 404);
    expect(ask('GET', '/addressbooks/contacts/nope.vcf').status, 404);
    expect(ask('GET', '/addressbooks/contacts/ada.vcf/x').status, 404);
    expect(ask('GET', '/etc/passwd').status, 404);
  });

  test('basic auth is exact; throttle locks out after five failures', () {
    String header(String u, String p) =>
        'Basic ${base64.encode(utf8.encode('$u:$p'))}';
    expect(
      checkBasicAuth(header('zt', 'abcd-efgh'), 'zt', 'abcd-efgh'),
      isTrue,
    );
    expect(
      checkBasicAuth(header('zt', 'abcd-efg'), 'zt', 'abcd-efgh'),
      isFalse,
    );
    expect(checkBasicAuth('Basic !!!', 'zt', 'p'), isFalse);
    expect(checkBasicAuth(null, 'zt', 'p'), isFalse);

    DateTime now = DateTime(2026);
    final LoginThrottle t = LoginThrottle(clock: () => now);
    for (int i = 0; i < 5; i++) {
      expect(t.blocked('10.0.0.2'), isFalse);
      t.failed('10.0.0.2');
    }
    expect(t.blocked('10.0.0.2'), isTrue);
    expect(t.blocked('10.0.0.3'), isFalse);
    now = now.add(const Duration(minutes: 6));
    expect(t.blocked('10.0.0.2'), isFalse);
  });

  test('only local network addresses are answered', () {
    for (final String a in <String>[
      '192.168.1.5',
      '10.1.2.3',
      '172.16.0.1',
      '127.0.0.1',
      'fd12::1',
    ]) {
      expect(isLocalAddress(InternetAddress(a)), isTrue, reason: a);
    }
    for (final String a in <String>['8.8.8.8', '172.32.0.1', '2a00:1450::1']) {
      expect(isLocalAddress(InternetAddress(a)), isFalse, reason: a);
    }
  });

  test('the server answers over TLS only with the password', () async {
    final BridgeCredentials creds = BridgeCredentials.create();
    expect(
      creds.fingerprint,
      matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')),
    );
    expect(CardDavServer.defaultPort, isNot(8443)); // ZT Calendar's.
    final CardDavServer server = CardDavServer(
      credentials: creds,
      snapshot: () async => cards,
      port: 0,
    );
    await server.start();
    final HttpClient client = HttpClient()
      ..badCertificateCallback = (_, _, _) => true;
    Future<(int, String)> get(String? auth) async {
      final HttpClientRequest req = await client.openUrl(
        'PROPFIND',
        Uri.parse('https://127.0.0.1:${server.boundPort}/addressbooks/'),
      );
      req.headers.set('Depth', '1');
      if (auth != null) req.headers.set('Authorization', auth);
      final HttpClientResponse res = await req.close();
      return (res.statusCode, await res.transform(utf8.decoder).join());
    }

    expect((await get(null)).$1, 401);
    final (int, String) ok = await get(
      'Basic ${base64.encode(utf8.encode('zt:${creds.password}'))}',
    );
    expect(ok.$1, 207);
    expect(ok.$2, contains('/addressbooks/contacts/'));
    client.close(force: true);
    await server.stop();
  });
}
