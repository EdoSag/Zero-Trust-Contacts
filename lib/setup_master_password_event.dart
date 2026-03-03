import 'package:zerotrust_contacts/auth_event.dart';
import 'package:nowa_runtime/nowa_runtime.dart';

@NowaGenerated()
class SetupMasterPasswordEvent extends AuthEvent {
  SetupMasterPasswordEvent(this.masterPassword);

  final String masterPassword;
}
