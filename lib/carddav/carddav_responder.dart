import 'dart:convert';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter/foundation.dart';
import 'package:zerotrust_contacts/import/vcard_writer.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

/// One contact as the bridge offers it: its vCard, made once per change so
/// a desktop app polling every few minutes costs the phone little.
@immutable
class DavCard {
  const DavCard({required this.name, required this.vcf, required this.etag});

  /// [contact] as vCard 3.0 with its photo, and the `UID` that CardDAV
  /// needs (RFC 6352: every address object has one).
  factory DavCard.of(VaultContact contact, {Uint8List? photo}) {
    final String vcf = const VCardWriter()
        .write(contact, photo: photo)
        .replaceFirst(
          'VERSION:3.0\r\n',
          'VERSION:3.0\r\nUID:${_uid(contact.id)}\r\n',
        );
    return DavCard(
      name: '${_safe(contact.id)}.vcf',
      vcf: vcf,
      etag: CardDavResponder.digest(vcf),
    );
  }

  /// The resource's file name in the address book.
  final String name;
  final String vcf;

  /// Changes whenever the card does.
  final String etag;

  static String _safe(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');

  static String _uid(String id) =>
      id.replaceAll(RegExp(r'[\r\n;,\\]'), '-');
}

/// A request as the bridge received it.
@immutable
class DavRequest {
  const DavRequest({
    required this.method,
    required this.path,
    this.depth,
    this.body = '',
  });
  final String method;
  final String path;

  /// The `Depth` header: '0', '1' or 'infinity'; null when absent.
  final String? depth;
  final String body;
}

@immutable
class DavResponse {
  const DavResponse(this.status,
      {this.headers = const <String, String>{}, this.body = ''});
  final int status;
  final Map<String, String> headers;
  final String body;
}

/// A read-only CardDAV server's answers (C10), as pure functions of the
/// request and the cards, so they are tested without a network.
///
/// Layout:
/// - `/` and `/.well-known/carddav` point at the principal;
/// - `/principal/` names the address book home;
/// - `/addressbooks/` holds one address book, `contacts`;
/// - `/addressbooks/contacts/` holds one `.vcf` resource per contact;
/// - `GET /addressbooks/contacts/` returns every card as one .vcf file.
///
/// Writes (PUT, DELETE, MKCOL, PROPPATCH…) are refused: desktop apps read,
/// the phone stays the only place contacts are changed.
class CardDavResponder {
  CardDavResponder(this.cards, {this.name = 'ZT Contacts'});

  final List<DavCard> cards;

  /// The address book's name as desktop apps show it.
  final String name;

  static const String book = 'contacts';
  static const String _home = '/addressbooks/';
  static const String _bookPath = '/addressbooks/$book/';
  static const String _xml = 'application/xml; charset=utf-8';
  static const String _vcard = 'text/vcard; charset=utf-8';
  static const String _dav = '1, 3, addressbook';
  static const String _allow = 'OPTIONS, GET, HEAD, PROPFIND, REPORT';

  static String digest(String text) =>
      hash.sha256.convert(utf8.encode(text)).toString().substring(0, 24);

  late final Map<String, DavCard> _byName = <String, DavCard>{
    for (final DavCard c in cards) c.name: c,
  };

  late final List<DavCard> _sorted = cards.toList()
    ..sort((DavCard a, DavCard b) => a.name.compareTo(b.name));

  late final String _ctag = digest(
      '$name|${<String>[for (final DavCard c in _sorted) '${c.name}=${c.etag}'].join(',')}');

  /// RFC 6578 wants a URI.
  String get syncToken => 'urn:zt-contacts:sync:$_ctag';

  DavResponse handle(DavRequest r) {
    final String path = Uri.decodeFull(r.path.split('?').first);
    final List<String> parts =
        path.split('/').where((String p) => p.isNotEmpty).toList();
    if (r.method == 'OPTIONS') {
      return const DavResponse(200,
          headers: <String, String>{'DAV': _dav, 'Allow': _allow});
    }
    if (!const <String>{'GET', 'HEAD', 'PROPFIND', 'REPORT'}
        .contains(r.method)) {
      return const DavResponse(
        403,
        headers: <String, String>{'Allow': _allow},
        body: 'ZT Contacts shares contacts read-only. '
            'Change them on the phone.',
      );
    }
    if (parts.length >= 2 &&
        parts[0] == '.well-known' &&
        parts[1] == 'carddav') {
      return const DavResponse(301,
          headers: <String, String>{'Location': '/principal/'});
    }
    if (parts.isEmpty || parts[0] == 'principal') {
      if (r.method != 'PROPFIND') {
        return r.method == 'GET'
            ? const DavResponse(
                200,
                headers: <String, String>{
                  'Content-Type': 'text/plain; charset=utf-8',
                },
                body: 'ZT Contacts desktop bridge. Add this address as a '
                    'CardDAV account in your contacts app.',
              )
            : const DavResponse(405);
      }
      return _multistatus(
          <String>[_principal(parts.isEmpty ? '/' : '/principal/')]);
    }
    if (parts[0] != 'addressbooks') return const DavResponse(404);
    if (parts.length == 1) {
      if (r.method != 'PROPFIND') return const DavResponse(405);
      return _multistatus(<String>[
        _homeResponse(),
        if (r.depth != '0') _collection(),
      ]);
    }
    if (parts[1] != book) return const DavResponse(404);
    if (parts.length == 2) {
      switch (r.method) {
        case 'GET' || 'HEAD':
          return DavResponse(
            200,
            headers: <String, String>{
              'Content-Type': _vcard,
              'ETag': '"$_ctag"',
            },
            body: r.method == 'HEAD'
                ? ''
                : <String>[for (final DavCard c in _sorted) c.vcf].join(),
          );
        case 'PROPFIND':
          return _multistatus(<String>[
            _collection(),
            if (r.depth != '0')
              for (final DavCard c in _sorted) _resource(c, false),
          ]);
        default: // REPORT
          return _report(r.body);
      }
    }
    if (parts.length > 3) return const DavResponse(404);
    final DavCard? card = _byName[parts[2]];
    if (card == null) return const DavResponse(404);
    switch (r.method) {
      case 'GET' || 'HEAD':
        return DavResponse(
          200,
          headers: <String, String>{
            'Content-Type': _vcard,
            'ETag': '"${card.etag}"',
          },
          body: r.method == 'HEAD' ? '' : card.vcf,
        );
      case 'PROPFIND':
        return _multistatus(<String>[_resource(card, false)]);
      default:
        return const DavResponse(405);
    }
  }

