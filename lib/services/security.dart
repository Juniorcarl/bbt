import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// On-device security settings: app lock, screenshot blocking and
/// signing out after a long time away. Everything here stays on the phone.
class Security extends ChangeNotifier {
  static const _lockKey = 'bbt_app_lock';
  static const _shotsKey = 'bbt_block_screenshots';
  static const _activeKey = 'bbt_last_active';

  /// Ask to unlock again after the app has been in the background this long.
  static const lockAfter = Duration(minutes: 1);

  /// Sign out automatically when the app hasn't been opened for this long.
  static const signOutAfter = Duration(days: 30);

  static const _screen = MethodChannel('bbt/screen');
  final _auth = LocalAuthentication();
  SharedPreferences? _prefs;

  /// True when the phone has a fingerprint, face unlock or screen lock set up.
  bool lockSupported = false;

  /// True while the fingerprint / PIN prompt is open (it pauses the app).
  bool authenticating = false;

  bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get lockEnabled => lockSupported && (_prefs?.getBool(_lockKey) ?? true);
  bool get blockScreenshots => _prefs?.getBool(_shotsKey) ?? true;

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    if (!kIsWeb) {
      try {
        lockSupported = await _auth.isDeviceSupported();
      } catch (_) {
        lockSupported = false;
      }
    }
    await _applyScreenshots();
  }

  /// Shows the fingerprint / face / PIN prompt. True when the user got in.
  Future<bool> unlock({String reason = 'Unlock bbt to see your money'}) async {
    if (!lockSupported) return true;
    authenticating = true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } on PlatformException catch (e) {
      // The phone's screen lock was removed: nothing to check against.
      if (e.code == auth_error.notAvailable ||
          e.code == auth_error.passcodeNotSet ||
          e.code == auth_error.notEnrolled) {
        return true;
      }
      return false;
    } finally {
      authenticating = false;
    }
  }

  /// Turning the lock off needs the fingerprint / PIN, so someone holding an
  /// unlocked phone can't switch it off.
  Future<bool> setLockEnabled(bool on) async {
    if (!on && !await unlock(reason: 'Confirm it\'s you to turn off the app lock')) return false;
    await _prefs?.setBool(_lockKey, on);
    notifyListeners();
    return true;
  }

  Future<void> setBlockScreenshots(bool on) async {
    await _prefs?.setBool(_shotsKey, on);
    await _applyScreenshots();
    notifyListeners();
  }

  Future<void> _applyScreenshots() async {
    if (!isAndroid) return;
    try {
      await _screen.invokeMethod<void>('setSecure', blockScreenshots);
    } catch (_) {}
  }

  /// Records that the app is being used now.
  void markActive() => _prefs?.setInt(_activeKey, DateTime.now().millisecondsSinceEpoch);

  /// True when the app was last used longer ago than [signOutAfter].
  bool get awayTooLong {
    final ms = _prefs?.getInt(_activeKey);
    if (ms == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)) > signOutAfter;
  }
}

final security = Security();

/// Keeps the sign-in token in the phone's encrypted keystore instead of plain
/// app storage. Used on Android/iOS; the web keeps the default.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage(this.key);

  final String key;
  // Defaults: AES-GCM encryption with a key held in the Android Keystore.
  static const _storage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {
    // Move a session saved by older versions of bbt (plain storage) across.
    try {
      final prefs = await SharedPreferences.getInstance();
      final old = prefs.getString(key);
      if (old != null) {
        if (!await _storage.containsKey(key: key)) await _storage.write(key: key, value: old);
        await prefs.remove(key);
      }
    } catch (_) {}
  }

  @override
  Future<bool> hasAccessToken() async {
    try {
      return await _storage.containsKey(key: key);
    } catch (_) {
      return false; // keystore unreadable: sign in again
    }
  }

  @override
  Future<String?> accessToken() async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: key, value: persistSessionString);
}
