class EnvVar {
  static const bool isAppStore =
      String.fromEnvironment('isAppStore', defaultValue: 'false') == 'true';

  static const bool isPlayStore =
      String.fromEnvironment('isPlayStore', defaultValue: 'false') == 'true';
  static const bool isFdroid =
      String.fromEnvironment('isFdroid', defaultValue: 'false') == 'true';
  static const bool isOhosStore =
      String.fromEnvironment('isOhosStore', defaultValue: 'false') == 'true';

  static bool get isStoreBuild => isAppStore || isPlayStore;

  static bool get showIapPlaceHolder => isOhosStore;

  static bool get enableAutomaticUpdateCheck => false;
  static bool get enableManualReleaseLink => true;
  static bool get enableDonation => false;
  static bool get enableInAppPurchase => isStoreBuild;

  static bool get showBeian => false;
  static bool get enableOpenAiConfig => !showBeian;
  static bool get showTelegramLink => false;

  static bool get enableAIFeature => !isOhosStore;
}
