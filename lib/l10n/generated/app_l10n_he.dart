// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Hebrew (`he`).
class AppL10nHe extends AppL10n {
  AppL10nHe([String locale = 'he']) : super(locale);

  @override
  String get tryAgain => 'לנסות שוב';

  @override
  String get bringOverYourContactsFrom => 'העברת אנשי הקשר מלפני העדכון';

  @override
  String get contactsNowUsesYourZero =>
      'אנשי קשר משתמשת עכשיו בחשבון Zero-Trust שלך. יש להזין את הסיסמה פעם אחת כדי להעביר את אנשי הקשר הקודמים.';

  @override
  String get later => 'אחר כך';

  @override
  String get bringOver => 'העברה';

  @override
  String get thatPasswordDoesntOpenYour =>
      'הסיסמה הזו לא פותחת את אנשי הקשר הקודמים. אם שינית אותה מאז, יש להשתמש בסיסמה הקודמת.';

  @override
  String get couldntBringThemOverCheck =>
      'לא ניתן היה להעביר אותם. כדאי לבדוק את החיבור ולנסות שוב.';

  @override
  String get earlierContacts => 'אנשי קשר קודמים';

  @override
  String get enterThePasswordYouUsed =>
      'יש להזין את הסיסמה שהייתה בשימוש באנשי קשר לפני העדכון. צריך אותה רק פעם אחת; שום דבר לא נשלח לשרת.';

  @override
  String get passwordFromBefore => 'הסיסמה הקודמת';

  @override
  String get cancel => 'ביטול';

  @override
  String get undo => 'ביטול';

  @override
  String get changesUndoneOnEveryDevice => 'השינויים בוטלו בכל המכשירים.';

  @override
  String get blockContact => 'חסימת איש קשר';

  @override
  String get thisContactWillBeMarked => 'איש הקשר יסומן כחסום.';

  @override
  String get reasonOptional => 'סיבה (לא חובה)';

  @override
  String get eGSpamUnwantedContact => 'לדוגמה ספאם, פנייה לא רצויה…';

  @override
  String get block => 'חסימה';

  @override
  String get unblockContact => 'ביטול חסימה';

  @override
  String get thisContactWillBeUnblocked => 'החסימה של איש הקשר תבוטל.';

  @override
  String get unblock => 'ביטול חסימה';

  @override
  String get whatsappIsntInstalledOrDoesnt =>
      'WhatsApp לא מותקנת, או שהמספר לא מוכר לה.';

  @override
  String get signalIsntInstalled => 'Signal לא מותקנת.';

  @override
  String get noAppOnThisPhone => 'אין בטלפון אפליקציה שיכולה לפתוח את זה.';

  @override
  String get scanWithAnotherPhonesCamera =>
      'אפשר לסרוק עם המצלמה של טלפון אחר כדי להוסיף את איש הקשר. כל מי שרואה את הקוד יכול לקרוא אותו.';

  @override
  String get done => 'סיום';

  @override
  String get secureSharePackage => 'חבילת שיתוף מאובטחת';

  @override
  String get copyBothPackageAndPassphrase =>
      'יש להעתיק גם את החבילה וגם את מילת הצופן כדי לשתף בבטחה.';

  @override
  String get passphraseCopied => 'מילת הצופן הועתקה';

  @override
  String get copyPassphrase => 'העתקת מילת הצופן';

  @override
  String get packageCopied => 'החבילה הועתקה';

  @override
  String get copyPackage => 'העתקת החבילה';

  @override
  String get email => 'אימייל';

  @override
  String get address => 'כתובת';

  @override
  String get company => 'חברה';

  @override
  String get birthday => 'יום הולדת';

  @override
  String get notes => 'הערות';

  @override
  String get copied => 'הועתק';

  @override
  String get call => 'התקשרות';

  @override
  String get text => 'הודעה';

  @override
  String get directions => 'הוראות הגעה';

  @override
  String get share => 'שיתוף';

  @override
  String get shareAsVcard => 'שיתוף כ-vCard';

  @override
  String get showQrCode => 'הצגת קוד QR';

  @override
  String get encryptedShare => 'שיתוף מוצפן';

  @override
  String get edit => 'עריכה';

  @override
  String get saveToTheVault => 'שמירה בכספת';

  @override
  String get undoChanges => 'ביטול שינויים';

  @override
  String get moveToTrash => 'העברה לאשפה';

  @override
  String get blocked => 'חסום';

  @override
  String get favorite => 'מועדף';

  @override
  String get pin => 'הצמדה';

  @override
  String get noPhone => 'אין טלפון';

  @override
  String get noEmail => 'אין אימייל';

