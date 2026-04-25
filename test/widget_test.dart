import 'package:flutter_test/flutter_test.dart';
import 'package:myroom/main.dart';

void main() {
  testWidgets('MyRoom smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyRoomApp());
    expect(find.text('myroom'), findsOneWidget);
  });
}
