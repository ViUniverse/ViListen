import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';

PlayerItem testPlayerItem({
  String id = 'track-1',
  Uri? audioUri,
  String title = 'Test track',
  String artist = 'Test artist',
  String? album,
  Uri? artUri,
  Duration? duration,
  Map<String, Object?> extras = const <String, Object?>{},
}) => PlayerItem(
  id: id,
  audioUri: audioUri ?? Uri.parse('https://cdn.example.test/audio/$id.mp3'),
  title: title,
  artist: artist,
  album: album,
  artUri: artUri,
  duration: duration,
  extras: extras,
);
