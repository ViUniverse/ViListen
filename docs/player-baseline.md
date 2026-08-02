# PLR-010 — Baseline hiện trạng

> Ngày ghi nhận: 2026-08-02
> Revision: `e5ecf8bbc822f137e1f2c9926913f9b5879971a0`
> Phạm vi release theo kế hoạch: Android, iOS, Web và macOS

Tài liệu này là evidence baseline trước khi bắt đầu task code của Player. Không
fix lỗi ngoài phạm vi Player trong baseline này.

## Files đã kiểm tra

- `pubspec.yaml`, `lib/main.dart`, `test/widget_test.dart`.
- Toàn bộ `lib/features/player/presentation/**`:
  `cubit/player_cubit.dart`, `expanded_player_screen.dart`,
  `widgets/mini_player.dart`, `widgets/player_artwork.dart`,
  `widgets/player_control_dock.dart`, `widgets/player_host.dart`.
- Platform manifests/config liên quan: Android manifests, `ios/Runner/Info.plist`,
  `ios/Runner/AppDelegate.swift`, `ios/Runner/SceneDelegate.swift`,
  `macos/Runner/Info.plist`, hai macOS entitlements và `web/manifest.json`.
  Windows/Linux nằm ngoài phạm vi release đã chốt; Windows manifest cũng được
  kiểm tra và không có cấu hình audio.

## Lệnh baseline

Các lệnh được chạy trước khi tạo artifact này và trước khi thay đổi source/config:

```text
flutter test
flutter analyze
```

### `flutter test` — FAIL baseline

Kết quả: 2 test pass, 1 test fail.

Test fail:

```text
test/widget_test.dart:11
mini player controls shared playback state
```

Lỗi:

```text
Exception: Asset 'shaders/ink_sparkle.frag' manifest could not be decoded:
INVALID_ARGUMENT: Unsupported runtime stages format version. Expected 2, got 1.
```

Failure xảy ra tại Flutter shader decoder khi test widget decode shader; chưa đủ
bằng chứng để kết luận root cause thuộc Flutter runtime. Baseline không thay đổi
shader, test hoặc code để sửa lỗi này.

Hai test pass:

```text
opens expanded player and closes back to mini player
swipes the expanded player down to return to mini player
```

### `flutter analyze` — NON-ZERO (exit 1), không có error/warning, có 1 info

```text
lib/features/player/presentation/expanded_player_screen.dart:407:13
'axisAlignment' is deprecated and shouldn't be used. Use alignment instead.
```

Không có error hoặc warning từ analyzer. Deprecation này được ghi nhận, không
được sửa trong PLR-010.

## Trạng thái Player hiện tại

- App tạo một `PlayerCubit` trong `lib/main.dart:6-7`.
- State khởi tạo trong `lib/features/player/presentation/cubit/player_cubit.dart:38-43`:
  - presentation: `PlayerPresentation.mini`;
  - progress: `.45` (45%);
  - isPlaying: `true`.
- Player chưa có field duration trong state. Duration đang được mô phỏng ở
  presentation bằng `159` giây tại
  `lib/features/player/presentation/widgets/player_control_dock.dart:61,63,86,123,146`.
- Mini player hiển thị `2m 39s` tại
  `lib/features/player/presentation/widgets/mini_player.dart:70-71`.
- Expanded player cũng hiển thị `2m 39s` tại
  `lib/features/player/presentation/expanded_player_screen.dart:294-296`.

## Platform/config baseline

- `pubspec.yaml`: chưa có `just_audio`, `audio_service` hoặc `audio_session`; app
  chỉ có `flutter_bloc` và các dependency scaffold.
- Android manifests: chỉ có Flutter embedding và INTERNET cho debug/profile;
  chưa có media playback service hoặc notification/audio-specific declaration.
- iOS: `Info.plist` chưa có `UIBackgroundModes`; `AppDelegate.swift` chỉ đăng ký
  plugin mặc định.
- macOS: entitlements chỉ có app sandbox (debug thêm JIT và network server);
  chưa có cấu hình audio-specific.
- Web: `web/manifest.json` chỉ là manifest scaffold; chưa có cấu hình Media
  Session/audio playback riêng.

## Regression scope cho các task sau

Các thay đổi Player tiếp theo phải giữ hoặc cố ý thay thế, kèm test/evidence,
những hành vi baseline sau:

- App mở với mini player hiện diện.
- Initial progress là 45% và initial playback intent là playing.
- Metadata hiện tại là `The English We Speak: On their toes`, duration hiển thị
  là 159 giây.
- Mini/expanded player dùng chung thao tác play/pause và navigation UI hiện có.
- Lỗi shader test runtime và deprecation `axisAlignment` là known baseline issues;
  không được trộn fix ngoài Player vào PLR-010.

## Artifact/worktree note

Artifact duy nhất của PLR-010 là file này. Thay đổi có sẵn trước task tại
`docs/.obsidian/workspace.json` được giữ nguyên. `pubspec.lock` đã được trả về
trạng thái trước khi baseline command resolve transitive dependencies.
