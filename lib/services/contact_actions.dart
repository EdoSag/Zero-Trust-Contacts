/// Links that open other apps for a contact: dialer, messages, mail,
/// WhatsApp, Signal and maps. Pure Dart so they can be unit tested; the
/// detail page opens them with url_launcher.
///
/// Nothing is sent anywhere by building these: the other app only gets the
/// one number, address or email the user tapped.
class ContactActions {
  const ContactActions._();

  /// Digits with an optional leading `+`, as dialers and messengers expect.
  static String dialable(String phone) {
    final String trimmed = phone.trim();
    final String digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    return trimmed.startsWith('+') || trimmed.startsWith('00')
        ? '+${trimmed.startsWith('00') ? digits.substring(2) : digits}'
        : digits;
  }

  static Uri? call(String phone) {
    final String number = dialable(phone);
    return number.replaceAll('+', '').isEmpty
        ? null
        : Uri(scheme: 'tel', path: number);
  }

  static Uri? text(String phone) {
    final String number = dialable(phone);
    return number.replaceAll('+', '').isEmpty
        ? null
        : Uri(scheme: 'sms', path: number);
  }

  static Uri? email(String address) {
    final String trimmed = address.trim();
    return trimmed.contains('@') ? Uri(scheme: 'mailto', path: trimmed) : null;
  }

  /// WhatsApp needs the number in international form; a local number is
  /// passed as is and WhatsApp says if it can't find it.
  static Uri? whatsApp(String phone) {
    final String digits = dialable(phone).replaceAll('+', '');
    return digits.isEmpty ? null : Uri.https('wa.me', '/$digits');
  }

  /// Signal only opens numbers in international form (`+44...`), so this is
  /// null for a local number.
  static Uri? signal(String phone) {
    final String number = dialable(phone);
    if (!number.startsWith('+') || number.length < 8) return null;
    return Uri.parse('https://signal.me/#p/$number');
  }

  /// Directions to [address] in the phone's maps app. On Android `geo:` lets
  /// the user pick any maps app (including offline ones); iOS opens Apple
  /// Maps.
  static Uri? directions(String address, {required bool isIOS}) {
    final String trimmed = address.trim();
    if (trimmed.isEmpty) return null;
    return isIOS
        ? Uri.https('maps.apple.com', '/', <String, String>{'q': trimmed})
        : Uri.parse('geo:0,0?q=${Uri.encodeQueryComponent(trimmed)}');
  }
}
