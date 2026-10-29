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

/// Hands [payload] to the example app's native side, which writes it into the
/// app group and opens the plugin with the share URL. Returns its report.
Future<String> _iosShare(String payload) async {
  final report = await _iosTestChannel.invokeMethod<String>(
    'shareJson',
    payload,
  );
  return report ?? 'no report';
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
    // Subscribe now, not at the first moveNext: the plugin delivers only to a
    // listener that exists when the share arrives. The controller buffers.
    final buffered = StreamController<List<SharedMediaFile>>();
    final sub = ReceiveSharingIntent.instance.getMediaStream().listen(
      buffered.add,
      onError: buffered.addError,
    );
    final it = StreamIterator(buffered.stream);
    // The event channel's listen is asynchronous on the platform side.
    await Future<void>.delayed(const Duration(seconds: 2));

    if (Platform.isIOS) {
      // The native side returns what it did (print does not reach the CI log
      // on iOS), so a failed expectation shows it.
      final text = await _iosShare(
        jsonEncode([
          {
            'path': androidTextPayload,
            'type': 'text',
            'mimeType': 'text/plain',
          },
        ]),
      );
      expect(text, contains('handled=true'), reason: text);
      final textEvent = await nextEvent(it);
      expect(textEvent.length, 1, reason: text);
      expect(textEvent.single.type, SharedMediaType.text);
      expect(textEvent.single.path, androidTextPayload);

      final images = await _iosShare(
        jsonEncode([
          for (final path in androidImagePaths)
            {'path': 'file://$path', 'type': 'image', 'mimeType': 'image/png'},
        ]),
      );
      expect(images, contains('handled=true'), reason: images);
      final imageEvent = await nextEvent(it);
      expect(imageEvent.length, 2, reason: images);
      for (var i = 0; i < 2; i++) {
        expect(imageEvent[i].type, SharedMediaType.image);
        expect(imageEvent[i].path, androidImagePaths[i]);
      }
    } else {
      // Android: the driver sends ACTION_SEND (text), then ACTION_SEND with
      // one image, once each is announced. ACTION_SEND_MULTIPLE is not sent:
      // `am start --eu` passes EXTRA_STREAM as one Uri, not the ArrayList<Uri>
      // a multi-share carries (logcat: "expected ArrayList<Uri>").
      mark('READY text');
      final text = await nextEvent(it);
      expect(text.length, 1);
      expect(text.single.type, SharedMediaType.text);
      expect(text.single.path, androidTextPayload);
      expect(text.single.mimeType, 'text/plain');

      mark('READY images');
      final images = await nextEvent(it);
      expect(images.length, 1);
      expect(images.single.type, SharedMediaType.image);
      expect(images.single.path, androidImagePaths.first);
      expect(images.single.mimeType, 'image/png');
    }
    mark('DONE stream');

    await it.cancel();
    await sub.cancel();
    await buffered.close();

    await ReceiveSharingIntent.instance.reset();
    final afterReset = await ReceiveSharingIntent.instance.getInitialMedia();
    expect(afterReset, isEmpty);
  });
}
