// Integration test for the share path of the plugin, on a device.
//
// Android: the test waits for the marker lines the CI driver reads (see
// .github/workflows/integration.yml). The driver then delivers real share
// intents to the running example app with `adb shell am start`
// (ACTION_SEND, ACTION_SEND_MULTIPLE), and the test checks the plugin's
// media stream receives them.
//
// iOS: there is no share sheet or share extension UI on the simulator. The
// test asks the example app's native side (AppDelegate.swift) to do what the
// share extension does: write the share payload into the app group, then call
// the plugin's URL handler with a ShareMedia-<bundle id> URL. So the plugin's
// read, decode and stream path runs; the extension's own UI and write do not.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

const _iosTestChannel = MethodChannel('receive_sharing_intent_example/test');

// Shared with the CI driver for Android: it sends these intents.
const androidTextPayload = 'rsi-ci-text';
const androidImagePaths = [
  '/sdcard/Download/rsi-ci-1.png',
  '/sdcard/Download/rsi-ci-2.png',
];

void mark(String line) {
  // ignore: avoid_print
  print('RSI_MARK $line');
}

/// Reads the next event of [it], failing after two minutes.
Future<List<SharedMediaFile>> nextEvent(
  StreamIterator<List<SharedMediaFile>> it,
) async {
  final has = await it.moveNext().timeout(const Duration(minutes: 2));
  expect(has, isTrue, reason: 'the media stream closed without an event');
  return it.current;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app starts without a share', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    expect(initial, isEmpty);
  });

  testWidgets('shares reach the media stream', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));

    // Listen before the share arrives: the plugin only delivers to a listener.
    final it = StreamIterator(ReceiveSharingIntent.instance.getMediaStream());
    // The event channel's listen is asynchronous on the platform side.
    await Future<void>.delayed(const Duration(seconds: 2));

    if (Platform.isIOS) {
      await _iosTestChannel.invokeMethod<bool>(
        'shareJson',
        jsonEncode([
          {
            'path': androidTextPayload,
            'type': 'text',
            'mimeType': 'text/plain',
          },
        ]),
      );
      final text = await nextEvent(it);
      expect(text.length, 1);
      expect(text.single.type, SharedMediaType.text);
      expect(text.single.path, androidTextPayload);

      await _iosTestChannel.invokeMethod<bool>(
        'shareJson',
        jsonEncode([
          for (final path in androidImagePaths)
            {'path': 'file://$path', 'type': 'image', 'mimeType': 'image/png'},
        ]),
      );
      final images = await nextEvent(it);
      expect(images.length, 2);
      for (var i = 0; i < 2; i++) {
        expect(images[i].type, SharedMediaType.image);
        expect(images[i].path, androidImagePaths[i]);
      }
    } else {
      // Android: the driver sends ACTION_SEND (text), then
      // ACTION_SEND_MULTIPLE (two images), once each is announced.
      mark('READY text');
      final text = await nextEvent(it);
      expect(text.length, 1);
      expect(text.single.type, SharedMediaType.text);
      expect(text.single.path, androidTextPayload);
      expect(text.single.mimeType, 'text/plain');

      mark('READY images');
      final images = await nextEvent(it);
      expect(images.length, 2);
      for (var i = 0; i < 2; i++) {
        expect(images[i].type, SharedMediaType.image);
        expect(images[i].path, androidImagePaths[i]);
      }
    }
    mark('DONE stream');

    await it.cancel();

    await ReceiveSharingIntent.instance.reset();
    final afterReset = await ReceiveSharingIntent.instance.getInitialMedia();
    expect(afterReset, isEmpty);
  });
}
