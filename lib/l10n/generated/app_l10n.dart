import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_l10n_en.dart';
import 'app_l10n_he.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_l10n.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('he'),
  ];

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @bringOverYourContactsFrom.
  ///
  /// In en, this message translates to:
  /// **'Bring over your contacts from before the update'**
  String get bringOverYourContactsFrom;

  /// No description provided for @contactsNowUsesYourZero.
  ///
  /// In en, this message translates to:
  /// **'Contacts now uses your Zero-Trust account. Enter your password once to move your earlier contacts across.'**
  String get contactsNowUsesYourZero;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @bringOver.
  ///
  /// In en, this message translates to:
  /// **'Bring over'**
  String get bringOver;

  /// No description provided for @thatPasswordDoesntOpenYour.
  ///
  /// In en, this message translates to:
  /// **'That password doesn\'t open your earlier contacts. If you changed it since, use the one from before.'**
  String get thatPasswordDoesntOpenYour;

  /// No description provided for @couldntBringThemOverCheck.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t bring them over. Check your connection and try again.'**
  String get couldntBringThemOverCheck;

  /// No description provided for @earlierContacts.
  ///
  /// In en, this message translates to:
  /// **'Earlier contacts'**
  String get earlierContacts;

  /// No description provided for @enterThePasswordYouUsed.
  ///
  /// In en, this message translates to:
  /// **'Enter the password you used in Contacts before this update. It\'s only needed once; nothing is sent to the server.'**
  String get enterThePasswordYouUsed;

  /// No description provided for @passwordFromBefore.
  ///
  /// In en, this message translates to:
  /// **'Password from before'**
  String get passwordFromBefore;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @changesUndoneOnEveryDevice.
  ///
  /// In en, this message translates to:
  /// **'Changes undone on every device.'**
  String get changesUndoneOnEveryDevice;

  /// No description provided for @blockContact.
  ///
  /// In en, this message translates to:
  /// **'Block contact'**
  String get blockContact;

  /// No description provided for @thisContactWillBeMarked.
  ///
  /// In en, this message translates to:
  /// **'This contact will be marked as blocked.'**
  String get thisContactWillBeMarked;

  /// No description provided for @reasonOptional.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get reasonOptional;

  /// No description provided for @eGSpamUnwantedContact.
  ///
  /// In en, this message translates to:
  /// **'e.g. Spam, unwanted contact…'**
  String get eGSpamUnwantedContact;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @unblockContact.
  ///
  /// In en, this message translates to:
  /// **'Unblock contact'**
  String get unblockContact;

  /// No description provided for @thisContactWillBeUnblocked.
  ///
  /// In en, this message translates to:
  /// **'This contact will be unblocked.'**
  String get thisContactWillBeUnblocked;

  /// No description provided for @unblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblock;

  /// No description provided for @whatsappIsntInstalledOrDoesnt.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp isn\'t installed, or doesn\'t know this number.'**
  String get whatsappIsntInstalledOrDoesnt;

  /// No description provided for @signalIsntInstalled.
  ///
  /// In en, this message translates to:
  /// **'Signal isn\'t installed.'**
  String get signalIsntInstalled;

  /// No description provided for @noAppOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'No app on this phone can open that.'**
  String get noAppOnThisPhone;

  /// No description provided for @scanWithAnotherPhonesCamera.
  ///
  /// In en, this message translates to:
  /// **'Scan with another phone\'s camera to add this contact. Anyone who can see the code can read it.'**
  String get scanWithAnotherPhonesCamera;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @secureSharePackage.
  ///
  /// In en, this message translates to:
  /// **'Secure share package'**
  String get secureSharePackage;

  /// No description provided for @copyBothPackageAndPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Copy both package and passphrase to share securely.'**
  String get copyBothPackageAndPassphrase;

  /// No description provided for @passphraseCopied.
  ///
  /// In en, this message translates to:
  /// **'Passphrase copied'**
  String get passphraseCopied;

  /// No description provided for @copyPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Copy passphrase'**
  String get copyPassphrase;

  /// No description provided for @packageCopied.
  ///
  /// In en, this message translates to:
  /// **'Package copied'**
  String get packageCopied;

  /// No description provided for @copyPackage.
  ///
  /// In en, this message translates to:
  /// **'Copy package'**
  String get copyPackage;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @company.
  ///
  /// In en, this message translates to:
  /// **'Company'**
  String get company;

  /// No description provided for @birthday.
  ///
  /// In en, this message translates to:
  /// **'Birthday'**
  String get birthday;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @call.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get call;

  /// No description provided for @text.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get text;

  /// No description provided for @directions.
  ///
  /// In en, this message translates to:
  /// **'Directions'**
  String get directions;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @shareAsVcard.
  ///
  /// In en, this message translates to:
  /// **'Share as vCard'**
  String get shareAsVcard;

  /// No description provided for @showQrCode.
  ///
  /// In en, this message translates to:
  /// **'Show QR code'**
  String get showQrCode;

  /// No description provided for @encryptedShare.
  ///
  /// In en, this message translates to:
  /// **'Encrypted share'**
  String get encryptedShare;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @saveToTheVault.
  ///
  /// In en, this message translates to:
  /// **'Save to the vault'**
  String get saveToTheVault;

  /// No description provided for @undoChanges.
  ///
  /// In en, this message translates to:
  /// **'Undo changes'**
  String get undoChanges;

  /// No description provided for @moveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to trash'**
  String get moveToTrash;

  /// No description provided for @blocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get blocked;

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favorite;

  /// No description provided for @pin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// No description provided for @noPhone.
  ///
  /// In en, this message translates to:
  /// **'no phone'**
  String get noPhone;

  /// No description provided for @noEmail.
  ///
  /// In en, this message translates to:
  /// **'no email'**
  String get noEmail;

  /// No description provided for @noCompany.
  ///
  /// In en, this message translates to:
  /// **'no company'**
  String get noCompany;

  /// No description provided for @otherAddress.
  ///
  /// In en, this message translates to:
  /// **'other address'**
  String get otherAddress;

  /// No description provided for @otherLabels.
  ///
  /// In en, this message translates to:
  /// **'other labels'**
  String get otherLabels;

  /// No description provided for @otherNotes.
  ///
  /// In en, this message translates to:
  /// **'other notes'**
  String get otherNotes;

  /// No description provided for @otherBirthday.
  ///
  /// In en, this message translates to:
  /// **'other birthday'**
  String get otherBirthday;

  /// No description provided for @notAFavourite.
  ///
  /// In en, this message translates to:
  /// **'not a favourite'**
  String get notAFavourite;

  /// No description provided for @notBlocked.
  ///
  /// In en, this message translates to:
  /// **'not blocked'**
  String get notBlocked;

  /// No description provided for @smallDifferences.
  ///
  /// In en, this message translates to:
  /// **'Small differences'**
  String get smallDifferences;

  /// No description provided for @goBackToThisVersion.
  ///
  /// In en, this message translates to:
  /// **'Go back to this version?'**
  String get goBackToThisVersion;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get goBack;

  /// No description provided for @noEarlierVersionsOfThis.
  ///
  /// In en, this message translates to:
  /// **'No earlier versions of this contact on this phone yet.\nVersions come from the daily, weekly and before-import restore points.'**
  String get noEarlierVersionsOfThis;

  /// No description provided for @chooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get chooseFromGallery;

  /// No description provided for @takeAPhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get takeAPhoto;

  /// No description provided for @removePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get removePhoto;

  /// No description provided for @addAtLeastOneContact.
  ///
  /// In en, this message translates to:
  /// **'Add at least one contact detail to save.'**
  String get addAtLeastOneContact;

  /// No description provided for @youMayAlreadyHaveThis.
  ///
  /// In en, this message translates to:
  /// **'You may already have this contact'**
  String get youMayAlreadyHaveThis;

  /// No description provided for @youMayAlreadyHaveThese.
  ///
  /// In en, this message translates to:
  /// **'You may already have these contacts'**
  String get youMayAlreadyHaveThese;

  /// No description provided for @addTheNewDetailsTo.
  ///
  /// In en, this message translates to:
  /// **'Add the new details to this contact'**
  String get addTheNewDetailsTo;

  /// No description provided for @openThisContactInstead.
  ///
  /// In en, this message translates to:
  /// **'Open this contact instead'**
  String get openThisContactInstead;

  /// No description provided for @tapAContactToAdd.
  ///
  /// In en, this message translates to:
  /// **'Tap a contact to add the new details to it, or save a separate contact anyway.'**
  String get tapAContactToAdd;

  /// No description provided for @saveAnyway.
  ///
  /// In en, this message translates to:
  /// **'Save anyway'**
  String get saveAnyway;

  /// No description provided for @selectBirthday.
  ///
  /// In en, this message translates to:
  /// **'Select birthday'**
  String get selectBirthday;

  /// No description provided for @noLabel.
  ///
  /// In en, this message translates to:
  /// **'No label'**
  String get noLabel;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @editContact.
  ///
  /// In en, this message translates to:
  /// **'Edit contact'**
  String get editContact;

  /// No description provided for @newContact.
  ///
  /// In en, this message translates to:
  /// **'New contact'**
  String get newContact;

  /// No description provided for @removeFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get removeFromFavorites;

  /// No description provided for @addToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get addToFavorites;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @firstName.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get firstName;

  /// No description provided for @lastName.
  ///
  /// In en, this message translates to:
  /// **'Last name'**
  String get lastName;

  /// No description provided for @addPhone.
  ///
  /// In en, this message translates to:
  /// **'Add phone'**
  String get addPhone;

  /// No description provided for @withCountryCodeLike972.
  ///
  /// In en, this message translates to:
  /// **'With country code, like +972 50 123 4567'**
  String get withCountryCodeLike972;

  /// No description provided for @addEmail.
  ///
  /// In en, this message translates to:
  /// **'Add email'**
  String get addEmail;

  /// No description provided for @addAddress.
  ///
  /// In en, this message translates to:
  /// **'Add address'**
  String get addAddress;

  /// No description provided for @streetCityCountry.
  ///
  /// In en, this message translates to:
  /// **'Street, city, country'**
  String get streetCityCountry;

  /// No description provided for @addBirthday.
  ///
  /// In en, this message translates to:
  /// **'Add birthday'**
  String get addBirthday;

  /// No description provided for @label.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get label;

  /// No description provided for @addLabel.
  ///
  /// In en, this message translates to:
  /// **'Add label'**
  String get addLabel;

  /// No description provided for @familyWorkGym.
  ///
  /// In en, this message translates to:
  /// **'Family, Work, Gym…'**
  String get familyWorkGym;

  /// No description provided for @websiteOrOther.
  ///
  /// In en, this message translates to:
  /// **'Website or other'**
  String get websiteOrOther;

  /// No description provided for @addWebsiteOrOtherDetail.
  ///
  /// In en, this message translates to:
  /// **'Add website or other detail'**
  String get addWebsiteOrOtherDetail;

  /// No description provided for @readingThisIphonesContacts.
  ///
  /// In en, this message translates to:
  /// **'Reading this iPhone\'s contacts…'**
  String get readingThisIphonesContacts;

  /// No description provided for @iphoneContacts.
  ///
  /// In en, this message translates to:
  /// **'iPhone contacts'**
  String get iphoneContacts;

  /// No description provided for @reading.
  ///
  /// In en, this message translates to:
  /// **'Reading…'**
  String get reading;

  /// No description provided for @thatFileIsNotA.
  ///
  /// In en, this message translates to:
  /// **'That file is not a contacts export. In Google Contacts choose Export, then \"vCard (for iOS Contacts)\".'**
  String get thatFileIsNotA;

  /// No description provided for @encryptingAndSaving.
  ///
  /// In en, this message translates to:
  /// **'Encrypting and saving…'**
  String get encryptingAndSaving;

  /// No description provided for @everythingWasAlreadyInYour.
  ///
  /// In en, this message translates to:
  /// **'Everything was already in your vault.'**
  String get everythingWasAlreadyInYour;

  /// No description provided for @importContacts.
  ///
  /// In en, this message translates to:
  /// **'Import contacts'**
  String get importContacts;

  /// No description provided for @importFromGoogle.
  ///
  /// In en, this message translates to:
  /// **'Import from Google'**
  String get importFromGoogle;

  /// No description provided for @googleAccountsOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Google accounts on this phone'**
  String get googleAccountsOnThisPhone;

  /// No description provided for @allowAccessToContacts.
  ///
  /// In en, this message translates to:
  /// **'Allow access to contacts'**
  String get allowAccessToContacts;

  /// No description provided for @neededToReadTheGoogle.
  ///
  /// In en, this message translates to:
  /// **'Needed to read the Google contacts already on this phone.'**
  String get neededToReadTheGoogle;

  /// No description provided for @allow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allow;

  /// No description provided for @noGoogleContactsOnThis.
  ///
  /// In en, this message translates to:
  /// **'No Google contacts on this phone'**
  String get noGoogleContactsOnThis;

  /// No description provided for @addYourGoogleAccountIn.
  ///
  /// In en, this message translates to:
  /// **'Add your Google account in Android Settings, or use an export file below.'**
  String get addYourGoogleAccountIn;

  /// No description provided for @contactsOnThisIphone.
  ///
  /// In en, this message translates to:
  /// **'Contacts on this iPhone'**
  String get contactsOnThisIphone;

  /// No description provided for @ztContactsIsNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'ZT Contacts is not allowed to read your contacts. Turn it on in the iPhone Settings app under Privacy & Security, Contacts, then try again.'**
  String get ztContactsIsNotAllowed;

  /// No description provided for @copiesEverythingTheIphoneContacts.
  ///
  /// In en, this message translates to:
  /// **'Copies everything the iPhone Contacts app shows (iCloud and other accounts) into your vault. You see what will change before anything is saved, and people you already have are merged, not doubled.'**
  String get copiesEverythingTheIphoneContacts;

  /// No description provided for @importFromThisIphone.
  ///
  /// In en, this message translates to:
  /// **'Import from this iPhone'**
  String get importFromThisIphone;

  /// No description provided for @googleContactsExportFile.
  ///
  /// In en, this message translates to:
  /// **'Google Contacts export file'**
  String get googleContactsExportFile;

  /// No description provided for @openContactsGoogleComAnd.
  ///
  /// In en, this message translates to:
  /// **'Open contacts.google.com and tap Export.'**
  String get openContactsGoogleComAnd;

  /// No description provided for @chooseVcardForIosContacts.
  ///
  /// In en, this message translates to:
  /// **'Choose \"vCard (for iOS Contacts)\" and save the file.'**
  String get chooseVcardForIosContacts;

  /// No description provided for @pickThatFileHere.
  ///
  /// In en, this message translates to:
  /// **'Pick that file here.'**
  String get pickThatFileHere;

  /// No description provided for @chooseExportFile.
  ///
  /// In en, this message translates to:
  /// **'Choose export file'**
  String get chooseExportFile;

  /// No description provided for @readyToImport.
  ///
  /// In en, this message translates to:
  /// **'Ready to import'**
  String get readyToImport;

  /// No description provided for @newLabel.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newLabel;

  /// No description provided for @updated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get updated;

  /// No description provided for @alreadyHere.
  ///
  /// In en, this message translates to:
  /// **'Already here'**
  String get alreadyHere;

  /// No description provided for @everythingInThisSourceIs.
  ///
  /// In en, this message translates to:
  /// **'Everything in this source is already in your vault.'**
  String get everythingInThisSourceIs;

  /// No description provided for @thisExportLinksToPhotos.
  ///
  /// In en, this message translates to:
  /// **'This export links to photos instead of including them. Downloading connects to Google\'s photo server, which sees this phone\'s address. Photos are then encrypted like everything else.'**
  String get thisExportLinksToPhotos;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @nothingToImport.
  ///
  /// In en, this message translates to:
  /// **'Nothing to import'**
  String get nothingToImport;

  /// No description provided for @importPhotos.
  ///
  /// In en, this message translates to:
  /// **'Import photos'**
  String get importPhotos;

  /// No description provided for @noGoogleSignInNeeded.
  ///
  /// In en, this message translates to:
  /// **'No Google sign-in needed. Your contacts are read on this device and encrypted before they are saved or synced.'**
  String get noGoogleSignInNeeded;

  /// No description provided for @createANewContact.
  ///
  /// In en, this message translates to:
  /// **'Create a new contact'**
  String get createANewContact;

  /// No description provided for @addToAContactI.
  ///
  /// In en, this message translates to:
  /// **'Add to a contact I already have'**
  String get addToAContactI;

  /// No description provided for @searchYourContacts.
  ///
  /// In en, this message translates to:
  /// **'Search your contacts'**
  String get searchYourContacts;

  /// No description provided for @searchNamePhoneEmailNotes.
  ///
  /// In en, this message translates to:
  /// **'Search name, phone, email, notes'**
  String get searchNamePhoneEmailNotes;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @sort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// No description provided for @firstNameAToZ.
  ///
  /// In en, this message translates to:
  /// **'First name, A to Z'**
  String get firstNameAToZ;

  /// No description provided for @lastNameAToZ.
  ///
  /// In en, this message translates to:
  /// **'Last name, A to Z'**
  String get lastNameAToZ;

  /// No description provided for @recentlyChanged.
  ///
  /// In en, this message translates to:
  /// **'Recently changed'**
  String get recentlyChanged;

  /// No description provided for @bySource.
  ///
  /// In en, this message translates to:
  /// **'By source'**
  String get bySource;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @source.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get source;

  /// No description provided for @addALabel.
  ///
  /// In en, this message translates to:
  /// **'Add a label'**
  String get addALabel;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @merge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get merge;

  /// No description provided for @cancelSelection.
  ///
  /// In en, this message translates to:
  /// **'Cancel selection'**
  String get cancelSelection;

  /// No description provided for @selectNone.
  ///
  /// In en, this message translates to:
  /// **'Select none'**
  String get selectNone;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @bringYourIphoneContacts.
  ///
  /// In en, this message translates to:
  /// **'Bring your iPhone contacts'**
  String get bringYourIphoneContacts;

  /// No description provided for @bringYourGoogleContacts.
  ///
  /// In en, this message translates to:
  /// **'Bring your Google contacts'**
  String get bringYourGoogleContacts;

  /// No description provided for @importThemIntoYourEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Import them into your encrypted vault in a few taps.'**
  String get importThemIntoYourEncrypted;

  /// No description provided for @importLabel.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importLabel;

  /// No description provided for @contactsPermissionDeniedShowingVault.
  ///
  /// In en, this message translates to:
  /// **'Contacts permission denied. Showing vault-only contacts.'**
  String get contactsPermissionDeniedShowingVault;

  /// No description provided for @noContactsMatchTheCurrent.
  ///
  /// In en, this message translates to:
  /// **'No contacts match the current filters.'**
  String get noContactsMatchTheCurrent;

  /// No description provided for @pinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinned;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @frequent.
  ///
  /// In en, this message translates to:
  /// **'Frequent'**
  String get frequent;

  /// No description provided for @noHighlightsYetStarPin.
  ///
  /// In en, this message translates to:
  /// **'No highlights yet. Star/pin contacts to see them here.'**
  String get noHighlightsYetStarPin;

  /// No description provided for @trash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trash;

  /// No description provided for @deletedContactsKeptFor30.
  ///
  /// In en, this message translates to:
  /// **'Deleted contacts, kept for 30 days'**
  String get deletedContactsKeptFor30;

  /// No description provided for @scanAContactQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan a contact QR code'**
  String get scanAContactQrCode;

  /// No description provided for @addAContactSomeoneShows.
  ///
  /// In en, this message translates to:
  /// **'Add a contact someone shows you'**
  String get addAContactSomeoneShows;

  /// No description provided for @scanABusinessCard.
  ///
  /// In en, this message translates to:
  /// **'Scan a business card'**
  String get scanABusinessCard;

  /// No description provided for @readOnThisPhoneThe.
  ///
  /// In en, this message translates to:
  /// **'Read on this phone, the picture is never uploaded'**
  String get readOnThisPhoneThe;

  /// No description provided for @labels.
  ///
  /// In en, this message translates to:
  /// **'Labels'**
  String get labels;

  /// No description provided for @manageLabels.
  ///
  /// In en, this message translates to:
  /// **'Manage labels'**
  String get manageLabels;

  /// No description provided for @noLabelsYet.
  ///
  /// In en, this message translates to:
  /// **'No labels yet'**
  String get noLabelsYet;

  /// No description provided for @smartGroups.
  ///
  /// In en, this message translates to:
  /// **'Smart groups'**
  String get smartGroups;

  /// No description provided for @duplicateCleanup.
  ///
  /// In en, this message translates to:
  /// **'Duplicate cleanup'**
  String get duplicateCleanup;

  /// No description provided for @noDuplicatesDetected.
  ///
  /// In en, this message translates to:
  /// **'No duplicates detected'**
  String get noDuplicatesDetected;

  /// No description provided for @contacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get contacts;

  /// No description provided for @highlights.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get highlights;

  /// No description provided for @organize.
  ///
  /// In en, this message translates to:
  /// **'Organize'**
  String get organize;

  /// No description provided for @labelName.
  ///
  /// In en, this message translates to:
  /// **'Label name'**
  String get labelName;

  /// No description provided for @addAContactFirstThen.
  ///
  /// In en, this message translates to:
  /// **'Add a contact first, then you can put it in a label.'**
  String get addAContactFirstThen;

  /// No description provided for @newLabelX.
  ///
  /// In en, this message translates to:
  /// **'New label'**
  String get newLabelX;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @noLabelsYetMakeOne.
  ///
  /// In en, this message translates to:
  /// **'No labels yet. Make one for family, a team or a class, then email or text everyone in it at once.'**
  String get noLabelsYetMakeOne;

  /// No description provided for @renameLabel.
  ///
  /// In en, this message translates to:
  /// **'Rename label'**
  String get renameLabel;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @theContactsStayOnlyThe.
  ///
  /// In en, this message translates to:
  /// **'The contacts stay. Only the label is taken off them.'**
  String get theContactsStayOnlyThe;

  /// No description provided for @deleteLabel.
  ///
  /// In en, this message translates to:
  /// **'Delete label'**
  String get deleteLabel;

  /// No description provided for @everyContactAlreadyHasThis.
  ///
  /// In en, this message translates to:
  /// **'Every contact already has this label.'**
  String get everyContactAlreadyHasThis;

  /// No description provided for @nobodyHereHasAnEmail.
  ///
  /// In en, this message translates to:
  /// **'Nobody here has an email address.'**
  String get nobodyHereHasAnEmail;

  /// No description provided for @noMailAppCouldBe.
  ///
  /// In en, this message translates to:
  /// **'No mail app could be opened.'**
  String get noMailAppCouldBe;

  /// No description provided for @nobodyHereHasAPhone.
  ///
  /// In en, this message translates to:
  /// **'Nobody here has a phone number.'**
  String get nobodyHereHasAPhone;

  /// No description provided for @noMessagesAppCouldBe.
  ///
  /// In en, this message translates to:
  /// **'No messages app could be opened.'**
  String get noMessagesAppCouldBe;

  /// No description provided for @clearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get clearSelection;

  /// No description provided for @removeFromLabel.
  ///
  /// In en, this message translates to:
  /// **'Remove from label'**
  String get removeFromLabel;

  /// No description provided for @addContacts.
  ///
  /// In en, this message translates to:
  /// **'Add contacts'**
  String get addContacts;

  /// No description provided for @emailAll.
  ///
  /// In en, this message translates to:
  /// **'Email all'**
  String get emailAll;

  /// No description provided for @textAll.
  ///
  /// In en, this message translates to:
  /// **'Text all'**
  String get textAll;

  /// No description provided for @nobodyHasThisLabelAny.
  ///
  /// In en, this message translates to:
  /// **'Nobody has this label any more.'**
  String get nobodyHasThisLabelAny;

  /// No description provided for @searchContacts.
  ///
  /// In en, this message translates to:
  /// **'Search contacts'**
  String get searchContacts;

  /// No description provided for @syncConflicts.
  ///
  /// In en, this message translates to:
  /// **'Sync conflicts'**
  String get syncConflicts;

  /// No description provided for @noConflictsWhenTheSame.
  ///
  /// In en, this message translates to:
  /// **'No conflicts. When the same contact is edited on two devices, the newer edit is kept and yours shows up here.'**
  String get noConflictsWhenTheSame;

  /// No description provided for @deletedOnAnotherDeviceAfter.
  ///
  /// In en, this message translates to:
  /// **'Deleted on another device after you edited it.'**
  String get deletedOnAnotherDeviceAfter;

  /// No description provided for @editedOnAnotherDeviceAfter.
  ///
  /// In en, this message translates to:
  /// **'Edited on another device after your edit.'**
  String get editedOnAnotherDeviceAfter;

  /// No description provided for @keepDeleted.
  ///
  /// In en, this message translates to:
  /// **'Keep deleted'**
  String get keepDeleted;

  /// No description provided for @keepTheNewerOne.
  ///
  /// In en, this message translates to:
  /// **'Keep the newer one'**
  String get keepTheNewerOne;

  /// No description provided for @useMine.
  ///
  /// In en, this message translates to:
  /// **'Use mine'**
  String get useMine;

  /// No description provided for @combine.
  ///
  /// In en, this message translates to:
  /// **'Combine'**
  String get combine;

  /// No description provided for @qrCode.
  ///
  /// In en, this message translates to:
  /// **'QR code'**
  String get qrCode;

  /// No description provided for @thatCodeIsNotA.
  ///
  /// In en, this message translates to:
  /// **'That code is not a contact.'**
  String get thatCodeIsNotA;

  /// No description provided for @allowTheCameraForZt.
  ///
  /// In en, this message translates to:
  /// **'Allow the camera for ZT Contacts in the phone\'s settings to scan a code.'**
  String get allowTheCameraForZt;

  /// No description provided for @pointTheCameraAtA.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at a contact QR code. It is read on this phone only.'**
  String get pointTheCameraAtA;

  /// No description provided for @bringOverContactsFromBefore.
  ///
  /// In en, this message translates to:
  /// **'Bring over contacts from before the update'**
  String get bringOverContactsFromBefore;

  /// No description provided for @needsYourPasswordFromBefore.
  ///
  /// In en, this message translates to:
  /// **'Needs your password from before, once'**
  String get needsYourPasswordFromBefore;

  /// No description provided for @showInPhoneAndMessages.
  ///
  /// In en, this message translates to:
  /// **'Show in Phone and Messages'**
  String get showInPhoneAndMessages;

  /// No description provided for @onCallerIdAndThe.
  ///
  /// In en, this message translates to:
  /// **'On: caller ID and the dialer show your contacts'**
  String get onCallerIdAndThe;

  /// No description provided for @offCallsFromContactsShow.
  ///
  /// In en, this message translates to:
  /// **'Off: calls from contacts show only the number'**
  String get offCallsFromContactsShow;

  /// No description provided for @fromThisIphoneOrA.
  ///
  /// In en, this message translates to:
  /// **'From this iPhone, or a Google export'**
  String get fromThisIphoneOrA;

  /// No description provided for @accountsOnThisPhoneOr.
  ///
  /// In en, this message translates to:
  /// **'Accounts on this phone, or a Google export'**
  String get accountsOnThisPhoneOr;

  /// No description provided for @restorePoints.
  ///
  /// In en, this message translates to:
  /// **'Restore points'**
  String get restorePoints;

  /// No description provided for @undoAnImportMergeOr.
  ///
  /// In en, this message translates to:
  /// **'Undo an import, merge or restore'**
  String get undoAnImportMergeOr;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @activityOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Activity on this device'**
  String get activityOnThisDevice;

  /// No description provided for @saveAnEncryptedBackup.
  ///
  /// In en, this message translates to:
  /// **'Save an encrypted backup'**
  String get saveAnEncryptedBackup;

  /// No description provided for @aFileSealedWithA.
  ///
  /// In en, this message translates to:
  /// **'A file sealed with a passphrase you choose'**
  String get aFileSealedWithA;

  /// No description provided for @copyToTheClipboardInstead.
  ///
  /// In en, this message translates to:
  /// **'Copy to the clipboard instead'**
  String get copyToTheClipboardInstead;

  /// No description provided for @restoreAnEncryptedBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore an encrypted backup'**
  String get restoreAnEncryptedBackup;

  /// No description provided for @fromABackupFile.
  ///
  /// In en, this message translates to:
  /// **'From a backup file'**
  String get fromABackupFile;

  /// No description provided for @pasteTheBackupTextInstead.
  ///
  /// In en, this message translates to:
  /// **'Paste the backup text instead'**
  String get pasteTheBackupTextInstead;

  /// No description provided for @exportContactsAsAVcard.
  ///
  /// In en, this message translates to:
  /// **'Export contacts as a vCard file'**
  String get exportContactsAsAVcard;

  /// No description provided for @notEncryptedWorksWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Not encrypted. Works with Google, Apple and other apps'**
  String get notEncryptedWorksWithGoogle;

  /// No description provided for @importAVcardFile.
  ///
  /// In en, this message translates to:
  /// **'Import a vCard file'**
  String get importAVcardFile;

  /// No description provided for @aVcfFileFromAny.
  ///
  /// In en, this message translates to:
  /// **'A .vcf file from any contacts app'**
  String get aVcfFileFromAny;

  /// No description provided for @pasteVcardTextInstead.
  ///
  /// In en, this message translates to:
  /// **'Paste vCard text instead'**
  String get pasteVcardTextInstead;

  /// No description provided for @exportEncryptedBackup.
  ///
  /// In en, this message translates to:
  /// **'Export encrypted backup'**
  String get exportEncryptedBackup;

  /// No description provided for @passphrase8Characters.
  ///
  /// In en, this message translates to:
  /// **'Passphrase (8+ characters)'**
  String get passphrase8Characters;

  /// No description provided for @thePassphraseNeedsAtLeast.
  ///
  /// In en, this message translates to:
  /// **'The passphrase needs at least 8 characters.'**
  String get thePassphraseNeedsAtLeast;

  /// No description provided for @encryptedBackupCopiedToThe.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup copied to the clipboard.'**
  String get encryptedBackupCopiedToThe;

  /// No description provided for @encryptedBackupSaved.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup saved.'**
  String get encryptedBackupSaved;

  /// No description provided for @nothingWasSaved.
  ///
  /// In en, this message translates to:
  /// **'Nothing was saved.'**
  String get nothingWasSaved;

  /// No description provided for @restoreEncryptedBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore encrypted backup'**
  String get restoreEncryptedBackup;

  /// No description provided for @backupText.
  ///
  /// In en, this message translates to:
  /// **'Backup text'**
  String get backupText;

  /// No description provided for @passphrase.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get passphrase;

  /// No description provided for @theBackupAndItsPassphrase.
  ///
  /// In en, this message translates to:
  /// **'The backup and its passphrase are both needed.'**
  String get theBackupAndItsPassphrase;

  /// No description provided for @thereAreNoContactsTo.
  ///
  /// In en, this message translates to:
  /// **'There are no contacts to export yet.'**
  String get thereAreNoContactsTo;

  /// No description provided for @vcardCopiedToTheClipboard.
  ///
  /// In en, this message translates to:
  /// **'vCard copied to the clipboard.'**
  String get vcardCopiedToTheClipboard;

  /// No description provided for @importVcard.
  ///
  /// In en, this message translates to:
  /// **'Import vCard'**
  String get importVcard;

  /// No description provided for @pasteVcardText.
  ///
  /// In en, this message translates to:
  /// **'Paste vCard text'**
  String get pasteVcardText;

  /// No description provided for @deleteForGood.
  ///
  /// In en, this message translates to:
  /// **'Delete for good?'**
  String get deleteForGood;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deletedForGood.
  ///
  /// In en, this message translates to:
  /// **'Deleted for good.'**
  String get deletedForGood;

  /// No description provided for @emptyTheTrash.
  ///
  /// In en, this message translates to:
  /// **'Empty the trash?'**
  String get emptyTheTrash;

  /// No description provided for @emptyTrash.
  ///
  /// In en, this message translates to:
  /// **'Empty trash'**
  String get emptyTrash;

  /// No description provided for @theTrashIsEmptyDeleted.
  ///
  /// In en, this message translates to:
  /// **'The trash is empty.\nDeleted contacts stay here for 30 days.'**
  String get theTrashIsEmptyDeleted;

  /// No description provided for @contactsInTheTrashAre.
  ///
  /// In en, this message translates to:
  /// **'Contacts in the trash are deleted for good after 30 days.'**
  String get contactsInTheTrashAre;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @deleteForGoodX.
  ///
  /// In en, this message translates to:
  /// **'Delete for good'**
  String get deleteForGoodX;

  /// No description provided for @deletedForGoodToday.
  ///
  /// In en, this message translates to:
  /// **'Deleted for good today'**
  String get deletedForGoodToday;

  /// No description provided for @restoreThisPoint.
  ///
  /// In en, this message translates to:
  /// **'Restore this point?'**
  String get restoreThisPoint;

  /// No description provided for @restorePointSaved.
  ///
  /// In en, this message translates to:
  /// **'Restore point saved.'**
  String get restorePointSaved;

  /// No description provided for @saveNow.
  ///
  /// In en, this message translates to:
  /// **'Save now'**
  String get saveNow;

  /// No description provided for @noRestorePointsYet.
  ///
  /// In en, this message translates to:
  /// **'No restore points yet.'**
  String get noRestorePointsYet;

  /// No description provided for @noActivityYet.
  ///
  /// In en, this message translates to:
  /// **'No activity yet.'**
  String get noActivityYet;

  /// No description provided for @contactsPermissionIsNeededTo.
  ///
  /// In en, this message translates to:
  /// **'Contacts permission is needed to show contacts in the Phone and Messages apps.'**
  String get contactsPermissionIsNeededTo;

  /// No description provided for @removeFromThePhone.
  ///
  /// In en, this message translates to:
  /// **'Remove from the phone?'**
  String get removeFromThePhone;

  /// No description provided for @theCopiesInThePhones.
  ///
  /// In en, this message translates to:
  /// **'The copies in the phone\'s contacts are removed. Your contacts stay in the vault. Calls will show numbers instead of names.'**
  String get theCopiesInThePhones;

  /// No description provided for @phoneAndMessages.
  ///
  /// In en, this message translates to:
  /// **'Phone and Messages'**
  String get phoneAndMessages;

  /// No description provided for @showContactsInPhoneAnd.
  ///
  /// In en, this message translates to:
  /// **'Show contacts in Phone and Messages'**
  String get showContactsInPhoneAnd;

  /// No description provided for @callerIdTheDialerAnd.
  ///
  /// In en, this message translates to:
  /// **'Caller ID, the dialer and messaging apps see names'**
  String get callerIdTheDialerAnd;

  /// No description provided for @thisPutsAnUnencryptedCopy.
  ///
  /// In en, this message translates to:
  /// **'This puts an unencrypted copy of the details you pick below in the phone\'s own contacts, under a \"ZT Contacts\" account. Any app you allow to read contacts can see that copy. Your vault stays encrypted and is still where you edit contacts; the copy updates while the app is unlocked and is removed when you turn this off or sign out.'**
  String get thisPutsAnUnencryptedCopy;

  /// No description provided for @whatLeavesTheVault.
  ///
  /// In en, this message translates to:
  /// **'What leaves the vault'**
  String get whatLeavesTheVault;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @alwaysSoCallsShowWho.
  ///
  /// In en, this message translates to:
  /// **'Always, so calls show who it is'**
  String get alwaysSoCallsShowWho;

  /// No description provided for @phoneNumbers.
  ///
  /// In en, this message translates to:
  /// **'Phone numbers'**
  String get phoneNumbers;

  /// No description provided for @neededForCallerId.
  ///
  /// In en, this message translates to:
  /// **'Needed for caller ID'**
  String get neededForCallerId;

  /// No description provided for @photos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photos;

  /// No description provided for @emailAddresses.
  ///
  /// In en, this message translates to:
  /// **'Email addresses'**
  String get emailAddresses;

  /// No description provided for @addresses.
  ///
  /// In en, this message translates to:
  /// **'Addresses'**
  String get addresses;

  /// No description provided for @birthdays.
  ///
  /// In en, this message translates to:
  /// **'Birthdays'**
  String get birthdays;

  /// No description provided for @favourites.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get favourites;

  /// No description provided for @starredInThePhoneToo.
  ///
  /// In en, this message translates to:
  /// **'Starred in the phone too'**
  String get starredInThePhoneToo;

  /// No description provided for @sendBlockedContactsToVoicemail.
  ///
  /// In en, this message translates to:
  /// **'Send blocked contacts to voicemail'**
  String get sendBlockedContactsToVoicemail;

  /// No description provided for @updatingThePhonesContacts.
  ///
  /// In en, this message translates to:
  /// **'Updating the phone\'s contacts…'**
  String get updatingThePhonesContacts;

  /// No description provided for @waitingToUpdate.
  ///
  /// In en, this message translates to:
  /// **'Waiting to update'**
  String get waitingToUpdate;

  /// No description provided for @updateNow.
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get updateNow;

  /// No description provided for @theCardIsReadOn.
  ///
  /// In en, this message translates to:
  /// **'The card is read on this phone. The picture is not uploaded and is deleted once it has been read.'**
  String get theCardIsReadOn;

  /// No description provided for @takeAPhotoOfThe.
  ///
  /// In en, this message translates to:
  /// **'Take a photo of the card'**
  String get takeAPhotoOfThe;

  /// No description provided for @chooseAPhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose a photo'**
  String get chooseAPhoto;

  /// No description provided for @readingTheCard.
  ///
  /// In en, this message translates to:
  /// **'Reading the card…'**
  String get readingTheCard;

  /// No description provided for @noDetailsCouldBeRead.
  ///
  /// In en, this message translates to:
  /// **'No details could be read from that picture. Try again in good light with the card filling the frame.'**
  String get noDetailsCouldBeRead;

  /// No description provided for @jumpToALetter.
  ///
  /// In en, this message translates to:
  /// **'Jump to a letter'**
  String get jumpToALetter;

  /// No description provided for @nContacts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 contact} other{{count} contacts}}'**
  String nContacts(int count);

  /// No description provided for @typeMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get typeMobile;

  /// No description provided for @typeHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get typeHome;

  /// No description provided for @typeWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get typeWork;

  /// No description provided for @typeMain.
  ///
  /// In en, this message translates to:
  /// **'Main'**
  String get typeMain;

  /// No description provided for @typeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get typeOther;

  /// No description provided for @phoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phoneLabel;

  /// No description provided for @unnamedContact.
  ///
  /// In en, this message translates to:
  /// **'Unnamed Contact'**
  String get unnamedContact;

  /// No description provided for @srcSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get srcSaved;

  /// No description provided for @srcAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get srcAccount;

  /// No description provided for @srcSim.
  ///
  /// In en, this message translates to:
  /// **'SIM'**
  String get srcSim;

  /// No description provided for @rpBeforeMerging.
  ///
  /// In en, this message translates to:
  /// **'Before merging duplicates'**
  String get rpBeforeMerging;

  /// No description provided for @rpDaily.
  ///
  /// In en, this message translates to:
  /// **'Automatic daily restore point'**
  String get rpDaily;

  /// No description provided for @rpWeekly.
  ///
  /// In en, this message translates to:
  /// **'Automatic weekly restore point'**
  String get rpWeekly;

  /// No description provided for @rpBeforeRestoring.
  ///
  /// In en, this message translates to:
  /// **'Before restoring a restore point'**
  String get rpBeforeRestoring;

  /// No description provided for @rpBeforeReplacing.
  ///
  /// In en, this message translates to:
  /// **'Before replacing local contacts'**
  String get rpBeforeReplacing;

  /// No description provided for @rpManual.
  ///
  /// In en, this message translates to:
  /// **'Manual restore point'**
  String get rpManual;

  /// No description provided for @dupSimilar.
  ///
  /// In en, this message translates to:
  /// **'Similar contacts'**
  String get dupSimilar;

  /// No description provided for @dupPhone.
  ///
  /// In en, this message translates to:
  /// **'Same phone number'**
  String get dupPhone;

  /// No description provided for @dupEmail.
  ///
  /// In en, this message translates to:
  /// **'Same email'**
  String get dupEmail;

  /// No description provided for @dupName.
  ///
  /// In en, this message translates to:
  /// **'Same display name'**
  String get dupName;

  /// No description provided for @rpBeforeImport.
  ///
  /// In en, this message translates to:
  /// **'Before import from {source}'**
  String rpBeforeImport(String source);

  /// No description provided for @cantOpenContacts.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open your contacts on this device. {error}'**
  String cantOpenContacts(String error);

  /// No description provided for @broughtOver.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Brought over 1 contact.} other{Brought over {count} contacts.}}'**
  String broughtOver(int count);

  /// No description provided for @movedToTrash.
  ///
  /// In en, this message translates to:
  /// **'{name} moved to the trash'**
  String movedToTrash(String name);

  /// No description provided for @couldntShare.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t share: {error}'**
  String couldntShare(String error);

  /// No description provided for @qrCodeFor.
  ///
  /// In en, this message translates to:
  /// **'QR code for {name}'**
  String qrCodeFor(String name);

  /// No description provided for @passphraseValue.
  ///
  /// In en, this message translates to:
  /// **'Passphrase: {value}'**
  String passphraseValue(String value);

  /// No description provided for @expiresAt.
  ///
  /// In en, this message translates to:
  /// **'Expires: {date}'**
  String expiresAt(String date);

  /// No description provided for @textNumber.
  ///
  /// In en, this message translates to:
  /// **'Text {number}'**
  String textNumber(String number);

  /// No description provided for @interactionCount.
  ///
  /// In en, this message translates to:
  /// **'Interaction count: {count}'**
  String interactionCount(int count);

  /// No description provided for @histName.
  ///
  /// In en, this message translates to:
  /// **'name: {value}'**
  String histName(String value);

  /// No description provided for @histPhone.
  ///
  /// In en, this message translates to:
  /// **'phone: {value}'**
  String histPhone(String value);

  /// No description provided for @histEmail.
  ///
  /// In en, this message translates to:
  /// **'email: {value}'**
  String histEmail(String value);

  /// No description provided for @histCompany.
  ///
  /// In en, this message translates to:
  /// **'company: {value}'**
  String histCompany(String value);

  /// No description provided for @histFavourite.
  ///
  /// In en, this message translates to:
  /// **'favourite'**
  String get histFavourite;

  /// No description provided for @histBlocked.
  ///
  /// In en, this message translates to:
  /// **'blocked'**
  String get histBlocked;

  /// No description provided for @goesBackTo.
  ///
  /// In en, this message translates to:
  /// **'{name} goes back to how it was on {date}, on every device. The photo stays as it is now.'**
  String goesBackTo(String name, String date);

  /// No description provided for @failedToSaveContact.
  ///
  /// In en, this message translates to:
  /// **'Failed to save contact: {error}'**
  String failedToSaveContact(String error);

  /// No description provided for @whatToDoWith.
  ///
  /// In en, this message translates to:
  /// **'What to do with {name}'**
  String whatToDoWith(String name);

  /// No description provided for @readingName.
  ///
  /// In en, this message translates to:
  /// **'Reading {name}…'**
  String readingName(String name);

  /// No description provided for @encryptingPhotos.
  ///
  /// In en, this message translates to:
  /// **'Encrypting photos… {done} of {total}'**
  String encryptingPhotos(int done, int total);

  /// No description provided for @nAdded.
  ///
  /// In en, this message translates to:
  /// **'{count} added'**
  String nAdded(int count);

  /// No description provided for @nUpdated.
  ///
  /// In en, this message translates to:
  /// **'{count} updated'**
  String nUpdated(int count);

  /// No description provided for @nPhotos.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo} other{{count} photos}}'**
  String nPhotos(int count);

  /// No description provided for @importedSummary.
  ///
  /// In en, this message translates to:
  /// **'Imported: {details}.'**
  String importedSummary(String details);

  /// No description provided for @importedFromIphoneSummary.
  ///
  /// In en, this message translates to:
  /// **'Imported from this iPhone: {details}.'**
  String importedFromIphoneSummary(String details);

  /// No description provided for @importedFromGoogleSummary.
  ///
  /// In en, this message translates to:
  /// **'Imported from Google: {details}.'**
  String importedFromGoogleSummary(String details);

  /// No description provided for @nothingToImportFrom.
  ///
  /// In en, this message translates to:
  /// **'Nothing to import from {name}.'**
  String nothingToImportFrom(String name);

  /// No description provided for @nothingToImportFromFile.
  ///
  /// In en, this message translates to:
  /// **'Nothing to import from this file.'**
  String get nothingToImportFromFile;

  /// No description provided for @fromSource.
  ///
  /// In en, this message translates to:
  /// **'From {source}'**
  String fromSource(String source);

  /// No description provided for @matchingContactsGet.
  ///
  /// In en, this message translates to:
  /// **'Matching contacts get the missing phones, emails and details added. Nothing you already have is changed or removed, and a restore point is saved first so you can undo the import from Account & Vault.'**
  String get matchingContactsGet;

  /// No description provided for @photosAddedToo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo added too, encrypted on this phone.} other{{count} photos added too, encrypted on this phone.}}'**
  String photosAddedToo(int count);

  /// No description provided for @downloadPhotosFromGoogle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Download 1 photo from Google} other{Download {count} photos from Google}}'**
  String downloadPhotosFromGoogle(int count);

  /// No description provided for @andNMore.
  ///
  /// In en, this message translates to:
  /// **'and {count} more'**
  String andNMore(int count);

  /// No description provided for @importNContacts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Import 1 contact} other{Import {count} contacts}}'**
  String importNContacts(int count);

  /// No description provided for @saveName.
  ///
  /// In en, this message translates to:
  /// **'Save {name}'**
  String saveName(String name);

  /// No description provided for @mergedDuplicatesInto.
  ///
  /// In en, this message translates to:
  /// **'Merged duplicates into {name}'**
  String mergedDuplicatesInto(String name);

  /// No description provided for @labelFilter.
  ///
  /// In en, this message translates to:
  /// **'Label: {label}'**
  String labelFilter(String label);

  /// No description provided for @thatDidntWork.
  ///
  /// In en, this message translates to:
  /// **'That didn\'t work: {error}'**
  String thatDidntWork(String error);

  /// No description provided for @nMovedToTrash.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 contact moved to the trash} other{{count} contacts moved to the trash}}'**
  String nMovedToTrash(int count);

  /// No description provided for @addedLabelTo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added \"{label}\" to 1 contact} other{Added \"{label}\" to {count} contacts}}'**
  String addedLabelTo(int count, String label);

  /// No description provided for @mergeNIntoOne.
  ///
  /// In en, this message translates to:
  /// **'Merge {count} contacts into one?'**
  String mergeNIntoOne(int count);

  /// No description provided for @mergeExplained.
  ///
  /// In en, this message translates to:
  /// **'{names}\n\nTheir phones, emails and other details are combined. A restore point is saved first, so you can undo this from Settings.'**
  String mergeExplained(String names);

  /// No description provided for @mergedInto.
  ///
  /// In en, this message translates to:
  /// **'Merged into {name}'**
  String mergedInto(String name);

  /// No description provided for @nSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String nSelected(int count);

  /// No description provided for @contactsCount.
  ///
  /// In en, this message translates to:
  /// **'Contacts ({count})'**
  String contactsCount(int count);

  /// No description provided for @birthdaysSoon.
  ///
  /// In en, this message translates to:
  /// **'Birthdays soon ({count})'**
  String birthdaysSoon(int count);

  /// No description provided for @staleContacts.
  ///
  /// In en, this message translates to:
  /// **'Stale contacts ({count})'**
  String staleContacts(int count);

  /// No description provided for @missingPhone.
  ///
  /// In en, this message translates to:
  /// **'Missing phone ({count})'**
  String missingPhone(int count);

  /// No description provided for @addToLabel.
  ///
  /// In en, this message translates to:
  /// **'Add to {label}'**
  String addToLabel(String label);

  /// No description provided for @labelNowHas.
  ///
  /// In en, this message translates to:
  /// **'{label} now has {contacts}.'**
  String labelNowHas(String label, String contacts);

  /// No description provided for @renamedTo.
  ///
  /// In en, this message translates to:
  /// **'Renamed to {name}.'**
  String renamedTo(String name);

  /// No description provided for @deleteTheLabel.
  ///
  /// In en, this message translates to:
  /// **'Delete the label {label}?'**
  String deleteTheLabel(String label);

  /// No description provided for @addedContacts.
  ///
  /// In en, this message translates to:
  /// **'Added {contacts}.'**
  String addedContacts(String contacts);

  /// No description provided for @tookOutOf.
  ///
  /// In en, this message translates to:
  /// **'Took {contacts} out of {label}.'**
  String tookOutOf(String contacts, String label);

  /// No description provided for @emailN.
  ///
  /// In en, this message translates to:
  /// **'Email {count}'**
  String emailN(int count);

  /// No description provided for @textN.
  ///
  /// In en, this message translates to:
  /// **'Text {count}'**
  String textN(int count);

  /// No description provided for @holdRowToSelect.
  ///
  /// In en, this message translates to:
  /// **'{contacts}. Hold a row to select several.'**
  String holdRowToSelect(String contacts);

  /// No description provided for @addN.
  ///
  /// In en, this message translates to:
  /// **'Add {count}'**
  String addN(int count);

  /// No description provided for @editsReplaced.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 edit replaced by a newer one from another device} other{{count} edits replaced by a newer one from another device}}'**
  String editsReplaced(int count);

  /// No description provided for @couldntReadThatFile.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read that file: {error}'**
  String couldntReadThatFile(String error);

  /// No description provided for @importedNContacts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Imported 1 contact.} other{Imported {count} contacts.}}'**
  String importedNContacts(int count);

  /// No description provided for @savedAsVcard.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 contact saved as a vCard file.} other{{count} contacts saved as a vCard file.}}'**
  String savedAsVcard(int count);

  /// No description provided for @importedFromVcard.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Imported 1 contact from the vCard.} other{Imported {count} contacts from the vCard.}}'**
  String importedFromVcard(int count);

  /// No description provided for @isBackInContacts.
  ///
  /// In en, this message translates to:
  /// **'{name} is back in your contacts.'**
  String isBackInContacts(String name);

  /// No description provided for @deletedEverywhereName.
  ///
  /// In en, this message translates to:
  /// **'{name} is deleted from every device and can\'t be restored.'**
  String deletedEverywhereName(String name);

  /// No description provided for @deletedEverywhereN.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 contact is deleted from every device and can\'t be restored.} other{{count} contacts are deleted from every device and can\'t be restored.}}'**
  String deletedEverywhereN(int count);

  /// No description provided for @deletedNForGood.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Deleted 1 contact for good.} other{Deleted {count} contacts for good.}}'**
  String deletedNForGood(int count);

  /// No description provided for @daysLeft.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day left} other{{count} days left}}'**
  String daysLeft(int count);

  /// No description provided for @restorePointExplained.
  ///
  /// In en, this message translates to:
  /// **'Your contacts go back to how they were on {date} ({count} contacts), on every device. A restore point of the current state is taken first, so you can undo this.'**
  String restorePointExplained(String date, int count);

  /// No description provided for @restoredN.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Restored 1 contact.} other{Restored {count} contacts.}}'**
  String restoredN(int count);

  /// No description provided for @nOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 contact on this phone} other{{count} contacts on this phone}}'**
  String nOnThisPhone(int count);

  /// No description provided for @cardCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The card could not be read: {error}'**
  String cardCouldNotBeRead(String error);
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'he'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
    case 'he':
      return AppL10nHe();
  }

  throw FlutterError(
    'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