  // ---- XML --------------------------------------------------------------

  static String _esc(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  DavResponse _multistatus(List<String> responses, {String extra = ''}) =>
      DavResponse(
        207,
        headers: const <String, String>{'Content-Type': _xml, 'DAV': _dav},
        body: '<?xml version="1.0" encoding="utf-8"?>\n'
            '<d:multistatus xmlns:d="DAV:" '
            'xmlns:card="urn:ietf:params:xml:ns:carddav" '
            'xmlns:cs="http://calendarserver.org/ns/">'
            '${responses.join()}$extra</d:multistatus>',
      );

  static String _ok(String href, String props) =>
      '<d:response><d:href>${_esc(href)}</d:href><d:propstat><d:prop>'
      '$props</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
      '</d:response>';

  String get _principalProps =>
      '<d:current-user-principal><d:href>/principal/</d:href>'
      '</d:current-user-principal>'
      '<d:principal-URL><d:href>/principal/</d:href></d:principal-URL>'
      '<card:addressbook-home-set><d:href>$_home</d:href>'
      '</card:addressbook-home-set>'
      '<d:displayname>${_esc(name)}</d:displayname>';

  String _principal(String href) => _ok(
        href,
        '<d:resourcetype><d:principal/></d:resourcetype>$_principalProps',
      );

  String _homeResponse() => _ok(
        _home,
        '<d:resourcetype><d:collection/></d:resourcetype>$_principalProps',
      );

  String _collection() => _ok(
        _bookPath,
        '<d:resourcetype><d:collection/><card:addressbook/></d:resourcetype>'
            '<d:displayname>${_esc(name)}</d:displayname>'
            '<cs:getctag>$_ctag</cs:getctag>'
            '<d:sync-token>${_esc(syncToken)}</d:sync-token>'
            '<card:supported-address-data>'
            '<card:address-data-type content-type="text/vcard" version="3.0"/>'
            '</card:supported-address-data>'
            '<d:current-user-privilege-set><d:privilege><d:read/></d:privilege>'
            '</d:current-user-privilege-set>'
            '<d:current-user-principal><d:href>/principal/</d:href>'
            '</d:current-user-principal>',
      );

  String _resource(DavCard c, bool withData) => _ok(
        '$_bookPath${c.name}',
        '<d:resourcetype/>'
            '<d:getcontenttype>text/vcard; charset=utf-8</d:getcontenttype>'
            '<d:getetag>"${c.etag}"</d:getetag>'
            '${withData ? '<card:address-data>${_esc(c.vcf)}</card:address-data>' : ''}',
      );

  /// addressbook-multiget (the hrefs asked for) and addressbook-query
  /// (every card; filters are left to the app), and sync-collection.
  DavResponse _report(String body) {
    if (body.contains('addressbook-multiget')) {
      final Set<String> hrefs = RegExp(r'<(?:[A-Za-z0-9_-]+:)?href>([^<]*)</')
          .allMatches(body)
          .map((Match m) => Uri.decodeFull(m.group(1)!.trim()).split('/').last)
          .toSet();
      return _multistatus(<String>[
        for (final DavCard c in _sorted)
          if (hrefs.contains(c.name)) _resource(c, true),
        for (final String h in hrefs)
          if (!_byName.containsKey(h))
            '<d:response><d:href>${_esc('$_bookPath$h')}</d:href>'
                '<d:status>HTTP/1.1 404 Not Found</d:status></d:response>',
      ]);
    }
    if (body.contains('sync-collection')) {
      // No change history on the phone (RFC 6578): an empty token gets
      // everything, the current token gets "nothing changed", and any older
      // token is refused with valid-sync-token so the app does a full
      // resync and drops contacts deleted on the phone.
      final String token = RegExp(r'<(?:[A-Za-z0-9_-]+:)?sync-token>([^<]*)</')
              .firstMatch(body)
              ?.group(1)
              ?.trim() ??
          '';
      if (token.isNotEmpty && token != syncToken) {
        return const DavResponse(
          403,
          headers: <String, String>{'Content-Type': _xml, 'DAV': _dav},
          body: '<?xml version="1.0" encoding="utf-8"?>'
              '<d:error xmlns:d="DAV:"><d:valid-sync-token/></d:error>',
        );
      }
      return _multistatus(
        <String>[
          if (token.isEmpty)
            for (final DavCard c in _sorted) _resource(c, false),
        ],
        extra: '<d:sync-token>${_esc(syncToken)}</d:sync-token>',
      );
    }
    final bool withData = body.contains('address-data');
    return _multistatus(
        <String>[for (final DavCard c in _sorted) _resource(c, withData)]);
  }
}
