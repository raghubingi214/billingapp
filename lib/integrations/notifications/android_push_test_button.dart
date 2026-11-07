import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A development-only entry point for the Firebase Console test sender.
class AndroidPushTestButton extends StatefulWidget {
  const AndroidPushTestButton({super.key});

  @override
  State<AndroidPushTestButton> createState() => _AndroidPushTestButtonState();
}

class _AndroidPushTestButtonState extends State<AndroidPushTestButton> {
  bool _busy = false;

  Future<void> _copyToken() async {
    setState(() => _busy = true);
    String message;
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        message = 'Allow notifications in Android settings to test push.';
      } else {
        final token = await messaging.getToken();
        if (token == null) throw StateError('Device token unavailable');
        await Clipboard.setData(ClipboardData(text: token));
        message = 'Test token copied. Paste it into Firebase Console.';
      }
    } catch (_) {
      message = 'Unable to get a test token. Check Firebase setup and network.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }
    return OutlinedButton.icon(
      onPressed: _busy ? null : _copyToken,
      icon: const Icon(Icons.notifications_active_outlined),
      label: Text(
        _busy ? 'Getting test token…' : 'Copy Android push test token',
      ),
    );
  }
}
