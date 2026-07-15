import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:filter_brew_companion/main.dart';

void main() {
  testWidgets('renders brew controls and starts timer', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const BrewCompanionApp());
    await tester.pumpAndSettle();

    expect(find.text('Giri Brew Companion'), findsWidgets);
    expect(find.text('V60'), findsWidgets);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pump();

    expect(find.text('Pause'), findsOneWidget);
  });
}
