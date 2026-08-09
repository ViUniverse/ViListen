# Kế hoạch triển khai Player đa nền tảng

> Trạng thái: Đã chốt phương án<br>
> Cập nhật: 2026-08-02<br>
> Phạm vi release: Android, iOS, Web và macOS<br>
> Ngoài phạm vi hiện tại: Windows

Tài liệu này là projection triển khai của [Player Architecture Decisions](./player-architecture-decisions.md). Khi có khác biệt, ADR là chuẩn và tài liệu này phải được sửa ngay trong cùng thay đổi.

## 1. Mục tiêu

Triển khai một audio player dùng chung toàn ứng dụng, đáp ứng các yêu cầu:

- Phát audio thật thay cho trạng thái mô phỏng hiện tại.
- Mini player và expanded player luôn dùng chung một trạng thái.
- Hỗ trợ background playback.
- Hỗ trợ Android Media Controls/Media Player notification.
- Hỗ trợ iOS Now Playing, Lock Screen và Control Center.
- Hỗ trợ Web Media Session ở các trình duyệt có khả năng tương ứng.
- Hỗ trợ macOS Now Playing, Control Center và media keys.
- Hỗ trợ queue, seek, tua nhanh/chậm, tốc độ phát, repeat và shuffle.
- Xử lý loading, buffering, completed, interruption và error.
- Giữ kiến trúc đơn giản, một chiều và có thể kiểm thử.

## 2. Stack kỹ thuật

~~~yaml
dependencies:
  just_audio: ^0.10.6
  audio_service: ^0.18.19
  audio_session: ^0.2.4
~~~

Vai trò của từng package:

| Package | Trách nhiệm |
|---|---|
| <code>just_audio</code> | Audio engine: load, play, pause, seek, queue, speed, repeat, shuffle và stream trạng thái |
| <code>audio_service</code> | Background playback, Android notification, Apple Now Playing, Web Media Session và remote commands |
| <code>audio_session</code> | Audio focus, interruption policy và cấu hình phiên âm thanh |

Không cài thêm <code>just_audio_background</code>. Package này cũng dùng <code>audio_service</code> ở bên dưới và sẽ tạo thêm một lớp điều khiển không cần thiết.

Tài liệu tham khảo:

