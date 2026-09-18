import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/native_bottom_tab_bar.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  testWidgets(
    'native tabs keep stable IDs, owned icons, badges, and live sizing',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        const items = [
          NativeBottomTabItem(
            id: 0,
            label: 'Messages',
            icon: HeroAppIcons.solidMessage,
          ),
          NativeBottomTabItem(
            id: 2,
            label: 'Contacts',
            icon: HeroAppIcons.users,
          ),
        ];
        Map<Object?, Object?>? created;
        var id = -1;
        final updates = <MethodCall>[];
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
          call,
        ) async {
          if (call.method == 'create') {
            final arguments = call.arguments as Map;
            id = arguments['id'] as int;
            created =
                const StandardMessageCodec().decodeMessage(
                      ByteData.sublistView(arguments['params'] as Uint8List),
                    )
                    as Map;
            messenger.setMockMethodCallHandler(
              MethodChannel('mithka/native_bottom_bar/$id'),
              (call) async {
                updates.add(call);
                return null;
              },
            );
          }
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(
            SystemChannels.platform_views,
            null,
          );
          messenger.setMockMethodCallHandler(
            MethodChannel('mithka/native_bottom_bar/$id'),
            null,
          );
        });
        var selected = 0;
        var clears = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(extensions: [AppColors.light]),
            home: Align(
              alignment: Alignment.bottomCenter,
              child: NativeBottomTabBar(
                items: items,
                selection: 0,
                unread: 252,
                unreadLabel: '99+',
                onSelect: (index) => selected = index,
                onClearUnread: () => clears++,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(id, greaterThanOrEqualTo(0));
        expect(created!['unread'], 252);
        expect(created!['unreadLabel'], '99+');
        final nativeItems = created!['items'] as List;
        expect((nativeItems[1] as Map)['id'], 2);
        expect(
          (nativeItems[1] as Map)['codePoint'],
          HeroAppIcons.users.data.codePoint,
        );
        expect(
          (nativeItems[1] as Map)['fontFamily'],
          HeroAppIcons.users.data.fontFamily,
        );
        expect(updates.last.method, 'update');

        Future<void> nativeCall(String method, Object? value) async {
          await messenger.handlePlatformMessage(
            'mithka/native_bottom_bar/$id',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, value),
            ),
            (_) {},
          );
          await tester.pump();
        }

        await nativeCall('select', 2);
        expect(selected, 1);
        await nativeCall('select', 99);
        expect(
          selected,
          1,
          reason: 'ignore callbacks for a removed or stale tab',
        );
        await nativeCall('clearUnread', null);
        expect(clears, 1);
        await nativeCall('height', 92.0);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('native-bottom-tab-bar')))
              .height,
          92,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
