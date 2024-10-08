// ignore_for_file: avoid_print
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main() async {
  final yt = YoutubeExplode();
  final streamInfo = await yt.videos.streamsClient.getManifest('xHBLWgX_nT8');

  print(streamInfo);

  var streamInfoH = streamInfo.muxed.withHighestBitrate();
  print(streamInfoH);
  // Close the YoutubeExplode's http client.
  yt.close();
}