  @override
  String get noCompany => 'אין חברה';

  @override
  String get otherAddress => 'כתובת אחרת';

  @override
  String get otherLabels => 'תוויות אחרות';

  @override
  String get otherNotes => 'הערות אחרות';

  @override
  String get otherBirthday => 'יום הולדת אחר';

  @override
  String get notAFavourite => 'לא מועדף';

  @override
  String get notBlocked => 'לא חסום';

  @override
  String get smallDifferences => 'הבדלים קטנים';

  @override
  String get goBackToThisVersion => 'לחזור לגרסה הזו?';

  @override
  String get goBack => 'חזרה';

  @override
  String get noEarlierVersionsOfThis =>
      'עדיין אין בטלפון גרסאות קודמות של איש הקשר.\nגרסאות נוצרות מנקודות השחזור היומיות, השבועיות ושלפני ייבוא.';

  @override
  String get chooseFromGallery => 'בחירה מהגלריה';

  @override
  String get takeAPhoto => 'צילום תמונה';

  @override
  String get removePhoto => 'הסרת התמונה';

  @override
  String get addAtLeastOneContact => 'כדי לשמור יש להוסיף לפחות פרט אחד.';

  @override
  String get youMayAlreadyHaveThis => 'ייתכן שאיש הקשר הזה כבר קיים';

  @override
  String get youMayAlreadyHaveThese => 'ייתכן שאנשי הקשר האלה כבר קיימים';

  @override
  String get addTheNewDetailsTo => 'הוספת הפרטים החדשים לאיש הקשר הזה';

  @override
  String get openThisContactInstead => 'פתיחת איש הקשר הזה במקום';

  @override
  String get tapAContactToAdd =>
      'אפשר להקיש על איש קשר כדי להוסיף לו את הפרטים החדשים, או לשמור בכל זאת איש קשר נפרד.';

  @override
  String get saveAnyway => 'שמירה בכל זאת';

  @override
  String get selectBirthday => 'בחירת יום הולדת';

  @override
  String get noLabel => 'ללא תווית';

  @override
  String get remove => 'הסרה';

  @override
  String get close => 'סגירה';

  @override
  String get editContact => 'עריכת איש קשר';

  @override
  String get newContact => 'איש קשר חדש';

  @override
  String get removeFromFavorites => 'הסרה מהמועדפים';

  @override
  String get addToFavorites => 'הוספה למועדפים';

  @override
  String get save => 'שמירה';

  @override
  String get firstName => 'שם פרטי';

  @override
  String get lastName => 'שם משפחה';

  @override
  String get addPhone => 'הוספת טלפון';

  @override
  String get withCountryCodeLike972 =>
      'עם קידומת מדינה, למשל ‎+972 50 123 4567';

  @override
  String get addEmail => 'הוספת אימייל';

  @override
  String get addAddress => 'הוספת כתובת';

  @override
  String get streetCityCountry => 'רחוב, עיר, מדינה';

  @override
  String get addBirthday => 'הוספת יום הולדת';

  @override
  String get label => 'תווית';

  @override
  String get addLabel => 'הוספת תווית';

  @override
  String get familyWorkGym => 'משפחה, עבודה, חדר כושר…';

  @override
  String get websiteOrOther => 'אתר או אחר';

  @override
  String get addWebsiteOrOtherDetail => 'הוספת אתר או פרט אחר';

  @override
  String get readingThisIphonesContacts => 'קורא את אנשי הקשר של האייפון…';

  @override
  String get iphoneContacts => 'אנשי הקשר באייפון';

  @override
  String get reading => 'קורא…';

  @override
  String get thatFileIsNotA =>
      'הקובץ הזה אינו ייצוא של אנשי קשר. ב-Google Contacts בוחרים ייצוא, ואז \"vCard (for iOS Contacts)\".';

  @override
  String get encryptingAndSaving => 'מצפין ושומר…';

  @override
  String get everythingWasAlreadyInYour => 'הכול כבר היה בכספת שלך.';

  @override
  String get importContacts => 'ייבוא אנשי קשר';

  @override
  String get importFromGoogle => 'ייבוא מ-Google';

  @override
  String get googleAccountsOnThisPhone => 'חשבונות Google בטלפון הזה';

  @override
  String get allowAccessToContacts => 'מתן גישה לאנשי הקשר';

  @override
  String get neededToReadTheGoogle =>
      'נדרש כדי לקרוא את אנשי הקשר של Google שכבר בטלפון.';

  @override
  String get allow => 'אישור';

  @override
  String get noGoogleContactsOnThis => 'אין בטלפון אנשי קשר של Google';

