/// Static catalog of screens that FocusFlow can detect + block.
///
/// Phase 1's Kotlin ScreenMatcher.kt has the matching rules; this Dart list
/// mirrors the entries so the AppDetailScreen UI can offer them as toggles
/// without forcing the user to type View IDs.
///
/// Order in each app list = order shown in the UI. High-risk (Reels, FYP,
/// Shorts, For You) appear first so the most tempting sections are the
/// most visible.
class SupportedScreen {
  final String packageName;
  final String appName;
  final String screenKey;
  final String friendlyName;
  final String emoji;

  const SupportedScreen({
    required this.packageName,
    required this.appName,
    required this.screenKey,
    required this.friendlyName,
    this.emoji = '📱',
  });
}

const List<SupportedScreen> kSupportedScreens = [
  // ── Instagram ───────────────────────────────────────────────────────────
  SupportedScreen(
    packageName: 'com.instagram.android',
    appName: 'Instagram',
    screenKey: 'reels',
    friendlyName: 'Reels',
    emoji: '🎬',
  ),
  SupportedScreen(
    packageName: 'com.instagram.android',
    appName: 'Instagram',
    screenKey: 'stories',
    friendlyName: 'Stories',
    emoji: '📸',
  ),
  SupportedScreen(
    packageName: 'com.instagram.android',
    appName: 'Instagram',
    screenKey: 'explore',
    friendlyName: 'Explore / Search',
    emoji: '🔍',
  ),

  // ── TikTok ──────────────────────────────────────────────────────────────
  SupportedScreen(
    packageName: 'com.zhiliaoapp.musically',
    appName: 'TikTok',
    screenKey: 'fyp',
    friendlyName: 'For You (FYP)',
    emoji: '🎵',
  ),
  SupportedScreen(
    packageName: 'com.zhiliaoapp.musically',
    appName: 'TikTok',
    screenKey: 'search',
    friendlyName: 'Search',
    emoji: '🔍',
  ),
  SupportedScreen(
    packageName: 'com.zhiliaoapp.musically',
    appName: 'TikTok',
    screenKey: 'live',
    friendlyName: 'Live',
    emoji: '📡',
  ),

  // ── YouTube ─────────────────────────────────────────────────────────────
  SupportedScreen(
    packageName: 'com.google.android.youtube',
    appName: 'YouTube',
    screenKey: 'shorts',
    friendlyName: 'Shorts',
    emoji: '🎞️',
  ),
  SupportedScreen(
    packageName: 'com.google.android.youtube',
    appName: 'YouTube',
    screenKey: 'search',
    friendlyName: 'Search',
    emoji: '🔍',
  ),

  // ── Facebook ────────────────────────────────────────────────────────────
  SupportedScreen(
    packageName: 'com.facebook.katana',
    appName: 'Facebook',
    screenKey: 'reels',
    friendlyName: 'Reels',
    emoji: '🎬',
  ),
  SupportedScreen(
    packageName: 'com.facebook.katana',
    appName: 'Facebook',
    screenKey: 'stories',
    friendlyName: 'Stories',
    emoji: '📸',
  ),
  SupportedScreen(
    packageName: 'com.facebook.katana',
    appName: 'Facebook',
    screenKey: 'explore',
    friendlyName: 'Explore / Watch',
    emoji: '🔍',
  ),

  // ── Snapchat ────────────────────────────────────────────────────────────
  SupportedScreen(
    packageName: 'com.snapchat.android',
    appName: 'Snapchat',
    screenKey: 'stories',
    friendlyName: 'Stories',
    emoji: '📸',
  ),
  SupportedScreen(
    packageName: 'com.snapchat.android',
    appName: 'Snapchat',
    screenKey: 'spotlight',
    friendlyName: 'Spotlight',
    emoji: '⭐',
  ),

  // ── X (Twitter) ─────────────────────────────────────────────────────────
  SupportedScreen(
    packageName: 'com.twitter.android',
    appName: 'X',
    screenKey: 'explore',
    friendlyName: 'Explore',
    emoji: '🔍',
  ),

  // ── WhatsApp ────────────────────────────────────────────────────────────
  SupportedScreen(
    packageName: 'com.whatsapp',
    appName: 'WhatsApp',
    screenKey: 'status',
    friendlyName: 'Status',
    emoji: '🟢',
  ),
  SupportedScreen(
    packageName: 'com.whatsapp',
    appName: 'WhatsApp',
    screenKey: 'channels',
    friendlyName: 'Channels',
    emoji: '📢',
  ),
];

/// Filter the catalog to the screens hosted inside [packageName].
List<SupportedScreen> supportedScreensFor(String packageName) =>
    kSupportedScreens.where((s) => s.packageName == packageName).toList();
