import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_player_view.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/moments/moments_view.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final contentType in [
    'messageAnimation',
    'messageVideoNote',
    'messageVideo',
  ]) {
    testWidgets('Moments opens thumbnail-less $contentType', (tester) async {
      final video = TdFileRef(id: 901);
      final message = ChatMessage(
        id: 7,
        isOutgoing: false,
        text: '',
        date: 1,
        contentType: contentType,
        video: video,
        videoDuration: 7,
        imageWidth: 320,
        imageHeight: 240,
      );
      final observer = _MediaRouteObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: Scaffold(
            body: ChannelPostRow(
              post: ChannelPost(
                channel: ChatSummary(
                  id: 42,
                  title: 'Channel',
                  lastMessage: '',
                  lastMessageId: 7,
                  date: 1,
                  unreadCount: 0,
                  order: 1,
                  isMuted: false,
                  kind: ChatKind.channel,
                ),
                message: message,
                accountSlot: 2,
              ),
              meName: 'Me',
              showInlineReply: false,
              showInlineComments: false,
            ),
          ),
        ),
      );
      final tile = find.byKey(const ValueKey('moments-media-7'));
      expect(tile, findsOneWidget);
      await tester.tap(tile);
      final route = observer.latest as MaterialPageRoute;
      final player =
          route.builder(tester.element(tile)) as VideoOnDemandPlayerView;
      expect(player.queue.items.single.video, same(video));
      expect(player.queue.items.single.durationSeconds, 7);
      expect(player.queue.items.single.accountSlot, 2);
      expect(player.queue.items.single.messageId, 7);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Moments shows forwarding and unresolved reply attribution', (
    tester,
  ) async {
    final message =
        ChatMessage(
            id: 7,
            isOutgoing: false,
            text: '',
            date: 1,
            replyToMessageId: 9,
          )
          ..forwardFromChatId = -44
          ..forwardOrigin = 'Source channel'
          ..forwardAuthorSignature = 'Alice';
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        home: Scaffold(
          body: ChannelPostRow(
            post: ChannelPost(
              channel: ChatSummary(
                id: 42,
                title: 'Channel',
                lastMessage: '',
                lastMessageId: 7,
                date: 1,
                unreadCount: 0,
                order: 1,
                isMuted: false,
                kind: ChatKind.channel,
              ),
              message: message,
              accountSlot: 0,
            ),
            meName: 'Me',
            showInlineReply: false,
            showInlineComments: false,
          ),
        ),
      ),
    );
    expect(find.text('Forwarded from Source channel (Alice)'), findsOneWidget);
    expect(find.byKey(const ValueKey('momentsReplyQuote')), findsOneWidget);
    expect(find.text('Reply', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Moments shows media-only reply quotes', (tester) async {
    final quotedImage = TdFileRef(
      id: 900,
      localPath: '${Directory.current.path}/assets/penguin.png',
    );
    final channel = ChatSummary(
      id: 42,
      title: 'Channel',
      lastMessage: '',
      lastMessageId: 7,
      date: 1,
      unreadCount: 0,
      order: 1,
      isMuted: false,
      kind: ChatKind.channel,
    );
    final message =
        ChatMessage(
            id: 7,
            isOutgoing: false,
            text: 'Moment',
            date: 1,
            contentType: 'messageText',
            replyToMessageId: 9,
            replyToImage: quotedImage,
            replyToImageWidth: 600,
            replyToImageHeight: 400,
          )
          ..replyToSender = 'Original channel'
          ..replyToPreview = '';

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(extensions: [AppColors.light]),
        home: Scaffold(
          body: ChannelPostRow(
            post: ChannelPost(
              channel: channel,
              message: message,
              accountSlot: 0,
            ),
            meName: 'Me',
            showInlineReply: false,
            showInlineComments: false,
          ),
        ),
      ),
    );
    await tester.pump();

    final mediaPreview = find.byKey(const ValueKey('momentsReplyMediaPreview'));
    expect(mediaPreview, findsOneWidget);
    final image = tester.widget<TDImage>(
      find.descendant(of: mediaPreview, matching: find.byType(TDImage)),
    );
    expect(image.photo, same(quotedImage));
  });
}

class _MediaRouteObserver extends NavigatorObserver {
  Route<dynamic>? latest;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    latest = route;
  }
}
