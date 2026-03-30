import 'package:flutter_test/flutter_test.dart';
import 'package:esp32_oled_app/main.dart';

void main() {
  testWidgets('App should build without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const ESP32OLEDApp());
    expect(find.text('ESP32 OLED 配网'), findsOneWidget);
  });
}
