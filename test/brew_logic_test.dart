import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:filter_brew_companion/main.dart';

void main() {
  test('ratio math matches dose and yield', () {
    final entry = BrewLogEntry(
      id: '1',
      brewedAt: DateTime.utc(2026, 7, 15),
      methodName: 'V60',
      bean: 'House Blend',
      roast: 'Medium',
      grind: 'Medium fine',
      doseG: 18,
      yieldG: 270,
      rating: 4.5,
      tags: const ['Sweet'],
      notes: 'Clean cup',
    );

    expect(entry.ratio, 15);
    expect(fmt(210), '3:30');
  });

  test('settings and logs persist through BrewStore', () async {
    SharedPreferences.setMockInitialValues({});
    final store = BrewStore();
    final settings = BrewSettings.defaults().copyWith(
      defaultMethod: 'kalita',
      strength: 1.1,
      cupSizeMl: 140,
      themeMode: ThemeMode.dark,
    );

    await store.saveSettings(settings);
    final loadedSettings = await store.loadSettings();
    expect(loadedSettings.defaultMethod, 'kalita');
    expect(loadedSettings.strength, 1.1);
    expect(loadedSettings.cupSizeMl, 140);
    expect(loadedSettings.themeMode, ThemeMode.dark);

    final log = BrewLogEntry(
      id: 'persisted',
      brewedAt: DateTime.utc(2026, 7, 15),
      methodName: 'South Filter',
      bean: 'Chikmagalur',
      roast: 'Dark',
      grind: 'Fine',
      doseG: 20,
      yieldG: 160,
      rating: 5,
      tags: const ['Chocolate'],
      notes: 'Dense decoction',
    );
    await store.saveLogs([log]);
    final logs = await store.loadLogs();

    expect(logs, hasLength(1));
    expect(logs.single.id, 'persisted');
    expect(logs.single.ratio, 8);
  });
}
