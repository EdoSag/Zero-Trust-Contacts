import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Downloads contact photos that a vCard only links to (Google's exports
/// link each photo on googleusercontent.com instead of embedding it).
///
/// Only used when the user turns it on: it connects to the server that
/// hosts the photo, which then sees this phone's IP address. Nothing about
/// the vault is sent; the request carries no cookies or account.
class PhotoDownloader {
  PhotoDownloader({HttpClient? client})
    : _client = client ?? (HttpClient()..userAgent = 'ZT Contacts');

  final HttpClient _client;

  static const int maxBytes = 3 * 1024 * 1024;
  static const Duration timeout = Duration(seconds: 20);

  /// The image at [url], or null if it isn't an https image under
  /// [maxBytes] that arrives within [timeout].
  Future<Uint8List?> download(Uri url) async {
    if (url.scheme != 'https') return null;
    try {
      final HttpClientRequest request = await _client
          .getUrl(url)
          .timeout(timeout);
      final HttpClientResponse response = await request.close().timeout(
        timeout,
      );
      final String type = response.headers.contentType?.primaryType ?? '';
      if (response.statusCode != HttpStatus.ok || type != 'image') {
        await response.drain<void>();
        return null;
      }
      final BytesBuilder bytes = BytesBuilder(copy: false);
      await for (final List<int> chunk in response.timeout(timeout)) {
        bytes.add(chunk);
        if (bytes.length > maxBytes) return null;
      }
      return bytes.takeBytes();
    } on Object {
      return null;
    }
  }

  void close() => _client.close(force: true);
}