  @override
  String get addYourGoogleAccountIn =>
      'אפשר להוסיף את חשבון Google בהגדרות Android, או להשתמש בקובץ ייצוא בהמשך.';

  @override
  String get contactsOnThisIphone => 'אנשי הקשר באייפון הזה';

  @override
  String get ztContactsIsNotAllowed =>
      'ל-ZT Contacts אין הרשאה לקרוא את אנשי הקשר. אפשר להפעיל אותה בהגדרות האייפון תחת פרטיות ואבטחה, אנשי קשר, ואז לנסות שוב.';

  @override
  String get copiesEverythingTheIphoneContacts =>
      'מעתיק לכספת את כל מה שאפליקציית אנשי הקשר באייפון מציגה (iCloud וחשבונות אחרים). לפני השמירה רואים מה ישתנה, ואנשים שכבר קיימים מתמזגים ולא מוכפלים.';

  @override
  String get importFromThisIphone => 'ייבוא מהאייפון הזה';

  @override
  String get googleContactsExportFile => 'קובץ ייצוא של Google Contacts';

  @override
  String get openContactsGoogleComAnd =>
      'פותחים את contacts.google.com ומקישים על ייצוא.';

  @override
  String get chooseVcardForIosContacts =>
      'בוחרים \"vCard (for iOS Contacts)\" ושומרים את הקובץ.';

  @override
  String get pickThatFileHere => 'בוחרים את הקובץ כאן.';

  @override
  String get chooseExportFile => 'בחירת קובץ ייצוא';

  @override
  String get readyToImport => 'מוכן לייבוא';

  @override
  String get newLabel => 'חדשים';

  @override
  String get updated => 'עודכנו';

  @override
  String get alreadyHere => 'כבר כאן';

  @override
  String get everythingInThisSourceIs => 'כל מה שבמקור הזה כבר בכספת שלך.';

  @override
  String get thisExportLinksToPhotos =>
      'הייצוא הזה מקשר לתמונות במקום לכלול אותן. ההורדה מתחברת לשרת התמונות של Google, שרואה את הכתובת של הטלפון. אחר כך התמונות מוצפנות כמו כל השאר.';

  @override
  String get update => 'עדכון';

  @override
  String get back => 'חזרה';

  @override
  String get nothingToImport => 'אין מה לייבא';

  @override
  String get importPhotos => 'ייבוא תמונות';

  @override
  String get noGoogleSignInNeeded =>
      'אין צורך להתחבר ל-Google. אנשי הקשר נקראים במכשיר הזה ומוצפנים לפני שמירה או סנכרון.';

  @override
  String get createANewContact => 'יצירת איש קשר חדש';

  @override
  String get addToAContactI => 'הוספה לאיש קשר קיים';

  @override
  String get searchYourContacts => 'חיפוש באנשי הקשר';

  @override
  String get searchNamePhoneEmailNotes => 'חיפוש לפי שם, טלפון, אימייל, הערות';

  @override
  String get settings => 'הגדרות';

  @override
  String get all => 'הכול';

  @override
  String get sort => 'מיון';

  @override
  String get firstNameAToZ => 'שם פרטי, א עד ת';

  @override
  String get lastNameAToZ => 'שם משפחה, א עד ת';

  @override
  String get recentlyChanged => 'שונו לאחרונה';

  @override
  String get bySource => 'לפי מקור';

  @override
  String get recent => 'אחרונים';

  @override
  String get source => 'מקור';

  @override
  String get addALabel => 'הוספת תווית';

  @override
  String get add => 'הוספה';

  @override
  String get merge => 'מיזוג';

  @override
  String get cancelSelection => 'ביטול הבחירה';

  @override
  String get selectNone => 'ביטול הבחירה בכול';

  @override
  String get selectAll => 'בחירת הכול';

  @override
  String get bringYourIphoneContacts => 'העברת אנשי הקשר מהאייפון';

  @override
  String get bringYourGoogleContacts => 'העברת אנשי הקשר מ-Google';

  @override
  String get importThemIntoYourEncrypted => 'ייבוא לכספת המוצפנת בכמה הקשות.';

  @override
  String get importLabel => 'ייבוא';

  @override
  String get contactsPermissionDeniedShowingVault =>
      'ההרשאה לאנשי הקשר נדחתה. מוצגים רק אנשי הקשר מהכספת.';

  @override
  String get noContactsMatchTheCurrent => 'אין אנשי קשר שמתאימים למסננים.';

  @override
  String get pinned => 'מוצמדים';

  @override
  String get favorites => 'מועדפים';

  @override
  String get frequent => 'תכופים';

  @override
  String get noHighlightsYetStarPin =>
      'עדיין אין כאן כלום. אפשר לסמן בכוכב או להצמיד אנשי קשר כדי לראות אותם כאן.';

