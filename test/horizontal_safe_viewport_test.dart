import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/adaptive_split_layout.dart';
import 'package:mithka/app/horizontal_safe_viewport.dart';

void main() {
  testWidgets('side controls remain below a full-window blocking overlay', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(466, 678);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var blocked = false;
    var taps = 0;
    late StateSetter update;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(466, 678),
            padding: EdgeInsets.only(right: 84, bottom: 34),
          ),
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Stack(
                children: [
                  Positioned.fill(
                    child: HorizontalSafeViewport(
                      sideNavigation: true,
                      child: SideNavigationPortal(
                        visible: true,
                        child: GestureDetector(
                          onTap: () => taps++,
                          child: const SizedBox(
                            width: 84,
                            height: 64,
                            child: ColoredBox(color: Color(0xff0000ff)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (blocked)
                    const Positioned.fill(
                      child: AbsorbPointer(
                        child: ColoredBox(color: Color(0xff000000)),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(425, 610));
    expect(taps, 1);
    update(() => blocked = true);
    await tester.pump();
    await tester.tapAt(const Offset(425, 610));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Duo reserves the side status area and preserves bottom insets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(466, 678);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    MediaQueryData? actual;
    const contentKey = ValueKey('content');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(466, 678),
            padding: EdgeInsets.only(right: 84, bottom: 34),
            viewPadding: EdgeInsets.only(right: 84, bottom: 34),
          ),
          child: HorizontalSafeViewport(
            child: Builder(
              builder: (context) {
                actual = MediaQuery.of(context);
                return const SizedBox.expand(key: contentKey);
              },
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getRect(find.byKey(contentKey)),
      const Rect.fromLTWH(0, 0, 382, 678),
    );
    expect(actual!.size, const Size(382, 678));
    expect(actual!.padding, const EdgeInsets.only(bottom: 34));
    expect(actual!.viewPadding, const EdgeInsets.only(bottom: 34));
  });

  testWidgets(
    'moving system chrome preserves content and uses usable split width',
    (tester) async {
      tester.view.physicalSize = const Size(800, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      MediaQueryData? actual;
      const key = ValueKey('retained');
      final content = Builder(
        key: key,
        builder: (context) {
          actual = MediaQuery.of(context);
          return const SizedBox.expand();
        },
      );
      Future<void> show(EdgeInsets insets) => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 650),
              padding: insets,
              viewPadding: insets,
              displayFeatures: const [
                DisplayFeature(
                  bounds: Rect.fromLTWH(400, 0, 0, 650),
                  type: DisplayFeatureType.fold,
                  state: DisplayFeatureState.postureHalfOpened,
                ),
              ],
            ),
            child: HorizontalSafeViewport(sideNavigation: true, child: content),
          ),
        ),
      );
      await show(const EdgeInsets.only(right: 84));
      final element = tester.element(find.byKey(key));
      expect(actual!.size.width, 716);
      expect(
        usesAdaptiveSplitLayout(actual!.size, platform: TargetPlatform.iOS),
        isFalse,
      );
      await show(EdgeInsets.zero);
      expect(
        usesAdaptiveSplitLayout(actual!.size, platform: TargetPlatform.iOS),
        isTrue,
      );
      await show(const EdgeInsets.only(left: 84));
      expect(tester.element(find.byKey(key)), same(element));
      expect(tester.getTopLeft(find.byKey(key)).dx, 84);
      expect(actual!.displayFeatures.single.bounds.left, 316);
      expect(
        actual!.displayFeatures.single.state,
        DisplayFeatureState.postureHalfOpened,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
