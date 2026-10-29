// Widget test of the example app: it shows the shared media it receives.

import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:receive_sharing_intent_example/main.dart';

void main() {
  testWidgets('the example app shows the shared media heading', (
    WidgetTester tester,
  ) async {
    ReceiveSharingIntent.setMockValues(
      initialMedia: [],
      mediaStream: Stream.empty(),
    );
    await tester.pumpWidget(MyApp());
    await tester.pump();

    expect(find.text('Shared files:'), findsOneWidget);
  });
}
