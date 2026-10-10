import 'package:flutter/services.dart';

import '../data/models.dart';

/// The Flutter half of the platform channel (spec 3).
///
/// Everything here is a thin call-through. No SMS plugin is used for sending: we need
/// per-message sent/delivered PendingIntents, and only our own native code gives us
/// those.
class SmsChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.loomsolutions.campaign_sms/native',
  );

  static Future<DefaultSmsInfo> defaultSmsInfo() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'defaultSmsInfo',
      );
      if (result == null) return DefaultSmsInfo.unknown;
      return DefaultSmsInfo.fromMap(result);
    } on PlatformException {
      return DefaultSmsInfo.unknown;
    } on MissingPluginException {
      return DefaultSmsInfo.unknown;
    }
  }

  static Future<void> rememberPreviousDefault() =>
      _invoke('rememberPreviousDefault');

  /// Opens the system role dialog and waits for the user to answer it.
  /// Resolves to whether this app holds the role afterwards.
  static Future<bool> requestDefaultRole() => _roleCall('requestDefaultRole');

  /// Offers the role back to [previousPackage] (or opens default-apps settings when we
  /// never recorded one). Resolves to whether this app *still* holds the role.
  static Future<bool> restoreDefaultRole(String? previousPackage) =>
      _roleCall('restoreDefaultRole', {'package': previousPackage});

  static Future<bool> _roleCall(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// True when SEND_SMS is granted — the one permission a campaign cannot run without.
  static Future<bool> hasSmsPermissions() async {
    try {
      return await _channel.invokeMethod<bool>('hasSmsPermissions') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Shows the runtime permission dialog and waits for the answer.
  static Future<bool> requestSmsPermissions() =>
      _roleCall('requestSmsPermissions');

  /// Opens the system document picker and returns a readable path to a copy of the
  /// chosen file, or null if the user backed out.
  static Future<String?> pickFile() async {
    try {
      return await _channel.invokeMethod<String?>('pickFile');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> hasContactsPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasContactsPermission') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Asks for READ_CONTACTS and waits for the answer.
  static Future<bool> requestContactsPermission() =>
      _roleCall('requestContactsPermission');

  /// Raw name/number pairs from the phone book. Normalizing and deduplicating
  /// them is Dart's job, on the same path a CSV takes.
  static Future<List<({String? name, String? phone})>>
  readDeviceContacts() async {
    try {
      final result = await _channel.invokeListMethod<Object?>(
        'readDeviceContacts',
      );
      if (result == null) return const [];
      return result.whereType<Map<Object?, Object?>>().map((m) {
        return (name: m['name'] as String?, phone: m['phone'] as String?);
      }).toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  static Future<bool> hasCallLogPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasCallLogPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Asks for READ_CALL_LOG and waits for the answer.
  static Future<bool> requestCallLogPermission() =>
      _roleCall('requestCallLogPermission');

  /// Calls exchanged with one number, newest first. Empty when the permission
  /// is missing — the callers treat that the same as "no calls".
  static Future<List<CallEntry>> callsFor(String phone) async {
    try {
      final result = await _channel.invokeListMethod<Object?>('callsFor', {
        'phone': phone,
      });
      if (result == null) return const [];
      return result.whereType<Map<Object?, Object?>>().map((m) {
        return CallEntry(
          type: (m['type'] as int?) ?? 0,
          date: (m['date'] as int?) ?? 0,
          durationSeconds: (m['duration'] as int?) ?? 0,
        );
      }).toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Whether LeadForce may draw over other apps — the caller-notes card needs it.
  static Future<bool> hasOverlayPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system page where "display over other apps" is granted. There
  /// is no dialog for this one — Android only offers the settings screen.
  static Future<void> requestOverlayPermission() =>
      _invoke('requestOverlayPermission');

  /// The whole recent call log, newest first. Empty without the permission.
  static Future<List<RecentCall>> recentCalls() async {
    try {
      final result = await _channel.invokeListMethod<Object?>('recentCalls');
      if (result == null) return const [];
      return result.whereType<Map<Object?, Object?>>().map((m) {
        return RecentCall(
          number: (m['number'] as String?) ?? '',
          entry: CallEntry(
            type: (m['type'] as int?) ?? 0,
            date: (m['date'] as int?) ?? 0,
            durationSeconds: (m['duration'] as int?) ?? 0,
          ),
        );
      }).toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Whether the system lets LeadForce read notifications — what the chat feed
  /// is built on. Granted by hand in Android's own settings.
  static Future<bool> hasNotificationAccess() async {
    try {
      return await _channel.invokeMethod<bool>('hasNotificationAccess') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens Android's notification-access page. There is no dialog for this.
  static Future<void> openNotificationAccess() =>
      _invoke('openNotificationAccess');

  /// The messengers LeadForce knows about that are installed on this phone.
  static Future<List<({String package, String label})>> chatApps() async {
    try {
      final result = await _channel.invokeListMethod<Object?>('chatApps');
      if (result == null) return const [];
      return result
          .whereType<Map<Object?, Object?>>()
          .map((m) {
            return (
              package: (m['package'] as String?) ?? '',
              label: (m['label'] as String?) ?? '',
            );
          })
          .where((a) => a.package.isNotEmpty)
          .toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Another app's own launcher icon, as PNG bytes. Null when it is not
  /// installed — the caller draws its own mark instead.
  static Future<Uint8List?> appIcon(String package) async {
    try {
      return await _channel.invokeMethod<Uint8List>('appIcon', {
        'package': package,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Opens another app — replying happens where the conversation lives.
  static Future<bool> openApp(String package) async {
    try {
      return await _channel.invokeMethod<bool>('openApp', {
            'package': package,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Moves a picked file into permanent car-photo storage; returns the new
  /// path, or null when the file could not be read.
  static Future<String?> importListingPhoto(String path) async {
    try {
      return await _channel.invokeMethod<String>('importListingPhoto', {
        'path': path,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Content another app shared into LeadForce — the shelf's front door.
  /// One-shot; the photos are already copies in the app's own storage.
  static Future<({String text, List<String> photos})?>
  takePendingShare() async {
    try {
      final m = await _channel.invokeMapMethod<Object?, Object?>(
        'takePendingShare',
      );
      if (m == null) return null;
      final photos = (m['photos'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList();
      return (text: (m['text'] as String?) ?? '', photos: photos);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// The after-call nudge's payload, if its notification was tapped. One-shot,
  /// like [takePendingThread].
  static Future<({int contactId, String prefill})?>
  takePendingCallNote() async {
    try {
      final m = await _channel.invokeMapMethod<Object?, Object?>(
        'takePendingCallNote',
      );
      final id = m?['contactId'] as int?;
      if (id == null || id <= 0) return null;
      return (contactId: id, prefill: (m?['prefill'] as String?) ?? '');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// The conversation an inbox notification was tapped on, if any. One-shot:
  /// native clears it as it hands it over, so a resume never reopens a thread
  /// the user has already backed out of.
  static Future<int?> takePendingThread() async {
    try {
      return await _channel.invokeMethod<int>('takePendingThread');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// True when Android is still free to stop our send service to save power.
  static Future<bool> isBatteryOptimized() async {
    try {
      return await _channel.invokeMethod<bool>('isBatteryOptimized') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system dialog that grants the exemption. Returns null if the
  /// dialog opened, or a reason it could not.
  static Future<String?> requestBatteryExemption() async {
    try {
      return await _channel.invokeMethod<String>('requestBatteryExemption');
    } on PlatformException catch (e) {
      return e.message ?? 'Could not open that setting.';
    } on MissingPluginException {
      return 'Could not open that setting.';
    }
  }

  /// Opens a `tel:` / `mailto:` / `https:` link in whichever app owns it.
  /// Returns null on success, or a reason to show the user.
  static Future<String?> openExternal(String url) async {
    try {
      return await _channel.invokeMethod<String>('openExternal', {'url': url});
    } on PlatformException catch (e) {
      return e.message ?? 'Could not open that link.';
    } on MissingPluginException {
      return 'Could not open that link.';
    }
  }

  static Future<List<SimCard>> listSims() async {
    try {
      final result = await _channel.invokeListMethod<Object?>('listSims');
      if (result == null) return const [];
      return result
          .whereType<Map<Object?, Object?>>()
          .map(SimCard.fromMap)
          .where((s) => s.subscriptionId >= 0)
          .toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  static Future<void> startSendService() => _invoke('startSendService');

  static Future<void> pauseCampaign() => _invoke('pauseCampaign');

  static Future<void> resumeCampaign() => _invoke('resumeCampaign');

  static Future<void> stopCampaign() => _invoke('stopCampaign');

  /// Sends a message whose `message` row already exists. Returns an error string, or
  /// null when the send reached the radio (the real outcome arrives as a receipt).
  static Future<String?> sendOneOff({
    required int messageId,
    required String phone,
    required String body,
    int? subId,
  }) async {
    try {
      return await _channel.invokeMethod<String?>('sendOneOff', {
        'messageId': messageId,
        'phone': phone,
        'body': body,
        'subId': subId,
      });
    } on PlatformException catch (e) {
      return e.message ?? 'Send failed';
    } on MissingPluginException {
      return 'SMS is not available on this device';
    }
  }

  /// Arms / disarms the native alarm behind a scheduled campaign. The row in
  /// the database is the schedule; these only manage the wake-up call.
  static Future<void> scheduleAlarm({
    required int campaignId,
    required int atMillis,
  }) => _invoke('scheduleAlarm', {
    'campaignId': campaignId,
    'atMillis': atMillis,
  });

  static Future<void> cancelAlarm({required int campaignId}) =>
      _invoke('cancelAlarm', {'campaignId': campaignId});

  /// Opens this app's page in the phone settings — the only route to a
  /// permission once Android has stopped showing its dialog.
  static Future<void> openAppSettings() => _invoke('openAppSettings');

  /// The phone book's photo for a number, as raw bytes. Null when they have
  /// none, or when the contacts permission has not been granted.
  static Future<Uint8List?> contactPhoto(String phone) async {
    try {
      return await _channel.invokeMethod<Uint8List>('contactPhoto', {
        'phone': phone,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Arms / disarms the alarm behind one scheduled personal message.
  static Future<void> scheduleMessageAlarm({
    required int id,
    required int atMillis,
  }) => _invoke('scheduleMessageAlarm', {'id': id, 'atMillis': atMillis});

  static Future<void> cancelMessageAlarm({required int id}) =>
      _invoke('cancelMessageAlarm', {'id': id});

  /// Arms / disarms the reminder for an appointment. Raises a notification
  /// rather than sending anything.
  static Future<void> scheduleAppointmentAlarm({
    required int id,
    required int atMillis,
  }) => _invoke('scheduleAppointmentAlarm', {'id': id, 'atMillis': atMillis});

  static Future<void> cancelAppointmentAlarm({required int id}) =>
      _invoke('cancelAppointmentAlarm', {'id': id});

  /// Hands a copy of the database to the share sheet. Returns null once the
  /// chooser is up, or a reason it could not be.
  static Future<String?> shareBackup({required String stamp}) async {
    try {
      return await _channel.invokeMethod<String>('shareBackup', {
        'stamp': stamp,
      });
    } on PlatformException catch (e) {
      return e.message ?? 'Could not share the backup.';
    } on MissingPluginException {
      return 'Could not share the backup.';
    }
  }

  /// Writes the DB and a status CSV somewhere the user can find them.
  /// Returns the human-readable locations written.
  static Future<List<String>> exportBackup({
    required String csv,
    required String stamp,
  }) async {
    final result = await _channel.invokeListMethod<Object?>('exportBackup', {
      'csv': csv,
      'stamp': stamp,
    });
    return (result ?? const []).map((e) => e.toString()).toList();
  }

  static Future<void> _invoke(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Only happens on a non-Android host; the app is Android-only by design.
    }
  }
}