  @override
  String get trash => 'אשפה';

  @override
  String get deletedContactsKeptFor30 => 'אנשי קשר שנמחקו, נשמרים 30 יום';

  @override
  String get scanAContactQrCode => 'סריקת קוד QR של איש קשר';

  @override
  String get addAContactSomeoneShows => 'הוספת איש קשר שמישהו מציג לך';

  @override
  String get scanABusinessCard => 'סריקת כרטיס ביקור';

  @override
  String get readOnThisPhoneThe => 'נקרא בטלפון הזה, התמונה אף פעם לא מועלית';

  @override
  String get labels => 'תוויות';

  @override
  String get manageLabels => 'ניהול תוויות';

  @override
  String get noLabelsYet => 'עדיין אין תוויות';

  @override
  String get smartGroups => 'קבוצות חכמות';

  @override
  String get duplicateCleanup => 'ניקוי כפילויות';

  @override
  String get noDuplicatesDetected => 'לא נמצאו כפילויות';

  @override
  String get contacts => 'אנשי קשר';

  @override
  String get highlights => 'מובחרים';

  @override
  String get organize => 'ארגון';

  @override
  String get labelName => 'שם התווית';

  @override
  String get addAContactFirstThen =>
      'קודם מוסיפים איש קשר, ואז אפשר לשייך אותו לתווית.';

  @override
  String get newLabelX => 'תווית חדשה';

  @override
  String get next => 'הבא';

  @override
  String get noLabelsYetMakeOne =>
      'עדיין אין תוויות. אפשר ליצור תווית למשפחה, לצוות או לכיתה, ואז לשלוח אימייל או הודעה לכולם בבת אחת.';

  @override
  String get renameLabel => 'שינוי שם התווית';

  @override
  String get rename => 'שינוי שם';

  @override
  String get theContactsStayOnlyThe => 'אנשי הקשר נשארים. רק התווית מוסרת מהם.';

  @override
  String get deleteLabel => 'מחיקת התווית';

  @override
  String get everyContactAlreadyHasThis =>
      'לכל אנשי הקשר כבר יש את התווית הזו.';

  @override
  String get nobodyHereHasAnEmail => 'לאף אחד כאן אין כתובת אימייל.';

  @override
  String get noMailAppCouldBe => 'לא ניתן היה לפתוח אפליקציית דואר.';

  @override
  String get nobodyHereHasAPhone => 'לאף אחד כאן אין מספר טלפון.';

  @override
  String get noMessagesAppCouldBe => 'לא ניתן היה לפתוח אפליקציית הודעות.';

  @override
  String get clearSelection => 'ניקוי הבחירה';

  @override
  String get removeFromLabel => 'הסרה מהתווית';

  @override
  String get addContacts => 'הוספת אנשי קשר';

  @override
  String get emailAll => 'אימייל לכולם';

  @override
  String get textAll => 'הודעה לכולם';

  @override
  String get nobodyHasThisLabelAny => 'לאף אחד כבר אין את התווית הזו.';

  @override
  String get searchContacts => 'חיפוש אנשי קשר';

  @override
  String get syncConflicts => 'התנגשויות סנכרון';

  @override
  String get noConflictsWhenTheSame =>
      'אין התנגשויות. כשאותו איש קשר נערך בשני מכשירים, העריכה החדשה נשמרת והעריכה שלך מופיעה כאן.';

  @override
  String get deletedOnAnotherDeviceAfter => 'נמחק במכשיר אחר אחרי שערכת אותו.';

  @override
  String get editedOnAnotherDeviceAfter => 'נערך במכשיר אחר אחרי העריכה שלך.';

  @override
  String get keepDeleted => 'להשאיר מחוק';

  @override
  String get keepTheNewerOne => 'להשאיר את החדש';

  @override
  String get useMine => 'להשתמש בשלי';

  @override
  String get combine => 'שילוב';

  @override
  String get qrCode => 'קוד QR';

  @override
  String get thatCodeIsNotA => 'הקוד הזה אינו איש קשר.';

  @override
  String get allowTheCameraForZt =>
      'כדי לסרוק קוד יש לאשר ל-ZT Contacts גישה למצלמה בהגדרות הטלפון.';

  @override
  String get pointTheCameraAtA =>
      'מכוונים את המצלמה לקוד QR של איש קשר. הוא נקרא רק בטלפון הזה.';

  @override
  String get bringOverContactsFromBefore => 'העברת אנשי קשר מלפני העדכון';

  @override
  String get needsYourPasswordFromBefore => 'דורש את הסיסמה הקודמת, פעם אחת';

