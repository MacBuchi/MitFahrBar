// Hält die Agenten-Konfiguration des Dart-MCP-Servers zusammen (#289):
// beide Clients starten denselben Launcher, und der schaltet ab, was Code
// ungefragt umschreibt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Claude und Codex starten tool/dart_mcp.sh', () {
    expect(File('.mcp.json').readAsStringSync(), contains('tool/dart_mcp.sh'));
    expect(
      File('.codex/config.toml').readAsStringSync(),
      contains('tool/dart_mcp.sh'),
    );
  });

  test('der Launcher schaltet die umschreibenden Werkzeuge ab', () {
    final script = File('tool/dart_mcp.sh').readAsStringSync();
    final disable = RegExp(r'--disable (\S+)').firstMatch(script)!.group(1)!;
    expect(disable.split(','), containsAll(['dart_fix', 'dart_format']));
    expect(script, contains('--enable run_tests'));
    expect(
      script,
      contains('TZ=Europe/Berlin'),
      reason: 'run_tests soll dieselbe Zeitzone sehen wie die CI (#290)',
    );
  });

  test('der Version Guard nimmt .mcp.json aus', () {
    expect(
      File('.github/workflows/ci.yml').readAsStringSync(),
      contains("':!.mcp.json'"),
      reason: 'Agenten-Konfiguration erreicht nie ein Binary',
    );
  });
}