- [just_audio](https://pub.dev/packages/just_audio)
- [audio_service](https://pub.dev/packages/audio_service)
- [audio_session](https://pub.dev/packages/audio_session)

## 3. Nguyên tắc kiến trúc

### 3.1. Phương trình luồng dữ liệu

~~~text
UI Intent                         OS Intent
    ↓                                 ↓
PlayerCubit                     AppAudioHandler
    ↓ PlaybackGateway                  ↑
UiPlaybackGatewayAdapter ──→ UiPlaybackCommandTarget
                                      ↓
                               PlaybackEngine
                                      ↓
                           JustAudioPlaybackEngine
                                      ↓
                          just_audio.AudioPlayer
                                      ↓ engine streams
                               AppAudioHandler
                                 ↙          ↘
                 UiPlaybackGatewayAdapter   audio_service
                           ↓                      ↓
                      PlayerCubit          Lock screen /
                           ↓               Notification /
                      Toàn bộ UI            Control Center
~~~

### 3.2. Các bất biến bắt buộc

~~~text
UI không tự sửa playing hoặc progress.
Cubit không mô phỏng audio engine.
OS controls không phụ thuộc vào Cubit.
Chỉ có một AppAudioHandler, một JustAudioPlaybackEngine và một AudioPlayer trong toàn ứng dụng.
Audio engine là nguồn sự thật duy nhất.
~~~

Luồng command:

1. Mini player, expanded player hoặc màn hình khác gọi <code>PlayerCubit</code>.
2. Cubit chuyển command sang <code>PlaybackGateway</code>; production binding là <code>UiPlaybackGatewayAdapter</code>.
3. Lock screen, notification, headset và Control Center gọi trực tiếp <code>AppAudioHandler</code>.
4. Hai đường command hội tụ tại cùng internal operation của <code>AppAudioHandler</code>, rồi handler điều khiển <code>PlaybackEngine</code>.
5. Production <code>JustAudioPlaybackEngine</code> sở hữu duy nhất một <code>AudioPlayer</code>.
6. Stream thật từ engine cập nhật Cubit qua adapter và cập nhật system media controls qua <code>audio_service</code>.

Không phát sinh optimistic state kiểu tự đảo <code>isPlaying</code> trong Cubit. Trạng thái chính thức luôn quay về từ engine stream.

## 4. Cấu trúc source đề xuất

~~~text
lib/features/player/
├── domain/
│   ├── player_item.dart
│   ├── playback_snapshot.dart
│   ├── player_failure.dart
│   └── player_command_failure.dart
├── application/
│   ├── playback_gateway.dart
│   ├── player_cubit.dart
│   ├── player_state.dart
│   └── player_command_policies.dart
├── infrastructure/
│   ├── app_audio_handler.dart
│   ├── command_source.dart
│   ├── ui_playback_command_target.dart
│   ├── ui_playback_gateway_adapter.dart
│   ├── engine/
│   │   ├── playback_engine.dart
│   │   └── just_audio_playback_engine.dart
│   ├── playback_contexts.dart
│   ├── playback_mappers.dart
│   └── unavailable_playback_gateway.dart
└── presentation/
    ├── cubit/
    │   └── player_cubit.dart  # LegacyPlayerCubit, migration-only đến PLR-110
    ├── expanded_player_screen.dart
    └── widgets/
        ├── mini_player.dart
        ├── player_artwork.dart
        ├── player_control_dock.dart
        └── player_host.dart
~~~

Chưa cần tạo repository hoặc use-case riêng cho các lệnh playback. Chỉ bổ sung repository khi xuất hiện yêu cầu lưu lịch sử, download, đồng bộ tiến độ hoặc resume position lên server.

## 5. Domain model

### 5.1. PlayerItem

<code>PlayerItem</code> là metadata dùng chung cho UI, audio engine và system controls.

~~~dart
final class PlayerItem {
  const PlayerItem({
    required this.id,
    required this.audioUri,
    required this.title,
    required this.artist,
    this.album,
    this.artUri,
    this.duration,
    this.extras = const {},
  });

  final String id;
  final Uri audioUri;
  final String title;
  final String artist;
  final String? album;
  final Uri? artUri;
  final Duration? duration;
  final Map<String, Object?> extras;
}
~~~

Quy ước:

- <code>id</code> là content ID ổn định, không mặc định dùng URL.
- URL phát audio nằm ở <code>audioUri</code>.
- <code>audioUri</code>: chấp nhận <code>https</code> và asset trên mọi nền tảng; <code>file</code> chỉ trên native; từ chối <code>http</code> và mọi scheme khác trong release này.
- <code>artUri</code>: chấp nhận <code>https</code> trên mọi nền tảng và <code>file</code> trên native; từ chối <code>http</code> và scheme khác.
- <code>extras</code> phải immutable sâu và chỉ gồm <code>null</code>, <code>bool</code>, <code>int</code>, finite <code>double</code>, <code>String</code>, <code>Uri</code>, <code>Duration</code>, <code>List</code> hợp lệ hoặc <code>Map&lt;String, Object?&gt;</code> hợp lệ. Từ chối cycle, custom object, <code>Set</code>, key không phải <code>String</code> và số không finite.
- Khi chuyển sang <code>audio_service.MediaItem</code>, mapper hạ tầng ánh xạ metadata qua các typed fields tương ứng; chỉ project extras scalar tương thích platform. Source <code>audioUri</code> được serialize thành <code>String</code> trong reserved key <code>extras['audioUri']</code>.
- <code>MediaItem.extras</code> chỉ forward scalar <code>int</code>, <code>String</code>, <code>bool</code> và <code>double</code> qua platform boundary. <code>null</code>, <code>Uri</code>, <code>Duration</code>, list và map lồng nhau vẫn thuộc Domain, không đưa trực tiếp vào OS metadata. Reserved key <code>extras['audioUri']</code> chứa <code>audioUri.toString()</code>; duration dùng field <code>MediaItem.duration</code>, không encode vào extras.

### 5.2. PlaybackSnapshot

~~~text
currentItem?
queue
currentIndex

processingState:
  idle | loading | buffering | ready | completed | error

playing
position
bufferedPosition
duration

speed
repeatMode
shuffleEnabled
failure?
~~~

Các giá trị suy ra:

~~~text
progress    = position / duration
remaining   = duration - position
isBuffering = processingState == buffering
isAudible   = playing && processingState == ready
hasNext
hasPrevious
~~~

<code>playing</code> và <code>processingState</code> là hai trục độc lập:

- <code>playing=true + ready</code>: đang phát.
- <code>playing=true + buffering</code>: người dùng muốn phát, engine đang chờ dữ liệu.
- <code>playing=false + ready</code>: đã pause nhưng dữ liệu sẵn sàng.
- <code>playing=false + completed</code>: đã tới cuối queue với repeat off; handler đã phát đúng một lệnh chuẩn hóa <code>pause</code>, UI hiển thị Replay.

<code>queue</code> và <code>currentIndex</code> luôn biểu diễn effective queue order đang được engine dùng sau khi áp dụng shuffle. Domain snapshot và OS queue phải cùng một thứ tự.

## 6. PlaybackGateway

~~~dart
abstract interface class PlaybackGateway {
  Stream<PlaybackSnapshot> get snapshots;

  Future<void> loadQueue(
    List<PlayerItem> items, {
    int initialIndex = 0,
    bool autoplay = true,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> skipBy(Duration offset);
  Future<void> next();
  Future<void> previous();
  Future<void> setSpeed(double speed);
  Future<void> setRepeatMode(PlayerRepeatMode mode);
  Future<void> setShuffleEnabled(bool enabled);
  Future<void> retry();
}
~~~

Interface này là biên duy nhất giữa Cubit và hạ tầng playback. <code>UiPlaybackGatewayAdapter</code> là production implementation; <code>AppAudioHandler</code> không implement public Gateway. Phân tách này cho phép widget test dùng <code>FakePlaybackGateway</code> mà không khởi tạo platform plugin.

## 7. AppAudioHandler

<code>AppAudioHandler</code> là application service trung tâm, nhưng không trực tiếp sở hữu plugin:

~~~dart
final class AppAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements UiPlaybackCommandTarget {
  factory AppAudioHandler.production() =>
      AppAudioHandler(JustAudioPlaybackEngine());

  AppAudioHandler(this._engine);

  final PlaybackEngine _engine;
}

final class JustAudioPlaybackEngine implements PlaybackEngine {
  final AudioPlayer _player = AudioPlayer();
}

final class UiPlaybackGatewayAdapter implements PlaybackGateway {
  UiPlaybackGatewayAdapter(this._target);

  final UiPlaybackCommandTarget _target;
}
~~~

### 7.1. Trách nhiệm

- Sở hữu <code>PlaybackEngine</code>; production adapter của engine sở hữu duy nhất một <code>AudioPlayer</code>.
- Engine load chỉ prepare nguồn; handler commit/publication xong mới thực hiện
  autoplay bằng lệnh <code>play()</code> riêng.
- Chuyển <code>PlayerItem</code> thành <code>MediaItem</code> và <code>AudioSource</code>.
- Giữ effective queue order của engine, domain và <code>audio_service</code> đồng bộ.
- Map stream engine sang <code>PlaybackSnapshot</code>.
- Broadcast <code>mediaItem</code>, <code>queue</code> và <code>playbackState</code> cho hệ điều hành.
- Nhận command từ UI và system controls.
- Quản lý <code>ActivePlaybackContext</code>, <code>PendingLoadContext</code>, <code>RetryContext</code>, generation token và publication epoch.
- Quản lý lifecycle của subscriptions.

### 7.2. Mapping processing state

| just_audio | audio_service/domain |
|---|---|
| <code>idle</code> | <code>idle</code> |
| <code>loading</code> | <code>loading</code> |
| <code>buffering</code> | <code>buffering</code> |
| <code>ready</code> | <code>ready</code> |
| <code>completed</code> | <code>completed</code> |

### 7.3. Remote controls

System actions cần quảng bá:

- Play.
- Pause.
- Stop.
- Seek.
- Seek forward 10 giây.
- Seek backward 10 giây.
- Skip next.
- Skip previous.
- Repeat.
- Shuffle.
- Playback speed khi nền tảng hỗ trợ.

Không dùng Next/Previous để tua ±10 giây. Hai nhóm hành vi phải tách biệt:

~~~text
rewind / fastForward → ±10 giây
previous / next      → điều hướng queue
~~~

### 7.4. Chính sách command

- Mọi command không hợp lệ trả <code>PlayerCommandFailure</code> có typed code; boundary navigation hợp lệ là no-op, không phải failure.
- <code>play()</code>: nếu completed thì thực hiện Replay theo đúng thứ tự <code>seek(Duration.zero)</code> rồi <code>play()</code>.
- <code>pause()</code>: giữ media session và current item.
- <code>stop()</code>: mở publication barrier, dừng engine, reset option baseline, commit atomic idle/item null/queue rỗng, phát OS idle rồi đóng barrier. Nếu engine stop lỗi thì giữ session hiện tại và phát <code>stopFailed</code>; Stop lần hai sau thành công là no-op.
- <code>seek()</code>/<code>skipBy()</code>: khi không có current item trả <code>noCurrentItem</code>; khi duration chưa biết hoặc bằng 0 trả <code>seekUnavailableUnknownDuration</code>. UI đồng thời disable seek.
- <code>skipBy()</code>: tính position mới rồi gọi seek.
- <code>previous()</code>: nếu position &gt; 3 giây thì seek đầu track; nếu position ≤ 3 giây thì lùi theo effective queue; tại boundary là no-op.
- <code>next()</code>/<code>previous()</code>: repeat all được wrap; repeat off và one không wrap cho explicit navigation.
- <code>setSpeed()</code>: chỉ nhận preset UI <code>0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0</code> hoặc API value finite trong <code>[0.5, 2.0]</code>.
- <code>loadQueue()</code>: từ chối queue rỗng, index ngoài range, duplicate ID và item không hợp lệ; chỉ request mới nhất được commit atomic sau khi load thành công.
- <code>loadQueue()</code> khi có request đang chờ phải gọi handshake
  <code>PlaybackEngine.interruptLoad()</code> để giải phóng graph lane trước khi
  load generation mới; kết quả stale/interrupted của request cũ không được
  publish.
- <code>retry()</code>: dùng target cụ thể trong <code>RetryContext</code>, không suy từ snapshot đã thay đổi; thứ tự là load với autoplay false → xác nhận latest → clamp/seek → xác nhận latest → atomic commit → play nếu desired intent vẫn true.
- <code>stop()</code>, load mới và navigation mới làm mất hiệu lực retry context cũ.

## 8. PlayerCubit toàn app

<code>PlayerCubit</code> thuộc Application và được provide phía trên <code>MaterialApp</code>, nhưng không trực tiếp sở hữu audio engine. Cubit cũ trong Presentation chỉ tồn tại qua bridge tạm thời trong migration và phải bị xóa khi toàn bộ consumer đã chuyển xong.

Trách nhiệm:

- Subscribe <code>PlaybackGateway.snapshots</code>.
- Chuyển snapshot thành immutable <code>PlayerState</code>.
- Cung cấp command đơn giản cho UI.
- Giữ private pending desired-playing intent để hai lần Toggle liên tiếp vẫn suy ra đúng ý định khi snapshot engine chưa kịp quay về; giá trị này không được publish như playback state.
- Hủy subscription trong <code>close()</code>.

Các method dự kiến:

~~~text
open(item)
openQueue(items, initialIndex)
togglePlayback()
play()
pause()
stop()
seekTo(position)
skipBackward()
skipForward()
next()
previous()
setSpeed(speed)
cycleRepeatMode()
toggleShuffle()
retry()
~~~

Cubit không chứa timer tự tăng position và không optimistic emit <code>playing</code>. Position và trạng thái chính thức luôn đến từ audio engine.

## 9. Tách navigation khỏi playback state

<code>PlayerPresentation.hidden/mini/expanded</code> hiện đang trộn navigation state với playback state tại [player_cubit.dart](../lib/features/player/presentation/cubit/player_cubit.dart).

Phương án:

- Loại <code>PlayerPresentation</code> khỏi <code>PlayerState</code>.
- <code>currentItem == null</code>: không hiện mini player.
- <code>currentItem != null</code>: hiện mini player.
- Expanded player được quản lý bởi Navigator/route.
- Push hoặc pop expanded route không làm thay đổi playback.
- Không gọi pause/stop khi dispose expanded screen.

Điều này loại bỏ trường hợp route bị đóng rồi <code>minimize()</code> vô tình làm sống lại mini player sau khi track đã stop.

## 10. Migration UI

### 10.1. Initial state

State mô phỏng hiện tại đang khởi tạo player ở 45% và ở trạng thái playing tại [player_cubit.dart](../lib/features/player/presentation/cubit/player_cubit.dart).

Thay bằng:

~~~text
currentItem = null
queue = []
processingState = idle
playing = false
position = 0
bufferedPosition = 0
duration = 0
speed = 1.0
repeatMode = off
shuffleEnabled = false
~~~

### 10.2. Metadata

Loại metadata hard-code khỏi:

- [mini_player.dart](../lib/features/player/presentation/widgets/mini_player.dart)
- [expanded_player_screen.dart](../lib/features/player/presentation/expanded_player_screen.dart)
- [player_artwork.dart](../lib/features/player/presentation/widgets/player_artwork.dart)

UI lấy title, artist, duration và artwork từ <code>state.currentItem</code>.

### 10.3. Seek bar

Loại duration cố định 159 giây và phép seek theo tỷ lệ tại [player_control_dock.dart](../lib/features/player/presentation/widgets/player_control_dock.dart).

Luồng slider:

1. Khi bắt đầu drag, tạo preview position cục bộ.
2. <code>onChanged</code> chỉ cập nhật preview UI.
3. <code>onChangeEnd</code> gọi Cubit một lần với <code>Duration</code> thật.
4. Khi không drag, slider theo position từ Cubit.

Không gọi platform seek liên tục trên mỗi pixel kéo.

### 10.4. Giới hạn rebuild

Dùng <code>BlocSelector</code> hoặc <code>buildWhen</code> theo từng lát state:

- Metadata/artwork.
- Playing/buffering/completed.
- Position/duration/buffered position.
- Speed/repeat/shuffle.
- Queue navigation.

Position stream target 200 ms nhưng không được rebuild toàn bộ expanded player.

## 11. Bootstrap ứng dụng

[main.dart](../lib/main.dart) chuyển thành async:

~~~dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final handler = await AudioService.init(
    builder: AppAudioHandler.production,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.vilisten.playback',
      androidNotificationChannelName: 'Đang phát',
      androidStopForegroundOnPause: false,
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
    ),
  );

  final session = await AudioSession.instance;
  await session.configure(AudioSessionConfiguration.speech());

  final PlaybackGateway gateway = UiPlaybackGatewayAdapter(handler);

  runApp(
    BlocProvider(
      create: (_) => PlayerCubit(gateway),
      child: const MyApp(),
    ),
  );
}
~~~

Đoạn trên mô tả happy path. Composition root thật phải fail-fast ở dev/test; ở production, nếu bootstrap plugin thất bại thì inject <code>UnavailablePlaybackGateway</code>, không tạo engine thứ hai và không giả lập playback.

<code>AudioSessionConfiguration.speech()</code> phù hợp nội dung học ngoại ngữ, podcast và spoken audio. <code>androidStopForegroundOnPause: false</code> là policy đã chốt để Pause không phải restart foreground service từ background trên Android 12+.

Handler phải được khởi tạo đúng một lần trước <code>runApp</code>. Không tạo <code>AudioPlayer</code> trong widget hoặc route.

## 12. Cấu hình nền tảng

### 12.1. Android

Hiện trạng: [AndroidManifest.xml](../android/app/src/main/AndroidManifest.xml) chưa khai báo media service và release manifest chưa có quyền Internet.

Thêm:

~~~xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
~~~

Khai báo:

- <code>AudioService</code> với <code>foregroundServiceType="mediaPlayback"</code>.
- <code>MediaButtonReceiver</code>.
- <code>MainActivity</code> kế thừa <code>AudioServiceActivity</code> hoặc <code>AudioServiceFragmentActivity</code> nếu ứng dụng cần FragmentActivity.
- Notification channel ID ổn định, không thay đổi giữa các phiên bản.

Với URL HTTPS thông thường không cần bật cleartext toàn ứng dụng. Nếu sau này dùng header proxy, caching source hoặc HTTP, chỉ mở cleartext cho localhost qua network security config.

Chính sách đã chốt cho Player v1:

- Giữ media session khi pause để resume từ lock screen ổn định.
- Chỉ explicit Stop thành công mới clear session và gỡ notification/Now Playing.
- Hết queue với repeat off giữ metadata/card ở <code>completed × playing=false</code> để hỗ trợ Replay; không tự chuyển thành Stop.
- Swipe app khỏi recent tasks không được quy đổi ngầm thành Stop; hành vi theo lifecycle của <code>audio_service</code> và phải được kiểm thử.
- Không tự restore queue/playback sau process death trong release này.
- Kiểm thử riêng Android 12+ về foreground-service restart.

Tài liệu: [audio_service Android setup](https://pub.dev/packages/audio_service#android-setup).

### 12.2. iOS

Hiện trạng: [Info.plist](../ios/Runner/Info.plist) chưa có background audio.

Thêm:

~~~xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
~~~

Đồng thời bật capability:

~~~text
Signing & Capabilities
→ Background Modes
→ Audio, AirPlay, and Picture in Picture
~~~

Quy tắc:

- Ưu tiên audio/artwork URL HTTPS.
- Không bật arbitrary ATS loads nếu không thực sự cần.
- Để <code>just_audio</code> làm chủ interruption handling; không tạo thêm một lớp audio-focus cạnh tranh.

Kết quả cần đạt:

- Now Playing metadata.
- Lock Screen player.
- Control Center.
- Headset/Bluetooth commands.
- Background playback.

Tài liệu: [Apple MPNowPlayingInfoCenter](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter).

### 12.3. Web

Không cần native manifest. <code>audio_service_web</code> dùng Media Session API.

Yêu cầu:

- Play lần đầu phải đến trực tiếp từ click/tap của người dùng.
- Feature-detect Media Session.
- Audio server phải hỗ trợ CORS và range request phù hợp.
- Artwork phải truy cập được bằng HTTPS.
- Nếu trình duyệt không hỗ trợ Media Session, player trong ứng dụng vẫn phải hoạt động.

Không cam kết:

- Tiếp tục phát sau khi đóng tab.
- Browser không suspend background tab.
- Mọi browser/OS đều hiển thị cùng một tập control.

Tài liệu:

- [Media Session API](https://developer.mozilla.org/en-US/docs/Web/API/MediaSession)
- [Autoplay policy](https://developer.mozilla.org/en-US/docs/Web/Media/Guides/Autoplay)

### 12.4. macOS

Hiện trạng:

- [DebugProfile.entitlements](../macos/Runner/DebugProfile.entitlements) thiếu outbound network client.
- [Release.entitlements](../macos/Runner/Release.entitlements) thiếu outbound network client.

Thêm vào cả hai:

~~~xml
<key>com.apple.security.network.client</key>
<true/>
~~~

Target macOS 10.15 hiện tại đã cao hơn mức tối thiểu của <code>audio_service</code>.

Kết quả cần đạt:

- Now Playing/Control Center.
- Keyboard media keys.
- Playback tiếp tục khi minimize.

Ứng dụng hiện terminate khi đóng cửa sổ cuối. Giai đoạn đầu giữ hành vi này. Nếu cần “đóng cửa sổ nhưng vẫn phát”, triển khai close-to-tray/menu bar app thành hạng mục riêng.

## 13. Lifecycle policy

| Tình huống | Hành vi |
|---|---|
| Mở/đóng expanded player | Không ảnh hưởng playback |
| Android/iOS background | Tiếp tục phát |
| Android/iOS khóa màn hình | Tiếp tục phát và nhận remote commands |
| Web chuyển tab | Cố gắng tiếp tục, phụ thuộc browser |
| Web đóng tab | Kết thúc |
| macOS minimize | Tiếp tục phát |
| macOS đóng cửa sổ cuối | Kết thúc process trong scope hiện tại |
| Pause | Giữ current item và system controls |
| Stop thành công | Dừng, reset baseline, clear queue/item và gỡ system controls |
| Stop engine lỗi | Giữ active session/snapshot, phát typed failure <code>stopFailed</code> |
| Hết queue, repeat off | Chuẩn hóa một lần thành <code>completed × playing=false</code>, giữ metadata/card và cho phép Replay |

Không tự pause chỉ vì Flutter nhận <code>AppLifecycleState.paused</code>.

## 14. Error và interruption

### 14.1. Error model

~~~text
PlayerFailure
- code
- message
- isRecoverable
- itemId?

PlayerCommandFailure
- code
- message
- command
~~~

Các nhóm lỗi tối thiểu:

- Network/load failure.
- Source không tồn tại.
- Format không hỗ trợ.
- Audio output failure.
- Command validation failure như <code>emptyQueue</code>, <code>initialIndexOutOfRange</code>, <code>duplicateItemId</code>, <code>unsupportedUriScheme</code>, <code>invalidExtras</code>, <code>noCurrentItem</code>, <code>seekUnavailableUnknownDuration</code>, <code>invalidSpeed</code> và <code>retryUnavailable</code>.

Khi error:

- Không giữ UI ở trạng thái playing giả.
- Runtime failure của active item giữ active context, chuyển processing state sang error với <code>playing=false</code> và phát OS error code tương ứng; không tự clear media item. Riêng Stop failure tuân PLR-004 và giữ engine-confirmed playing state gần nhất.
- Initial-load failure không publish metadata/queue pending; replace-load A→B lỗi phải giữ nguyên A.
- Hiển thị Retry nếu recoverable.
- Retry phải dùng <code>RetryContext</code> bất biến chứa target item/queue/index, resume position và desired-playing intent. Không có context thì trả <code>retryUnavailable</code>.
- Retry thực hiện: load target với autoplay false → kiểm tra generation mới nhất → clamp/seek resume position → kiểm tra generation mới nhất → commit atomic → chỉ play nếu desired intent vẫn true. Pause trong lúc retry cập nhật desired intent thành false và phải thắng.
- OS nhận <code>PlaybackState.errorCode/errorMessage</code> theo bảng code canonical trong ADR; UI và log dùng cùng một mã domain.

### 14.2. Interruption policy

Với spoken audio:

- <code>just_audio</code> là chủ sở hữu duy nhất của interruption/noisy handling; application chỉ quan sát stream để cập nhật snapshot và log.
- Cuộc gọi/Siri/audio focus loss: engine pause theo policy plugin.
- Headphone unplug/noisy event: pause và không auto-resume.
- Interruption tạm thời kết thúc: chỉ engine được auto-resume nếu trước interruption đang playing và OS cho phép.
- Application/handler không gọi thêm <code>pause()</code>/<code>play()</code> khi quan sát cùng event.

## 15. Kế hoạch triển khai

### PR 1 — Core playback

- Thêm dependencies.
- Tạo <code>PlayerItem</code>, <code>PlaybackSnapshot</code>, <code>PlayerCommandFailure</code> và <code>PlaybackGateway</code>.
- Implement <code>PlaybackEngine</code>, <code>JustAudioPlaybackEngine</code>, <code>AppAudioHandler</code>, <code>UiPlaybackCommandTarget</code> và <code>UiPlaybackGatewayAdapter</code>.
- Map processing state.
- Implement queue, play, pause, stop và seek.
- Broadcast media item, queue và playback state.

Điều kiện hoàn thành:

- Phát được một file audio local/HTTPS.
- UI test có thể dùng fake gateway.
- System session chưa cần hoàn thiện toàn bộ nhưng state mapping phải đúng.

### PR 2 — Full commands và Cubit

- Implement next/previous.
- Tua ±10 giây.
- Speed.
- Repeat.
- Shuffle.
- Completion/replay.
- Error mapping.
- First-class retry và retry context.
- Chuyển <code>PlayerCubit</code> sang snapshot thật.
- Hủy subscriptions đúng cách.

Điều kiện hoàn thành:

- UI command không tự emit playback state giả.
- Command từ handler và UI cùng tác động lên một engine.

### PR 3 — UI migration

- Initial idle state.
- Mini player chỉ hiện khi có current item.
- Metadata/artwork/duration lấy từ state.
- Slider dùng Duration và local drag preview.
- Tách navigation state khỏi Cubit.
- Giữ nguyên animation, Hero và gesture hiện hữu.
- Dùng selector để giới hạn rebuild.

Điều kiện hoàn thành:

- Mini và expanded luôn đồng bộ.
- Mở/đóng expanded không làm gián đoạn audio.

### PR 4 — Platform integration

- Android manifest, activity, service, receiver và notification.
- iOS background mode.
- macOS network entitlement.
- Web Media Session/autoplay fallback.
- Artwork thật cho system controls.

Điều kiện hoàn thành:

- Play/pause từ system controls phản ánh lại UI.
- Metadata và artwork hiển thị đúng.

### PR 5 — Reliability

- Phone call/audio focus.
- Headphone unplug.
- Rapid play/pause.
- Rapid track switching.
- Buffering.
- Network failure/retry.
- Queue completion.
- Stop publication barrier, failure retention và idempotence.
- Race load/replace/retry bằng generation token.
- Kiểm tra memory và subscription leak.

### PR 6 — QA thiết bị thật

- Android API 24, 31, 33 và 36.
- iPhone/iPad thật.
- Chrome, Edge và Safari.
- macOS Control Center và keyboard media keys.

## 16. Kế hoạch kiểm thử

### 16.1. Unit test PlayerCubit

Dùng <code>FakePlaybackGateway</code> kiểm tra:

- Play/pause delegate đúng một lần.
- Seek truyền đúng Duration.
- Skip ±10 giây clamp đúng.
- Next/previous theo queue boundary.
- Speed/repeat/shuffle.
- Hai lần Toggle nhanh dùng private desired intent nhưng không optimistic emit.
- Retry delegate đúng một lần và <code>retryUnavailable</code> được surface đúng.
- Snapshot cập nhật state.
- Subscription bị hủy khi Cubit close.
- Cubit không optimistic flip trạng thái engine.

### 16.2. Pure mapping tests

Kiểm tra:

- Mapping processing state.
- Mapping repeat/shuffle.
- Chọn controls theo queue boundary.
- PlayerItem sang MediaItem.
- PlaybackState có đúng position, buffered position, speed và queue index.
- Effective queue order của domain và OS luôn trùng nhau khi shuffle.
- Error mapping và bảng OS error code.
- Load generation, retry target, seek-before-commit và Stop publication epoch.

### 16.3. Widget tests

Chuyển [widget_test.dart](../test/widget_test.dart) sang fake gateway.

Bổ sung:

- Idle không hiện mini player.
- Load item làm xuất hiện mini player.
- Loading/buffering UI.
- Play/pause từ snapshot.
- Seek slider.
- Metadata thay đổi khi next.
- Completed hiển thị replay.
- Error hiển thị retry.
- Seek bị disable khi duration chưa biết hoặc bằng 0.
- Expanded route không thay đổi playback.

### 16.4. Integration/manual tests

Mỗi nền tảng phải kiểm tra:

1. Play từ UI.
2. Chuyển app sang background/minimize.
3. Play/pause từ system controls.
4. Seek.
5. Tua ±10 giây.
6. Next/previous.
7. Metadata, artwork và duration.
8. Buffering.
9. Track completion.
10. Stop làm biến mất system card.
11. Quay lại app, UI vẫn đồng bộ.
12. Repeat off/one/all tại boundary và khi track tự kết thúc.
13. Shuffle vẫn hiển thị cùng effective queue order giữa UI và OS.
14. Retry initial-load, runtime và replace-load failure đúng target/position.

Mobile bổ sung:

- Khóa/mở khóa màn hình.
- Cuộc gọi hoặc audio focus loss.
- Cắm/rút tai nghe.
- Bluetooth media buttons.
- Swipe app khỏi recent tasks theo policy Android.
- Pause dài trên Android 12+ rồi resume từ system controls mà không cần foreground-service restart lỗi.

## 17. Tiêu chí nghiệm thu

- Chỉ có một audio stream và một media session.
- Mini player, expanded player và system controls luôn cùng current item.
- Play/pause và metadata/queue thay đổi phản ánh tức thì theo engine event; UI position publish theo cadence 200 ms.
- OS position-only update không dày hơn 1 giây, nhưng seek/track/error/completion/command vẫn publish ngay.
- Position UI và system controls không lệch quá 1 giây sau seek.
- Không có trạng thái playing giả khi engine error.
- Buffering không làm nút Play/Pause nhấp nháy sai.
- Mở/đóng expanded player liên tục không tạo thêm player hoặc subscription.
- Android/iOS khóa màn hình 30 phút vẫn phát ổn định.
- Cuộc gọi và headphone unplug xử lý đúng policy.
- Stop gỡ notification/Now Playing.
- Stop lỗi không giả lập idle và event muộn trước Stop không làm sống lại session đã clear.
- Completed cuối queue luôn là <code>playing=false</code>; Replay luôn seek về 0 trước play.
- Retry không bao giờ commit nhầm pending target hoặc tự phát lại sau khi người dùng đã Pause.
- Web không hỗ trợ Media Session vẫn phát bằng UI thông thường.
- Tất cả unit/widget test pass.
- <code>flutter analyze</code> không có lỗi.

## 18. Rủi ro và biện pháp

| Rủi ro | Biện pháp |
|---|---|
| Cubit và engine trở thành hai nguồn sự thật | Cubit chỉ nhận snapshot qua Gateway adapter; pending desired intent là private và không publish |
| UI seek gọi platform quá dày | Local preview, commit ở onChangeEnd |
| Queue của engine và OS lệch nhau | Handler publish cùng effective queue order cho domain và OS |
| Remote command không cập nhật UI | UI và OS hội tụ vào cùng handler operation; UI nhận engine state qua adapter |
| Background resume lỗi Android mới | Test API 31–36, chốt foreground policy rõ ràng |
| Web autoplay bị chặn | Play đầu tiên luôn từ user gesture |
| Web Media Session không tương thích | Feature detection và graceful fallback |
| Artwork không hiện | HTTPS/local cache hợp lệ và test release |
| Interruption bị xử lý hai lần | <code>just_audio</code> sở hữu handling; application chỉ quan sát |
| Event muộn làm sống lại session sau Stop | Publication barrier và epoch chặn mọi event cũ |
| Retry commit nhầm item | RetryContext bất biến và generation check trước seek/commit |
| Route dispose làm dừng audio | Handler/engine sống ngoài widget lifecycle |

## 19. Definition of Done

Một hạng mục player chỉ được xem là hoàn tất khi:

- Code core đã implement.
- Unit/widget tests tương ứng đã có.
- Platform release configuration đã được kiểm tra.
- Ít nhất một thiết bị thật của platform đã chạy qua checklist.
- Không còn metadata hoặc duration hard-code trong player UI.
- Không còn timer mô phỏng position.
- Không còn playback state được emit trực tiếp từ thao tác UI.
- Không có production class vừa implement <code>PlaybackGateway</code> vừa extend <code>BaseAudioHandler</code>.
- Có đúng một <code>JustAudioPlaybackEngine</code>/<code>AudioPlayer</code> trong composition root.
- Các contract PLR-001–009 và PLR-014–016 có test tương ứng theo task ledger.
- Tài liệu này được cập nhật nếu architecture hoặc policy thay đổi.
