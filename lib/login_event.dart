import 'package:zerotrust_contacts/auth_event.dart';
import 'package:nowa_runtime/nowa_runtime.dart';

@NowaGenerated()
class LoginEvent extends AuthEvent {
  LoginEvent(this.masterPassword);

  final String masterPassword;
}
