import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import '../../../youtube_explode_dart.dart';
import '../../extensions/helpers_extension.dart';
import '../../retry.dart';
import '../youtube_http_client.dart';

///
class PlaylistPage {
  final _apiKeyExp = RegExp(r'"INNERTUBE_API_KEY":"(\w+?)"');

  ///
  final String playlistId;
  final Document _root;

  String _apiKey;

  ///
  String get apiKey => _apiKey ??= _apiKeyExp
      .firstMatch(_root
          .querySelectorAll('script')
          .firstWhere((e) => e.text.contains('INNERTUBE_API_KEY'))
          .text)
      .group(1);

  _InitialData _initialData;

  ///
  _InitialData get initialData {
    if (_initialData != null) {
      return _initialData;
    }

    final scriptText = _root
        .querySelectorAll('script')
        .map((e) => e.text)
        .toList(growable: false);

    var initialDataText = scriptText.firstWhere(
        (e) => e.contains('window["ytInitialData"] ='),
        orElse: () => null);
    if (initialDataText != null) {
      return _initialData = _InitialData(json
          .decode(_extractJson(initialDataText, 'window["ytInitialData"] =')));
    }

    initialDataText = scriptText.firstWhere(
        (e) => e.contains('var ytInitialData = '),
        orElse: () => null);
    if (initialDataText != null) {
      return _initialData = _InitialData(
          json.decode(_extractJson(initialDataText, 'var ytInitialData = ')));
    }

    throw TransientFailureException(
        'Failed to retrieve initial data from the search page, please report this to the project GitHub page.'); // ignore: lines_longer_than_80_chars
  }

  String _extractJson(String html, String separator) {
    if (html == null || separator == null) {
      return null;
    }
    var index = html.indexOf(separator) + separator.length;
    if (index > html.length) {
      return null;
    }
    return _matchJson(html.substring(index));
  }

  String _matchJson(String str) {
    var bracketCount = 0;
    int lastI;
    for (var i = 0; i < str.length; i++) {
      lastI = i;
      if (str[i] == '{') {
        bracketCount++;
      } else if (str[i] == '}') {
        bracketCount--;
      } else if (str[i] == ';') {
        if (bracketCount == 0) {
          return str.substring(0, i);
        }
      }
    }
    return str.substring(0, lastI + 1);
  }

  ///
  PlaylistPage(this._root, this.playlistId,
      [_InitialData initialData, this._apiKey])
      : _initialData = initialData;

  ///
  Future<PlaylistPage> nextPage(YoutubeHttpClient httpClient) async {
    if (initialData.continuationToken == null) {
      return null;
    }
    return get(httpClient, playlistId, token: initialData.continuationToken);
  }

  ///
  static Future<PlaylistPage> get(YoutubeHttpClient httpClient, String id,
      {String token}) {
    if (token != null && token.isNotEmpty) {
      var url =
          'https://www.youtube.com/youtubei/v1/search?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

      return retry(() async {
        var body = {
          'context': const {
            'client': {
              'hl': 'en',
              'clientName': 'WEB',
              'clientVersion': '2.20200911.04.00'
            }
          },
          'continuation': token
        };

        var raw = await httpClient.post(url, body: json.encode(body));
        return PlaylistPage(null, id, _InitialData(json.decode(raw.body)));
      });
      // Ask for next page,

    }
    var url = 'https://www.youtube.com/playlist?list=$id&hl=en&persist_hl=1';
    return retry(() async {
      var raw = await httpClient.getString(url);
      return PlaylistPage.parse(raw, id);
    });
    // ask for next page
  }

  ///
  PlaylistPage.parse(String raw, this.playlistId) : _root = parser.parse(raw);
}

class _InitialData {
  // Json parsed map
  final Map<String, dynamic> root;

  _InitialData(this.root);

  String get title => root
      ?.get('metadata')
      ?.get('playlistMetadataRenderer')
      ?.getT<String>('title');

  String get author => root
      .get('sidebar')
      ?.get('playlistSidebarRenderer')
      ?.getList('items')
      ?.elementAtSafe(1)
      ?.get('playlistSidebarSecondaryInfoRenderer')
      ?.get('videoOwner')
      ?.get('videoOwnerRenderer')
      ?.get('title')
      ?.getT<List<dynamic>>('runs')
      ?.parseRuns();

