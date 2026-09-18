import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/liquid_glass_bottom_bar.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/feature_settings_view.dart';
import 'package:mithka/settings/safety_notice_controller.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('glass setting defaults off and persists both choices', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final safety = SafetyNoticeController(prefs);
    addTearDown(theme.dispose);
    addTearDown(safety.dispose);
    expect(theme.liquidGlassBottomBar, isFalse);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: safety),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate],
          home: FeatureSettingsView(),
        ),
      ),
    );
    final row = find.byKey(const ValueKey('settings-liquid-glass-bottom-bar'));
    expect(tester.widget<SettingsSwitchRow>(row).value, isFalse);
    for (final value in [true, false]) {
      await tester.tap(row);
      await tester.pump();
      expect(theme.liquidGlassBottomBar, value);
      expect(prefs.getBool('liquidGlassBottomBar'), value);
      final restored = ThemeController(prefs);
      expect(restored.liquidGlassBottomBar, value);
      restored.dispose();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass respects safe area, RTL, contrast, and reduced motion', (
    tester,
  ) async {
    var selection = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.dark]),
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(bottom: 34),
            disableAnimations: true,
            highContrast: true,
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 320,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return LiquidGlassBottomBar(
                      selection: selection,
                      itemCount: 4,
                      child: const SizedBox(height: 90, width: double.infinity),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final bar = find.byType(LiquidGlassBottomBar);
    final pill = find.byKey(const ValueKey('liquid-glass-selection'));
    final initial = tester.getRect(pill);
    expect(tester.getRect(bar).bottom - initial.bottom, 39);
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
      isFalse,
    );
    update(() => selection = 3);
    await tester.pump();
    expect(tester.getRect(pill).left, lessThan(initial.left));
    expect(
      tester
          .widget<AnimatedPositionedDirectional>(
            find.byType(AnimatedPositionedDirectional),
          )
          .duration,
      Duration.zero,
    );
    expect(tester.takeException(), isNull);
  });
}