  @override
  String get showInPhoneAndMessages => 'הצגה בטלפון ובהודעות';

  @override
  String get onCallerIdAndThe =>
      'פועל: זיהוי המתקשר והחייגן מציגים את אנשי הקשר';

  @override
  String get offCallsFromContactsShow =>
      'כבוי: שיחות מאנשי קשר מציגות רק את המספר';

  @override
  String get fromThisIphoneOrA => 'מהאייפון הזה, או מייצוא של Google';

  @override
  String get accountsOnThisPhoneOr => 'חשבונות בטלפון הזה, או ייצוא של Google';

  @override
  String get restorePoints => 'נקודות שחזור';

  @override
  String get undoAnImportMergeOr => 'ביטול ייבוא, מיזוג או שחזור';

  @override
  String get none => 'אין';

  @override
  String get activityOnThisDevice => 'פעילות במכשיר הזה';

  @override
  String get saveAnEncryptedBackup => 'שמירת גיבוי מוצפן';

  @override
  String get aFileSealedWithA => 'קובץ שנחתם במילת צופן שבוחרים';

  @override
  String get copyToTheClipboardInstead => 'העתקה ללוח במקום';

  @override
  String get restoreAnEncryptedBackup => 'שחזור גיבוי מוצפן';

  @override
  String get fromABackupFile => 'מקובץ גיבוי';

  @override
  String get pasteTheBackupTextInstead => 'הדבקת טקסט הגיבוי במקום';

  @override
  String get exportContactsAsAVcard => 'ייצוא אנשי הקשר כקובץ vCard';

  @override
  String get notEncryptedWorksWithGoogle =>
      'לא מוצפן. עובד עם Google,‏ Apple ואפליקציות אחרות';

  @override
  String get importAVcardFile => 'ייבוא קובץ vCard';

  @override
  String get aVcfFileFromAny => 'קובץ ‎.vcf מכל אפליקציית אנשי קשר';

  @override
  String get pasteVcardTextInstead => 'הדבקת טקסט vCard במקום';

  @override
  String get exportEncryptedBackup => 'ייצוא גיבוי מוצפן';

  @override
  String get passphrase8Characters => 'מילת צופן (8 תווים לפחות)';

  @override
  String get thePassphraseNeedsAtLeast => 'מילת הצופן צריכה לפחות 8 תווים.';

  @override
  String get encryptedBackupCopiedToThe => 'הגיבוי המוצפן הועתק ללוח.';

  @override
  String get encryptedBackupSaved => 'הגיבוי המוצפן נשמר.';

  @override
  String get nothingWasSaved => 'שום דבר לא נשמר.';

  @override
  String get restoreEncryptedBackup => 'שחזור גיבוי מוצפן';

  @override
  String get backupText => 'טקסט הגיבוי';

  @override
  String get passphrase => 'מילת צופן';

  @override
  String get theBackupAndItsPassphrase =>
      'צריך גם את הגיבוי וגם את מילת הצופן שלו.';

  @override
  String get thereAreNoContactsTo => 'עדיין אין אנשי קשר לייצוא.';

  @override
  String get vcardCopiedToTheClipboard => 'ה-vCard הועתק ללוח.';

  @override
  String get importVcard => 'ייבוא vCard';

  @override
  String get pasteVcardText => 'הדבקת טקסט vCard';

  @override
  String get deleteForGood => 'למחוק לצמיתות?';

  @override
  String get delete => 'מחיקה';

  @override
  String get deletedForGood => 'נמחק לצמיתות.';

  @override
  String get emptyTheTrash => 'לרוקן את האשפה?';

  @override
  String get emptyTrash => 'ריקון האשפה';

  @override
  String get theTrashIsEmptyDeleted =>
      'האשפה ריקה.\nאנשי קשר שנמחקו נשארים כאן 30 יום.';

  @override
  String get contactsInTheTrashAre =>
      'אנשי קשר באשפה נמחקים לצמיתות אחרי 30 יום.';

  @override
  String get restore => 'שחזור';

  @override
  String get deleteForGoodX => 'מחיקה לצמיתות';

  @override
  String get deletedForGoodToday => 'יימחק לצמיתות היום';

  @override
  String get restoreThisPoint => 'לשחזר את הנקודה הזו?';

  @override
  String get restorePointSaved => 'נקודת השחזור נשמרה.';

  @override
  String get saveNow => 'שמירה עכשיו';

  @override
  String get noRestorePointsYet => 'עדיין אין נקודות שחזור.';

  @override
  String get noActivityYet => 'עדיין אין פעילות.';