  String get description => root
      ?.get('metadata')
      ?.get('playlistMetadataRenderer')
      ?.getT<String>('description');

  int get viewCount => root
      ?.get('sidebar')
      ?.get('playlistSidebarRenderer')
      ?.getList('items')
      ?.firstOrNull
      ?.get('playlistSidebarPrimaryInfoRenderer')
      ?.getList('stats')
      ?.elementAtSafe(1)
      ?.getT<String>('simpleText')
      ?.parseInt();

  String get continuationToken => (videosContent ?? playlistVideosContent)
      ?.firstWhere((e) => e['continuationItemRenderer'] != null,
          orElse: () => null)
      ?.get('continuationItemRenderer')
      ?.get('continuationEndpoint')
      ?.get('continuationCommand')
      ?.getT<String>('token');

  List<Map<String, dynamic>> get playlistVideosContent =>
      root
          .get('contents')
          ?.get('twoColumnBrowseResultsRenderer')
          ?.getList('tabs')
          ?.firstOrNull
          ?.get('tabRenderer')
          ?.get('content')
          ?.get('sectionListRenderer')
          ?.getList('contents')
          ?.firstOrNull
          ?.get('itemSectionRenderer')
          ?.getList('contents')
          ?.firstOrNull
          ?.get('playlistVideoListRenderer')
          ?.getList('contents') ??
      root
          .getList('onResponseReceivedActions')
          ?.firstOrNull
          ?.get('appendContinuationItemsAction')
          ?.get('continuationItems');

  List<Map<String, dynamic>> get videosContent =>
      root
          .get('contents')
          ?.get('twoColumnSearchResultsRenderer')
          ?.get('primaryContents')
          ?.get('sectionListRenderer')
          ?.getList('contents') ??
      root
          ?.getList('onResponseReceivedCommands')
          ?.firstOrNull
          ?.get('appendContinuationItemsAction')
          ?.get('continuationItems');

  List<_Video> get playlistVideos =>
      playlistVideosContent
          ?.where((e) => e['playlistVideoRenderer'] != null)
          ?.map((e) => _Video(e['playlistVideoRenderer']))
          ?.toList() ??
      const [];

  List<_Video> get videos =>
      videosContent?.firstOrNull
          ?.get('itemSectionRenderer')
          ?.getList('contents')
          ?.where((e) => e['videoRenderer'] != null)
          ?.map((e) => _Video(e))
          ?.toList() ??
      const [];
}

class _Video {
  // Json parsed map
  final Map<String, dynamic> root;

  _Video(this.root);

  String get id => root?.getT<String>('videoId');

  String get author =>
      root?.get('ownerText')?.getT<List<dynamic>>('runs')?.parseRuns() ??
      root?.get('shortBylineText')?.getT<List<dynamic>>('runs')?.parseRuns() ??
      '';

  String get channelId =>
      root
          .get('ownerText')
          ?.getList('runs')
          ?.firstOrNull
          ?.get('navigationEndpoint')
          ?.get('browseEndpoint')
          ?.getT<String>('browseId') ??
      root
          .get('shortBylineText')
          ?.getList('runs')
          ?.firstOrNull
          ?.get('navigationEndpoint')
          ?.get('browseEndpoint')
          ?.getT<String>('browseId') ??
      '';

  String get title => root.get('title')?.getList('runs')?.parseRuns() ?? '';

  String get description =>
      root.getList('descriptionSnippet')?.parseRuns() ?? '';

  Duration get duration =>
      _stringToDuration(root.get('lengthText')?.getT<String>('simpleText'));

  int get viewCount =>
      root.get('viewCountText')?.getT<String>('simpleText')?.parseInt() ?? 0;

  /// Format: HH:MM:SS
  static Duration _stringToDuration(String string) {
    if (string == null || string.trim().isEmpty) {
      return null;
    }

    var parts = string.split(':');
    assert(parts.length <= 3);

    if (parts.length == 1) {
      return Duration(seconds: int.parse(parts.first));
    }
    if (parts.length == 2) {
      return Duration(
          minutes: int.parse(parts.first), seconds: int.parse(parts[1]));
    }
    if (parts.length == 3) {
      return Duration(
          hours: int.parse(parts[0]),
          minutes: int.parse(parts[1]),
          seconds: int.parse(parts[2]));
    }
    throw Error();
  }
}