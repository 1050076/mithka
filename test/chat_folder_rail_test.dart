import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/chats/chat_list_view_model.dart';

void main() {
  testWidgets(
    'folder rail scrolls and changes selection without moving lower navigation',
    (tester) async {
      int? selected;
      late StateSetter update;
      const navigationKey = ValueKey('fixed-navigation');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: DefaultTextStyle(
              style: const TextStyle(fontSize: 11),
              child: Center(
                child: SizedBox(
                  width: 72,
                  height: 300,
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      return Column(
                        children: [
                          Expanded(
                            child: ChatFolderRail(
                              filters: [
                                const ChatFilterOption(title: 'All'),
                                for (var i = 0; i < 12; i++)
                                  ChatFilterOption(
                                    title: 'Folder $i',
                                    folderId: i,
                                  ),
                              ],
                              selectedFolderId: selected,
                              onSelect: (folder) =>
                                  update(() => selected = folder.folderId),
                            ),
                          ),
                          const SizedBox(key: navigationKey, height: 64),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final navigationRect = tester.getRect(find.byKey(navigationKey));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('side-folder-10')),
        120,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('side-folder-10')));
      await tester.pumpAndSettle();
      expect(selected, 10);
      expect(tester.getRect(find.byKey(navigationKey)), navigationRect);
      expect(tester.takeException(), isNull);
    },
  );
}