  @override
  String get contactsPermissionIsNeededTo =>
      'כדי להציג אנשי קשר באפליקציות הטלפון וההודעות נדרשת הרשאה לאנשי הקשר.';

  @override
  String get removeFromThePhone => 'להסיר מהטלפון?';

  @override
  String get theCopiesInThePhones =>
      'העותקים באנשי הקשר של הטלפון יוסרו. אנשי הקשר שלך נשארים בכספת. שיחות יציגו מספרים במקום שמות.';

  @override
  String get phoneAndMessages => 'טלפון והודעות';

  @override
  String get showContactsInPhoneAnd => 'הצגת אנשי הקשר בטלפון ובהודעות';

  @override
  String get callerIdTheDialerAnd =>
      'זיהוי המתקשר, החייגן ואפליקציות ההודעות רואים שמות';

  @override
  String get thisPutsAnUnencryptedCopy =>
      'האפשרות הזו שומרת עותק לא מוצפן של הפרטים שבוחרים כאן באנשי הקשר של הטלפון, תחת חשבון \"ZT Contacts\". כל אפליקציה שמורשית לקרוא אנשי קשר יכולה לראות את העותק. הכספת נשארת מוצפנת והיא עדיין המקום לערוך אנשי קשר; העותק מתעדכן כשהאפליקציה פתוחה ומוסר כשמכבים את האפשרות או מתנתקים.';

  @override
  String get whatLeavesTheVault => 'מה יוצא מהכספת';

  @override
  String get name => 'שם';

  @override
  String get alwaysSoCallsShowWho => 'תמיד, כדי ששיחות יציגו מי מתקשר';

  @override
  String get phoneNumbers => 'מספרי טלפון';

  @override
  String get neededForCallerId => 'נדרש לזיהוי מתקשר';

  @override
  String get photos => 'תמונות';

  @override
  String get emailAddresses => 'כתובות אימייל';

  @override
  String get addresses => 'כתובות';

  @override
  String get birthdays => 'ימי הולדת';

  @override
  String get favourites => 'מועדפים';

  @override
  String get starredInThePhoneToo => 'מסומנים בכוכב גם בטלפון';

  @override
  String get sendBlockedContactsToVoicemail => 'העברת אנשי קשר חסומים לתא קולי';

  @override
  String get updatingThePhonesContacts => 'מעדכן את אנשי הקשר בטלפון…';

  @override
  String get waitingToUpdate => 'ממתין לעדכון';

  @override
  String get updateNow => 'עדכון עכשיו';

  @override
  String get theCardIsReadOn =>
      'הכרטיס נקרא בטלפון הזה. התמונה לא מועלית ונמחקת אחרי הקריאה.';

  @override
  String get takeAPhotoOfThe => 'צילום הכרטיס';

  @override
  String get chooseAPhoto => 'בחירת תמונה';

  @override
  String get readingTheCard => 'קורא את הכרטיס…';

  @override
  String get noDetailsCouldBeRead =>
      'לא ניתן היה לקרוא פרטים מהתמונה. כדאי לנסות שוב בתאורה טובה כשהכרטיס ממלא את המסגרת.';

  @override
  String get jumpToALetter => 'מעבר לאות';

