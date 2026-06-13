import 'dart:convert';
import 'dart:io';

import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verifies that raw Runtime Adapter diagnostics are reduced through the public
/// Flutter Pilot API into compact agent-facing summaries.
void main() {
  group('DiagnosticReducer', () {
    test('preserves visible text and interactive widgets from Snapshot', () {
      final Object snapshot = jsonDecode(
        File(
          'test/fixtures/diagnostics/snapshot_checkout.json',
        ).readAsStringSync(),
      );

      final DiagnosticSummary summary = DiagnosticReducer.reduce(
        snapshot: snapshot,
      );

      expect(summary.visibleText, <String>['Checkout', 'Email', 'Pay now']);
      expect(summary.routes, <String>['/checkout']);
      expect(
        summary.interactiveWidgets.map(
          (DiagnosticWidgetSummary widget) => widget.toJson(),
        ),
        <Map<String, Object?>>[
          <String, Object?>{
            'type': 'textField',
            'label': 'Email',
            'text': 'bad@example.com',
            'enabled': true,
          },
          <String, Object?>{
            'type': 'button',
            'text': 'Pay now',
            'enabled': true,
          },
        ],
      );
      expect(summary.toJson().toString(), isNot(contains('RenderParagraph')));
      expect(summary.toJson().toString(), isNot(contains('BoxConstraints')));
      expect(summary.toJson().toString(), isNot(contains('SemanticsNode#14')));
    });

    test('preserves route context and likely suspects from Widget Tree', () {
      final Object widgetTree = jsonDecode(
        File(
          'test/fixtures/diagnostics/widget_tree_checkout.json',
        ).readAsStringSync(),
      );

      final DiagnosticSummary summary = DiagnosticReducer.reduce(
        widgetTree: widgetTree,
      );

      expect(summary.routes, <String>['CheckoutPage']);
      expect(summary.likelySuspects, <String>[
        'CheckoutPage',
        'EmailTextField',
        'PrimaryButton',
      ]);
      expect(summary.visibleText, <String>['Email', 'Pay now']);
      expect(
        summary.toJson().toString(),
        isNot(contains('_CheckoutPageState')),
      );
      expect(summary.toJson().toString(), isNot(contains('RenderEditable')));
      expect(summary.toJson().toString(), isNot(contains('NavigatorState#')));
    });

    test('preserves runtime failures and useful logs from Logs data', () {
      final Object logs = jsonDecode(
        File('test/fixtures/diagnostics/logs_checkout.json').readAsStringSync(),
      );

      final DiagnosticSummary summary = DiagnosticReducer.reduce(logs: logs);

      expect(summary.logs, <String>['Submitting checkout form']);
      expect(summary.runtimeFailures, <String>[
        'Exception caught by widgets library: Null check operator used on a null value',
        'RenderFlex overflowed by 18 pixels',
      ]);
      expect(summary.likelySuspects, <String>[
        'package:shop_app/features/checkout/checkout_controller.dart:42:18',
        'package:shop_app/features/checkout/checkout_page.dart:88:12',
      ]);
      expect(
        summary.toJson().toString(),
        isNot(contains('Rebuilding inherited widgets')),
      );
      expect(
        summary.toJson().toString(),
        isNot(contains('#0 CheckoutController')),
      );
    });
  });
}