  @override
  String nContacts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count אנשי קשר',
      one: 'איש קשר אחד',
    );
    return '$_temp0';
  }

  @override
  String get typeMobile => 'נייד';

  @override
  String get typeHome => 'בית';

  @override
  String get typeWork => 'עבודה';

  @override
  String get typeMain => 'ראשי';

  @override
  String get typeOther => 'אחר';

  @override
  String get phoneLabel => 'טלפון';

  @override
  String get unnamedContact => 'איש קשר ללא שם';

  @override
  String get srcSaved => 'שמורים';

  @override
  String get srcAccount => 'חשבון';

  @override
  String get srcSim => 'SIM';

  @override
  String get rpBeforeMerging => 'לפני מיזוג כפילויות';

  @override
  String get rpDaily => 'נקודת שחזור יומית אוטומטית';

  @override
  String get rpWeekly => 'נקודת שחזור שבועית אוטומטית';

  @override
  String get rpBeforeRestoring => 'לפני שחזור נקודת שחזור';

  @override
  String get rpBeforeReplacing => 'לפני החלפת אנשי הקשר המקומיים';

  @override
  String get rpManual => 'נקודת שחזור ידנית';

  @override
  String get dupSimilar => 'אנשי קשר דומים';

  @override
  String get dupPhone => 'אותו מספר טלפון';

  @override
  String get dupEmail => 'אותו אימייל';

  @override
  String get dupName => 'אותו שם תצוגה';

  @override
  String rpBeforeImport(String source) {
    return 'לפני ייבוא מ-$source';
  }

  @override
  String cantOpenContacts(String error) {
    return 'לא ניתן לפתוח את אנשי הקשר במכשיר הזה. $error';
  }

  @override
  String broughtOver(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'הועברו $count אנשי קשר.',
      one: 'הועבר איש קשר אחד.',
    );
    return '$_temp0';
  }

  @override
  String movedToTrash(String name) {
    return '$name הועבר לאשפה';
  }

  @override
  String couldntShare(String error) {
    return 'לא ניתן לשתף: $error';
  }

  @override
  String qrCodeFor(String name) {
    return 'קוד QR של $name';
  }

  @override
  String passphraseValue(String value) {
    return 'מילת צופן: $value';
  }

  @override
  String expiresAt(String date) {
    return 'תוקף עד: $date';
  }

  @override
  String textNumber(String number) {
    return 'הודעה ל-$number';
  }

  @override
  String interactionCount(int count) {
    return 'מספר אינטראקציות: $count';
  }

  @override
  String histName(String value) {
    return 'שם: $value';
  }

  @override
  String histPhone(String value) {
    return 'טלפון: $value';
  }

  @override
  String histEmail(String value) {
    return 'אימייל: $value';
  }

  @override
  String histCompany(String value) {
    return 'חברה: $value';
  }

  @override
  String get histFavourite => 'מועדף';

  @override
  String get histBlocked => 'חסום';

  @override
  String goesBackTo(String name, String date) {
    return '$name יחזור למצב שהיה ב-$date, בכל המכשירים. התמונה תישאר כמו שהיא עכשיו.';
  }

  @override
  String failedToSaveContact(String error) {
    return 'שמירת איש הקשר נכשלה: $error';
  }

  @override
  String whatToDoWith(String name) {
    return 'מה לעשות עם $name';
  }

  @override
  String readingName(String name) {
    return 'קורא את $name…';
  }

  @override
  String encryptingPhotos(int done, int total) {
    return 'מצפין תמונות… $done מתוך $total';
  }

  @override
  String nAdded(int count) {
    return '$count נוספו';
  }

  @override
  String nUpdated(int count) {
    return '$count עודכנו';
  }

  @override
  String nPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count תמונות',
      one: 'תמונה אחת',
    );
    return '$_temp0';
  }

  @override
  String importedSummary(String details) {
    return 'יובאו: $details.';
  }

  @override
  String importedFromIphoneSummary(String details) {
    return 'יובאו מהאייפון הזה: $details.';
  }

  @override
  String importedFromGoogleSummary(String details) {
    return 'יובאו מ-Google: $details.';
  }

  @override
  String nothingToImportFrom(String name) {
    return 'אין מה לייבא מ-$name.';
  }

  @override
  String get nothingToImportFromFile => 'אין מה לייבא מהקובץ הזה.';

  @override
  String fromSource(String source) {
    return 'מ-$source';
  }

  @override
  String get matchingContactsGet =>
      'אנשי קשר תואמים יקבלו את הטלפונים, האימיילים והפרטים החסרים. שום דבר קיים לא משתנה או נמחק, ולפני כן נשמרת נקודת שחזור כדי שאפשר יהיה לבטל את הייבוא מחשבון וכספת.';

  @override
  String photosAddedToo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'נוספו גם $count תמונות, מוצפנות בטלפון הזה.',
      one: 'נוספה גם תמונה אחת, מוצפנת בטלפון הזה.',
    );
    return '$_temp0';
  }

  @override
  String downloadPhotosFromGoogle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'הורדת $count תמונות מ-Google',
      one: 'הורדת תמונה אחת מ-Google',
    );
    return '$_temp0';
  }

  @override
  String andNMore(int count) {
    return 'ועוד $count';
  }

  @override
  String importNContacts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ייבוא $count אנשי קשר',
      one: 'ייבוא איש קשר אחד',
    );
    return '$_temp0';
  }

  @override
  String saveName(String name) {
    return 'שמירת $name';
  }

  @override
  String mergedDuplicatesInto(String name) {
    return 'הכפילויות מוזגו לתוך $name';
  }

  @override
  String labelFilter(String label) {
    return 'תווית: $label';
  }

  @override
  String thatDidntWork(String error) {
    return 'זה לא עבד: $error';
  }

  @override
  String nMovedToTrash(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count אנשי קשר הועברו לאשפה',
      one: 'איש קשר אחד הועבר לאשפה',
    );
    return '$_temp0';
  }

  @override
  String addedLabelTo(int count, String label) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '\"$label\" נוספה ל-$count אנשי קשר',
      one: '\"$label\" נוספה לאיש קשר אחד',
    );
    return '$_temp0';
  }

  @override
  String mergeNIntoOne(int count) {
    return 'למזג $count אנשי קשר לאחד?';
  }

  @override
  String mergeExplained(String names) {
    return '$names\n\nהטלפונים, האימיילים ושאר הפרטים שלהם יאוחדו. לפני כן נשמרת נקודת שחזור, כך שאפשר לבטל את זה מההגדרות.';
  }

  @override
  String mergedInto(String name) {
    return 'מוזג לתוך $name';
  }

  @override
  String nSelected(int count) {
    return '$count נבחרו';
  }

  @override
  String contactsCount(int count) {
    return 'אנשי קשר ($count)';
  }

  @override
  String birthdaysSoon(int count) {
    return 'ימי הולדת קרובים ($count)';
  }

  @override
  String staleContacts(int count) {
    return 'אנשי קשר לא פעילים ($count)';
  }

  @override
  String missingPhone(int count) {
    return 'חסר טלפון ($count)';
  }

  @override
  String addToLabel(String label) {
    return 'הוספה ל$label';
  }

  @override
  String labelNowHas(String label, String contacts) {
    return 'ב$label יש עכשיו $contacts.';
  }

  @override
  String renamedTo(String name) {
    return 'השם שונה ל$name.';
  }

  @override
  String deleteTheLabel(String label) {
    return 'למחוק את התווית $label?';
  }

  @override
  String addedContacts(String contacts) {
    return 'נוספו $contacts.';
  }

  @override
  String tookOutOf(String contacts, String label) {
    return '$contacts הוצאו מ$label.';
  }

  @override
  String emailN(int count) {
    return 'אימייל ל-$count';
  }

  @override
  String textN(int count) {
    return 'הודעה ל-$count';
  }

  @override
  String holdRowToSelect(String contacts) {
    return '$contacts. לחיצה ארוכה על שורה בוחרת כמה.';
  }

  @override
  String addN(int count) {
    return 'הוספת $count';
  }

  @override
  String editsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count עריכות הוחלפו בעריכות חדשות יותר ממכשיר אחר',
      one: 'עריכה אחת הוחלפה בעריכה חדשה יותר ממכשיר אחר',
    );
    return '$_temp0';
  }

  @override
  String couldntReadThatFile(String error) {
    return 'לא ניתן לקרוא את הקובץ: $error';
  }

  @override
  String importedNContacts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'יובאו $count אנשי קשר.',
      one: 'יובא איש קשר אחד.',
    );
    return '$_temp0';
  }

  @override
  String savedAsVcard(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count אנשי קשר נשמרו כקובץ vCard.',
      one: 'איש קשר אחד נשמר כקובץ vCard.',
    );
    return '$_temp0';
  }

  @override
  String importedFromVcard(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'יובאו $count אנשי קשר מה-vCard.',
      one: 'יובא איש קשר אחד מה-vCard.',
    );
    return '$_temp0';
  }

  @override
  String isBackInContacts(String name) {
    return '$name חזר לאנשי הקשר שלך.';
  }

  @override
  String deletedEverywhereName(String name) {
    return '$name יימחק מכל המכשירים ולא יהיה אפשר לשחזר אותו.';
  }

  @override
  String deletedEverywhereN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count אנשי קשר יימחקו מכל המכשירים ולא יהיה אפשר לשחזר אותם.',
      one: 'איש קשר אחד יימחק מכל המכשירים ולא יהיה אפשר לשחזר אותו.',
    );
    return '$_temp0';
  }

  @override
  String deletedNForGood(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count אנשי קשר נמחקו לצמיתות.',
      one: 'איש קשר אחד נמחק לצמיתות.',
    );
    return '$_temp0';
  }

  @override
  String daysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'נשארו $count ימים',
      two: 'נשארו יומיים',
      one: 'נשאר יום אחד',
    );
    return '$_temp0';
  }

  @override
  String restorePointExplained(String date, int count) {
    return 'אנשי הקשר יחזרו למצב שהיה ב-$date ($count אנשי קשר), בכל המכשירים. לפני כן נשמרת נקודת שחזור של המצב הנוכחי, כך שאפשר לבטל את זה.';
  }

  @override
  String restoredN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'שוחזרו $count אנשי קשר.',
      one: 'שוחזר איש קשר אחד.',
    );
    return '$_temp0';
  }

  @override
  String nOnThisPhone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count אנשי קשר בטלפון הזה',
      one: 'איש קשר אחד בטלפון הזה',
    );
    return '$_temp0';
  }

  @override
  String cardCouldNotBeRead(String error) {
    return 'לא ניתן לקרוא את הכרטיס: $error';
  }
}
