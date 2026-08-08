# Kế hoạch task triển khai Player chi tiết

> Trạng thái: Kế hoạch thực thi, chưa phải trạng thái implementation<br>
> Ngày lập: 2026-07-26<br>
> Cập nhật contract: 2026-08-02<br>
> Phạm vi: Android, iOS, Web và macOS; chưa gồm Windows<br>
> Tài liệu nguồn:
>
> - [Player Architecture Decisions — normative](./player-architecture-decisions.md)
> - [Player Behavioral Diagrams](./player-behavioral-diagrams.md)
> - [Player Class Diagram](./player-class-diagram.md)
> - [Player Implementation Plan](./player-implementation-plan.md)

## 1. Mục tiêu của tài liệu

Tài liệu này chuyển thiết kế cấp kiến trúc thành các task đủ nhỏ để:

- Mỗi task code chỉ thay đổi một contract hoặc một nhóm hành vi có liên hệ chặt.
- Unit test/widget test được viết cùng task, ưu tiên test trước implementation.
- Task sau chỉ bắt đầu khi test và điều kiện hoàn thành của task phụ thuộc đã xanh.
- Cấu hình source-controlled được tách khỏi thao tác bắt buộc làm tay trong Xcode, thiết bị hoặc hệ thống ngoài.
- Có thể gom các task thành các PR nhỏ mà vẫn giữ ứng dụng build/test được.

Kế hoạch giữ các invariant:

```text
Một AppAudioHandler
+ Một JustAudioPlaybackEngine sở hữu một just_audio.AudioPlayer
+ Một PlayerCubit toàn ứng dụng
= Một nguồn sự thật cho UI và system media controls
```

```text
Command UI: UI → PlayerCubit → UiPlaybackGatewayAdapter → AppAudioHandler
Command OS: OS → BaseAudioHandler override → AppAudioHandler internal operation
Engine:     AppAudioHandler → PlaybackEngine → JustAudioPlaybackEngine → AudioPlayer
State:      Engine → AppAudioHandler → adapter/Cubit/UI + audio_service/OS
```

## 2. Quy ước nhãn

| Nhãn | Ý nghĩa |
|---|---|
| `[CODE]` | Code Dart/Flutter thông thường, được lưu trong source control |
| `[UNIT]` | Phải có unit test không cần plugin/platform thật |
| `[WIDGET]` | Phải có widget test |
| `[INTEGRATION]` | Cần plugin, platform channel, app build hoặc audio engine thật |
| `[NATIVE-CODE]` | Sửa file Android/iOS/macOS/Web trong source control; không nhất thiết thao tác GUI |
| `⚠️ [MANUAL:DECISION]` | Con người phải chốt policy/contract trước khi code task phụ thuộc |
| `⚠️ [MANUAL:XCODE-IOS]` | Bắt buộc thao tác hoặc xác nhận trực tiếp trong Xcode cho iOS |
| `⚠️ [MANUAL:XCODE-MACOS]` | Bắt buộc xác nhận trực tiếp trong Xcode/signing cho macOS |
| `⚠️ [MANUAL:EXTERNAL]` | Cần cấu hình/xác nhận CDN, server, certificate hoặc hệ thống ngoài repository |
| `⚠️ [MANUAL:DEVICE-QA]` | Bắt buộc kiểm tra trên thiết bị, OS control hoặc browser thật |

Các task `MANUAL` không được xem là hoàn thành chỉ vì unit test xanh.

## 3. Quy tắc thực thi và Definition of Done cho từng task

Với task có nhãn `[UNIT]` hoặc `[WIDGET]`, thực hiện theo vòng lặp:

1. Viết test mô tả contract và xác nhận test fail đúng lý do.
2. Viết lượng code nhỏ nhất để test pass.
3. Refactor nhưng không thay đổi contract.
4. Chạy test trực tiếp của task.
5. Chạy toàn bộ test của feature player bị ảnh hưởng.

Một task code chỉ được đánh dấu hoàn thành khi:

- Test mới của task pass.
- Test cũ liên quan pass.
- `dart format` không còn thay đổi.
- `flutter analyze` không có lỗi mới.
- Không import `just_audio`/`audio_service` vào Domain hoặc Presentation.
- Không tạo `AudioPlayer` ngoài `JustAudioPlaybackEngine` ở Infrastructure.
- Không thêm optimistic playback state vào Cubit/UI.
- Nếu task làm thay đổi contract đã chốt, ADR và bốn projection phải được cập nhật
  ngay trong cùng task; không chờ PLR-190.

Lệnh kiểm tra chuẩn:

```bash
dart format lib test
flutter analyze
flutter test test/features/player
```

Với task native/platform, chạy thêm build hoặc smoke test đúng nền tảng ở phase tương ứng.

## 4. Các contract đã khóa trước khi triển khai

PLR-001–009 và PLR-014–016 đã được Accepted v1 ngày 2026-08-02 trong
[Player Architecture Decisions](./player-architecture-decisions.md). ADR là
normative; các mô tả dưới đây là acceptance summary để nối quyết định với task và
test, không phải một nguồn policy độc lập.

PLR-010 vẫn phải ghi baseline source code trước khi bắt đầu task code. Baseline là
evidence triển khai, không mở lại các contract đã Accepted.

Mọi quyết định trong mục này phải được ghi ngay vào
`docs/player-architecture-decisions.md` theo mẫu:

```text
Decision ID / ngày / owner
Context
Decision
Alternatives rejected
Affected contracts/files
Test oracle
```

Không chờ đến cuối dự án mới cập nhật contract. Mọi thay đổi quyết định phải tăng
decision version và đồng bộ ADR cùng bốn projection trong cùng thay đổi.

### PLR-001 — Khóa policy input và giá trị biên ⚠️ `[MANUAL:DECISION]`

- Trạng thái: Accepted v1; document sync hoàn tất 2026-08-02.
- Contract:
  - Queue rỗng bị từ chối bằng validation failure; không gọi engine.
  - `initialIndex` âm hoặc ngoài queue bị từ chối; không tự clamp.
  - Duplicate `PlayerItem.id` là validation failure.
  - `PlaybackSnapshot.duration` dùng `Duration.zero` khi chưa biết.
  - Seek UI bị disable và Gateway trả `seekUnavailableUnknownDuration` khi duration chưa
    biết hoặc bằng zero; không gọi engine.
  - Skip ±10 giây dùng `const Duration(seconds: 10)`.
  - Previous dùng `const Duration(seconds: 3)`: `> 3s` về đầu;
    `<= 3s` mới điều hướng effective queue.
  - Speed UI: `0.5`, `0.75`, `1.0`, `1.25`, `1.5`, `1.75`, `2.0`;
    Gateway chỉ nhận finite value trong `[0.5, 2.0]`.
  - `extras` được defensive deep-copy/deep-compare và chỉ nhận `null`, `bool`,
    `int`, finite `double`, `String`, `Uri`, `Duration`, list hợp lệ hoặc
    `Map<String, Object?>` hợp lệ. Từ chối cycle, custom object, `Set`, key
    không phải String và số không finite.
  - `audioUri`: `https`/asset trên mọi platform, `file` chỉ native;
    `artUri`: `https` mọi platform, `file` chỉ native. Từ chối `http` và scheme
    khác trước engine call.
  - Invalid programmer input hoàn thành `Future` bằng typed command failure và
    không mutate snapshot; lỗi nguồn hợp lệ nhưng load thất bại mới đi vào
    `PlayerFailure`.
- Code completion còn lại:
  - Owner/file và test oracle theo ADR PLR-001.
  - Xóa magic number `10`, `3`, `159`/speed khỏi source tại
    PLR-041, PLR-104, PLR-110 và kiểm lại tại PLR-180; không phải code output
    của task quyết định này.

### PLR-002 — Khóa owner completion, repeat và auto-advance ⚠️ `[MANUAL:DECISION]`

- Phụ thuộc: PLR-001.
- Trạng thái: Accepted v1; document sync hoàn tất 2026-08-02.
- Contract:
  - Engine sequence/loop mode là owner của auto-advance và repeat.
  - Handler chỉ quan sát `currentIndexStream` để publish item mới.
  - Handler không tự seek item kế tiếp khi nhận completion.
  - Ở cuối queue/repeat off, handler phát đúng một lệnh `pause` để chuẩn hóa
    `completed × playing=false`, giữ item/card.
  - Replay luôn là `seek(Duration.zero)` rồi `play()`.
  - Manual next/previous vẫn đi qua một operation của handler.
- Test oracle:
  - Chuyển item tự động chỉ xảy ra một lần.
  - Repeat one/all không gọi thêm seek thủ công nếu engine đã xử lý.
  - Completion cuối repeat off chỉ chuẩn hóa Pause một lần.
  - Explicit navigation tuân PLR-014: repeat one không chặn; repeat all wrap;
    repeat off/one boundary no-op.

### PLR-003 — Khóa transaction Retry ⚠️ `[MANUAL:DECISION]`

- Phụ thuộc: PLR-001.
- Trạng thái: Accepted v1; document sync hoàn tất 2026-08-02.
- Contract:
  - Bổ sung `Future<void> retry()` vào `PlaybackGateway`.
  - Handler giữ immutable `RetryContext` gồm target queue/index, restore
    position, desired playing, failure generation và failure item ID.
  - Runtime failure nhắm active item; initial-load failure nhắm initial target;
    replace A→B failure vẫn giữ A outward nhưng Retry nhắm B.
  - Retry transaction: generation mới → load target với autoplay false → check
    latest → đọc duration/clamp/seek → check latest → atomic commit/publish →
    conditional Play đúng một lần nếu latest desired intent vẫn true.
  - Không publish target retry ở position zero trước khi seek/commit.
  - Pause trong retry đổi desired intent false và phải thắng; Play đổi true;
    Stop/load/navigation mới invalidate retry.
  - Thiếu recoverable current context trả `retryUnavailable`, không no-op.
  - Không retry vô hạn tự động.
- Test contract:
  - Recoverable current context mới cho retry; non-recoverable/no context không gọi engine.
  - Item mới thắng retry cũ.
  - Call order là load → seek → commit/publication → conditional Play.
  - Prior-playing restore rồi play; prior-paused restore nhưng không play.
  - Pause trong pending retry không auto-play sau commit.
  - Saved position vượt duration mới được clamp trước seek.

### PLR-004 — Khóa thứ tự Stop canonical ⚠️ `[MANUAL:DECISION]`

- Phụ thuộc: PLR-001.
- Trạng thái: Accepted v1; document sync hoàn tất 2026-08-02.
- Success contract:
  1. Mở stopping publication barrier; tăng epoch/generation và invalidate mọi
     load/retry/navigation/seek cũ.
  2. Serialize với command thay playback graph.
  3. Await engine Stop.
  4. Reset speed/repeat/shuffle về `1.0`/off/false.
  5. Atomic replace internal state thành canonical idle và clear mọi context.
  6. Publish `mediaItem=null`, queue rỗng, OS idle, rồi đúng một Domain idle.
  7. Đóng barrier; event epoch cũ không được publish; handler vẫn reusable.
- Failure/idempotence contract:
  - Nếu engine Stop lỗi, không publish idle giả; giữ active metadata/queue/card,
    expose non-recoverable `stopFailed`, route không pop.
  - Nếu option reset lỗi sau engine Stop, outward cleanup vẫn hoàn tất; load kế
    tiếp bắt buộc reapply baseline trước Ready.
  - Stop ở canonical idle không pending là no-op; Stop sau failure được retry.
  - Khi Stop trong expanded route: route tự pop đúng một lần nếu vẫn là route
    player trên cùng; không pop route khác và không gửi thêm Stop/Pause.
- Test contract:
  - Không outward-publish snapshot trung gian trong barrier.
  - Stop lặp lại sau thành công có engine/publication call count zero.
  - Late load không thể hồi sinh item sau Stop.
  - Stop failure giữ session và không pop route.
  - Có thể load queue mới sau Stop.

### PLR-005 — Khóa policy interruption và becoming-noisy ⚠️ `[MANUAL:DECISION]`

- Phụ thuộc: PLR-001.
- Trạng thái: Accepted v1; document sync hoàn tất 2026-08-02.
- Contract:
  - Dùng `AudioSessionConfiguration.speech()`.
  - Để `just_audio` là owner runtime interruption; app không tạo listener pause/resume thứ hai.
  - App chỉ passive-observe để projection/log; một event không tạo engine call
    trùng. User Pause luôn hủy quyền resume.
  - Becoming noisy Pause và không auto-resume khi output route quay lại.

### PLR-006 — Khóa test seam cho `AppAudioHandler` ⚠️ `[MANUAL:DECISION]`

- Phụ thuộc: PLR-001 đến PLR-005.
- Trạng thái: Accepted v1; document sync hoàn tất 2026-08-02.
- Mục tiêu:
  - Logic race, ordering, reducer và command policy phải unit test được mà không khởi tạo platform plugin.
- Kiến trúc phải chốt trong decision record:
  - Giữ `PlaybackGateway` là public application boundary.
  - Tạo `UiPlaybackGatewayAdapter implements PlaybackGateway` ở Infrastructure;
    Cubit nhận adapter này, không nhận trực tiếp handler.
  - Tạo internal `PlaybackEngine` port tại
    `lib/features/player/infrastructure/engine/playback_engine.dart`.
  - Tạo production adapter `JustAudioPlaybackEngine` tại
    `lib/features/player/infrastructure/engine/just_audio_playback_engine.dart`;
    adapter này sở hữu đúng một `AudioPlayer`.
  - `AppAudioHandler.production()` tạo đúng một production adapter; test
    constructor nhận `PlaybackEngine` fake.
  - Tạo `PlayerClock`/position-emission policy injectable để test cadence không
    dùng wall clock.
  - Quan sát publication qua các stream `mediaItem`, `queue`, `playbackState`
    của handler; thêm recorder test, không tạo publisher global thứ hai.
  - Tạo `FakePlaybackEngine`, controllable load completer, fake clock và
    call-order recorder dưới `test/features/player/support/`.
  - Tách queue/seek/speed validators, snapshot reducer, mapper,
    generation guard, publication diff và command coordinator thành pure
    collaborators.
  - Port/adapter không được lộ lên Application/Presentation.
  - Không mock `AudioPlayer` xuyên toàn ứng dụng.
- Hoàn thành khi:
  - Exact interface, constructor/factory, files, fake capabilities và test
    oracles được duyệt trong decision record.
  - Class diagram có đúng ba ranh giới Adapter → internal target → engine port.
  - Code/fake/unit tests được triển khai tại PLR-048; production adapter được
    triển khai tại PLR-060 và integration proof với audio fixture tại PLR-141.

### PLR-007 — Khóa bootstrap, OS error và Android service policy ⚠️ `[MANUAL:DECISION]`

- Trạng thái: Accepted v1; document sync hoàn tất 2026-08-02.
- Contract:
  - Development/test bootstrap failure fail-fast với original stack; production
    inject `UnavailablePlaybackGateway` không engine, phát
    `bootstrapUnavailable`, mọi command trả `commandUnavailable`.
  - Tuyệt đối không tạo handler/player thứ hai và không retry bootstrap ngầm.
  - OS error dùng `AudioProcessingState.error`, `playing=false`, sanitized
    message và stable code: network/load `1001`, source not found `1002`,
    unsupported format `1003`, audio output `1004`, stop failed `1005`, unknown
    engine `1099`, bootstrap unavailable `1100`.
  - Pause giữ current item/system card.
  - Set explicit `androidStopForegroundOnPause=false`; explicit Stop mới gỡ card.
  - Swipe recent tasks không tự gửi Stop; v1 không auto-restore/autoplay sau
    process death và bootstrap mới bắt đầu canonical idle.

### PLR-008 — Khóa command-validity và rapid-intent matrix ⚠️ `[MANUAL:DECISION]`

- Phụ thuộc: PLR-001, PLR-002.
- Trạng thái: Accepted v1; document sync hoàn tất 2026-08-02.
- Matrix normative nằm trong ADR PLR-008:

```text
Processing state × command → execute | idempotent no-op | typed failure
```

- Bao phủ:
  - Play/Pause khi không có item.
  - Next/Previous khi queue rỗng hoặc boundary.
  - Speed/repeat/shuffle ở idle/loading/error.
  - Seek khi duration unknown.
  - Hai Play, hai Pause và rapid Toggle trước engine confirmation.
- Rapid intent contract:
  - Play/Pause trực tiếp là idempotent theo desired intent.
  - Handler coordinator serialize intent và coalesce command trùng.
  - Cubit giữ private `_pendingDesiredPlaying`: Toggle đảo pending intent nếu có,
    nếu không thì đảo confirmed snapshot; không expose vào state/đổi icon
    optimistic. Snapshot xác nhận hoặc command failure reconcile/clear intent.
  - Boundary Next/Previous trên queue hợp lệ là no-op; empty/no committed queue
    và command invalid trả typed failure theo matrix.
- Test oracle phải ghi số engine call và final confirmed state cho từng case.

### PLR-009 — Khóa active/pending load và replace-failure semantics ⚠️ `[MANUAL:DECISION]`

- Phụ thuộc: PLR-001, PLR-003.
- Trạng thái: Accepted v1; document sync hoàn tất 2026-08-02.
- Hai context bắt buộc:
  - Active queue/item đã commit.
  - Pending load request chưa được phép publish.
- Contract:
  - Replace A → B đang loading vẫn giữ A làm active/system metadata cho đến khi B
    latest-ready; pending B chỉ xuất hiện qua loading indicator/context nội bộ.
  - B ready thì commit atomic queue/item B.
  - B fail thì error mô tả pending B, nhưng không publish metadata B như item đã
    phát; Retry nhắm B.
  - Initial load fail không có active item: item/queue/index vẫn empty/null,
    mini và system metadata không xuất hiện.
  - Stale failure không thay active hoặc pending context mới.
- Test:
  - Initial failure, replace failure, retry pending target, stale failure và Stop
    trong pending load.

### PLR-014 — Khóa queue/shuffle/manual navigation semantics ⚠️ `[MANUAL:DECISION]`

- Phụ thuộc: PLR-001, PLR-002.
- Trạng thái: Accepted v1; document sync hoàn tất 2026-08-02.
- Contract:
  - Một effective playback order được handler publish nhất quán cho Domain và OS
    khi shuffle bật; current index luôn index trong order đang publish.
  - Handler giữ logical queue nội bộ; khi shuffle off effective = logical, khi on
    lấy engine-confirmed effective sequence.
  - Snapshot queue, OS queue, currentIndex/queueIndex, derived boundary và manual
    navigation đều dùng effective order.
  - Toggle shuffle giữ current item, recompute index và publish queue change.
  - Explicit Next/Previous bỏ qua repeat one; repeat all wrap; repeat off/one tại
    boundary no-op. Previous áp dụng ngưỡng PLR-001 trước navigation.
  - Mọi thay đổi order là queue publication, không phải position publication.
- Test oracle:
  - Shuffle on/off, current item giữ ổn định, next/previous và queueIndex đồng bộ.

### PLR-015 — Khóa OS timeline cadence và logging provenance ⚠️ `[MANUAL:DECISION]`

- Phụ thuộc: PLR-007, PLR-008.
- Trạng thái: Accepted v1; document sync hoàn tất 2026-08-02.
- Contract:
  - UI position cadence mục tiêu 200 ms.
  - OS position-only resync mỗi 1 giây; lifecycle/load/item/play/pause/seek/speed/
    repeat/shuffle/buffering/completed/error/Stop publish ngay.
  - N position ticks không tạo N platform publications.
  - Position-only event không republish metadata/queue; clock injectable.
  - `CommandSource` chỉ gồm `ui`, `systemRemote`, `interruption`.
  - `UiPlaybackGatewayAdapter` gọi internal handler operation với source `ui`.
  - BaseAudioHandler overrides gọi cùng internal operation với source
    `systemRemote`; chỉ dùng
    lock-screen/headset/notification/control-center cụ thể nếu platform callback
    thực sự cung cấp provenance.
  - `AppAudioHandler` không đồng thời dùng cùng một zero-argument method làm cả
    UI Gateway và OS callback, vì như vậy không thể biết caller.
  - Internal operations nhận `CommandSource`; UI adapter và OS override cùng gọi
    operation đó.
  - Cập nhật class diagram ngay: UI adapter implement Gateway; handler vẫn là
    owner engine/media session và expose snapshot/internal command API.

### PLR-016 — Khóa placement và migration cutover build-green ⚠️ `[MANUAL:DECISION]`

- Trạng thái: Accepted v1; document sync hoàn tất 2026-08-02.
- Contract:
  - Target `PlayerState` và `PlayerCubit` đặt tại
    `lib/features/player/application/` để đúng layer diagram.
  - Legacy class hiện tại được rename `LegacyPlayerCubit/LegacyPlayerState`
    nhưng giữ behavior trong thời gian migration.
  - Core/Cubit mới được phát triển song song và test độc lập.
  - Sau bootstrap, app tạm cung cấp cả legacy Cubit và target Cubit; không có
    player thứ hai vì legacy Cubit chỉ là state mô phỏng.
  - Migrate widget từng lát sang target Cubit.
  - Xóa legacy provider/type/API trong một task rõ trước platform/release QA.
- Guard:
  - Mọi task/commit vẫn compile/test.
  - Dual-provider bridge không được merge vào release cuối.

## 5. Phase 1 — Baseline, dependency và test foundation

### PLR-010 — Ghi baseline hiện trạng `[CODE]`

- Phụ thuộc: Không. Đây là task đầu tiên của toàn kế hoạch.
- Files kiểm tra:
  - `pubspec.yaml`
  - `lib/main.dart`
  - `lib/features/player/presentation/**`
  - `test/widget_test.dart`
  - Platform manifests/entitlements.
- Thực hiện:
  - Chạy test/analyze hiện tại trước khi đổi code.
  - Ghi riêng lỗi baseline nếu có; không trộn fix ngoài player vào PR.
  - Xác nhận hiện tại player đang khởi tạo mini, progress 45%, playing true và duration 159 giây.
- Hoàn thành khi:
  - Có log baseline trong PR description/CI và phạm vi regression rõ.
  - Chưa có source/config nào bị thay đổi ngoài artifact baseline.

### PLR-011 — Thêm runtime dependencies `[CODE]`

- Phụ thuộc: PLR-001 đến PLR-009, PLR-014 đến PLR-016.
- File:
  - `pubspec.yaml`
  - `pubspec.lock`
- Thực hiện:
  - Thêm đúng phiên bản đã chốt trong tài liệu nguồn:
    - `just_audio: ^0.10.6`
    - `audio_service: ^0.18.19`
    - `audio_session: ^0.2.4`
  - Không thêm `just_audio_background`.
  - Chạy `flutter pub get`.
  - Kiểm tra minimum platform versions và generated plugin registration.
- Hoàn thành khi:
  - Dependency resolution thành công trên repository sạch.
  - `pubspec.lock` được commit nếu project đang commit lockfile.

### PLR-012 — Tạo integration-test harness `[CODE]` `[INTEGRATION]`

- Phụ thuộc: PLR-011.
- Files:
  - `pubspec.yaml`
  - `integration_test/player_local_smoke_test.dart`
  - `test_driver/integration_test.dart` cho browser/`flutter drive` nếu Flutter
    toolchain đã chốt yêu cầu driver.
- Thực hiện:
  - Thêm:

```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
```

  - Khởi tạo `IntegrationTestWidgetsFlutterBinding`.
  - Tạo entrypoint smoke test có thể chạy trên device thật.
  - Ghi lệnh runner theo Android/iOS/macOS/Web trong README comment của test.
- Hoàn thành khi:
  - Một integration test rỗng/sanity chạy được trên ít nhất một target local.
  - `flutter test` unit/widget vẫn không tự khởi tạo plugin integration.

### PLR-013 — Tạo audio fixture deterministic cho integration `[CODE]` `[INTEGRATION]`

- Phụ thuộc: PLR-012.
- Files:
  - `assets/test_audio/player_fixture_2s.wav`
  - `pubspec.yaml`
  - `pubspec.lock` nếu bổ sung test dependency trực tiếp
  - `test/player_fixture_asset_test.dart`
  - `integration_test/player_local_smoke_test.dart`
- Thực hiện:
  - Dùng WAV PCM 2 giây được tạo trong project, không có vấn đề bản quyền.
  - Ghi provenance synthetic tone, generator formula,
    sample rate/channels/duration/checksum trong test comment.
  - Đăng ký đúng asset path trong `pubspec.yaml`.
  - Unit test đọc asset bundle, kiểm tra RIFF metadata và checksum.
  - macOS integration test đọc asset bundle và checksum; test này không tạo
    `AudioPlayer`, không gọi production adapter và không phát audio.
  - Không để smoke test CI phụ thuộc URL Internet.
  - Tách HTTPS/CDN test sang manual external QA.
- Hoàn thành khi:
  - Unit test đọc asset/metadata/checksum pass.
  - macOS integration asset/checksum test pass.
  - Điều kiện production adapter load/play fixture thuộc PLR-141, không phải
    acceptance gate của PLR-013.

## 6. Phase 2 — Domain thuần Dart

### PLR-019 — Tạo typed `PlayerCommandFailure` `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-001, PLR-008.
- Files:
  - `lib/features/player/domain/player_command_failure.dart`
  - `test/features/player/domain/player_command_failure_test.dart`
- Thực hiện:
  - Tách command validation failure khỏi `PlayerFailure` của engine.
  - Fields tối thiểu: code, message, command; không chứa plugin exception.
  - Gateway trả failed Future bằng type này cho nhánh matrix `typed failure`.
- Test:
  - Equality/message/command.
  - Invalid command không bị biểu diễn như playback error snapshot.

### PLR-020 — Tạo enums playback `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-010.
- Files:
  - `lib/features/player/domain/playback_processing_state.dart`
  - `lib/features/player/domain/player_repeat_mode.dart`
  - `test/features/player/domain/playback_enums_test.dart`
- Thực hiện:
  - `PlaybackProcessingState`: idle, loading, buffering, ready, completed, error.
  - `PlayerRepeatMode`: off, one, all.
- Test:
  - Cycle repeat theo thứ tự off → one → all → off qua helper pure nếu helper thuộc Domain.
- Hoàn thành khi:
  - Domain không import Flutter/Bloc/audio packages.

### PLR-021 — Implement `PlayerFailure` `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-020.
- Files:
  - `lib/features/player/domain/player_failure.dart`
  - `test/features/player/domain/player_failure_test.dart`
- Thực hiện:
  - Immutable fields: code, message, isRecoverable, itemId.
  - `copyWith`, value equality, hashCode.
- Test:
  - Equality/copyWith.
  - Thay `itemId` và recoverability tạo value khác.
  - Không lưu exception hoặc stack trace vào object.

### PLR-022 — Implement `PlayerItem` `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-020, PLR-001.
- Files:
  - `lib/features/player/domain/player_item.dart`
  - `test/features/player/domain/player_item_test.dart`
- Thực hiện:
  - Fields đúng class diagram.
  - `id` là content ID, `audioUri` tách riêng.
  - Deep-copy/deep-equality `extras` theo giới hạn type tại PLR-001.
  - `copyWith`, value equality, hashCode.
- Test:
  - Full equality và inequality từng field.
  - `copyWith` giữ field không đổi.
  - Mutable map truyền từ ngoài không làm đổi item đã tạo.
  - `audioUri` không bị dùng thay `id`.

### PLR-023 — Implement cấu trúc `PlaybackSnapshot` `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-020, PLR-021, PLR-022.
- Files:
  - `lib/features/player/domain/playback_snapshot.dart`
  - `test/features/player/domain/playback_snapshot_test.dart`
- Thực hiện:
  - Toàn bộ fields trong class diagram.
  - Factory/constant idle duy nhất.
  - Defensive-copy queue.
  - `copyWith`, equality và hashCode.
- Test:
  - Idle snapshot có item/index null, queue rỗng, positions zero, speed 1.0, repeat off, shuffle false.
  - Copy một field không làm mất field còn lại.
  - Queue input mutable không làm đổi snapshot.
  - Snapshot value object không tự suy diễn engine transition; reducer chịu
    trách nhiệm tạo tổ hợp state/failure hợp lệ.

### PLR-024 — Implement derived getters và boundary của snapshot `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-023.
- Files:
  - `lib/features/player/domain/playback_snapshot.dart`
  - `test/features/player/domain/playback_snapshot_derived_test.dart`
- Thực hiện:
  - `progress`, `remaining`, `isBuffering`, `isAudible`, `hasNext`, `hasPrevious`, `isCompleted`.
  - Guard duration zero/unknown.
  - Không trả progress NaN/Infinity/ngoài 0..1.
  - `remaining` không âm.
  - Boundary queue/index null hoặc invalid an toàn.
- Test:
  - Duration zero, position âm, position vượt duration.
  - Buffering × playing và ready × playing.
  - Queue rỗng, index đầu, giữa, cuối và invalid.
  - Completed vẫn giữ metadata.

### PLR-025 — Tạo typed test builders và domain fixtures `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-022, PLR-023, PLR-024.
- Files:
  - `test/features/player/support/player_test_data.dart`
  - `test/features/player/support/playback_snapshot_builder.dart`
  - `test/features/player/support/test_data_immutability_test.dart`
- Thực hiện:
  - Tạo factory `testPlayerItem(...)`.
  - Tạo snapshot builder với default idle an toàn.
  - Cho override queue/index/processing/position/duration/options/failure.
  - Không phụ thuộc plugin/platform.
- Test:
  - Hai builder result không chia sẻ mutable list/map.
  - Default builder luôn tạo snapshot hợp lệ.
- Hoàn thành khi:
  - Test Application/Infrastructure không phải lặp constructor dài.

### Gate Phase 2

- Chạy:

```bash
flutter test test/features/player/domain
flutter analyze
```

- Điều kiện:
  - Domain hoàn toàn thuần Dart.
  - Không có state navigation hoặc plugin type trong domain.

### PLR-029 — Rename legacy Cubit/state, không đổi behavior `[CODE]` `[WIDGET]`

- Phụ thuộc: PLR-016, Gate Phase 2.
- Files:
  - `lib/features/player/presentation/cubit/player_cubit.dart`
  - `lib/main.dart`
  - `lib/features/player/presentation/widgets/player_host.dart`
  - `lib/features/player/presentation/widgets/mini_player.dart`
  - `lib/features/player/presentation/widgets/player_control_dock.dart`
  - `test/widget_test.dart`
- Thực hiện:
  - Rename type hiện tại thành `LegacyPlayerCubit`, `LegacyPlayerState` và
    `LegacyPlayerPresentation`.
  - Chỉ sửa imports/type references; giữ nguyên UI behavior để tạo namespace cho
    target `PlayerCubit`.
  - Thêm comment migration-only và task xóa PLR-110.
- Test:
  - Toàn bộ test baseline giữ nguyên kết quả.
  - Không thay đổi snapshot/UI behavior ở task này.

## 7. Phase 3 — Application contract, fake và PlayerCubit

### PLR-030 — Tạo `PlaybackGateway` `[CODE]` `[UNIT]`

- Phụ thuộc: Gate Phase 2, PLR-003, PLR-008, PLR-014, PLR-019.
- Files:
  - `lib/features/player/application/playback_gateway.dart`
  - `test/features/player/application/playback_gateway_contract_test.dart`
- Thực hiện:
  - Khai báo stream snapshot và toàn bộ commands.
  - Bổ sung first-class `retry()` theo PLR-003.
  - Methods trả `Future<void>`.
  - Không import implementation concrete.
- Test:
  - Compile-time fake implement đủ contract.
- Hoàn thành khi:
  - Cubit có thể compile chỉ với interface.

### PLR-031 — Tạo `RecordedCommand` và `FakePlaybackGateway` `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-025, PLR-030.
- Files:
  - `test/features/player/support/fake_playback_gateway.dart`
  - `test/features/player/support/fake_playback_gateway_test.dart`
- Thực hiện:
  - Stream controller cho snapshots.
  - Subscriber mới nhận initial/latest snapshot bất đồng bộ ở microtask kế tiếp;
    stream là broadcast và mỗi subscriber chỉ nhận một replay value.
  - `emit(snapshot)`.
  - Ghi command name, arguments, order và call count.
  - Cho cấu hình command success, delayed completion hoặc exception.
  - `dispose()` controller.
- Test:
  - Emit/replay latest.
  - Record đúng argument và thứ tự.
  - Command error không tự emit snapshot.
  - Dispose không để test leak.

### PLR-032 — Tạo `PlayerState` projection `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-023, PLR-024.
- Files:
  - `lib/features/player/application/player_state.dart`
  - `test/features/player/application/player_state_test.dart`
- Thực hiện:
  - `PlayerState` wrap đúng một `PlaybackSnapshot`.
  - Factory `fromSnapshot`.
  - Convenience getters cho UI.
  - Không có `PlayerPresentation`, fake progress hoặc independent playback fields.
- Test:
  - Mỗi getter phản chiếu snapshot.
  - State equality thay đổi đúng khi snapshot đổi.
  - Completed/error/buffering không làm mất current item.

### PLR-033 — Cubit subscribe và phát snapshot thật `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-016, PLR-029, PLR-031, PLR-032.
- Files:
  - `lib/features/player/application/player_cubit.dart`
  - `test/features/player/application/player_cubit_subscription_test.dart`
- Thực hiện:
  - Inject `PlaybackGateway`.
  - Initial state idle.
  - Subscribe snapshots một lần.
  - Emit `PlayerState.fromSnapshot`.
  - Không timer position.
- Test:
  - Snapshot loading/ready/buffering/completed/error map đúng.
  - Duplicate snapshot không tạo state thừa nếu contract dùng distinct.
  - Position chỉ đổi khi fake emit.

### PLR-041 — Tạo command policies dùng chung đúng layer `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-001, PLR-002, PLR-008, PLR-014.
- Files:
  - `lib/features/player/application/player_command_policies.dart`
  - `test/features/player/application/player_command_policies_test.dart`
- Thực hiện:
  - Đặt skip interval 10 giây, previous restart threshold 3 giây, speed presets
    và repeat-cycle order ở Application.
  - Infrastructure được phép import policy này; Presentation dùng qua
    PlayerCubit/PlayerState, không import Infrastructure.
  - UI cadence/engine-only policy không đặt ở đây.
- Test:
  - Speed presets đúng `0.5/0.75/1.0/1.25/1.5/1.75/2.0`; API range finite
    `[0.5, 2.0]`; constants và repeat cycle đúng decision record.
  - Không có duplicate magic number trong Application/Presentation.

### PLR-042 — Tạo UI Gateway adapter và command source `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-006, PLR-015, PLR-030.
- Files:
  - `lib/features/player/infrastructure/command_source.dart`
  - `lib/features/player/infrastructure/ui_playback_command_target.dart`
  - `lib/features/player/infrastructure/ui_playback_gateway_adapter.dart`
  - `test/features/player/infrastructure/ui_playback_gateway_adapter_test.dart`
- Thực hiện:
  - `UiPlaybackCommandTarget` là internal port tối thiểu cho snapshot/commands;
    fake target dùng trong task này, handler implement ở PLR-060.
  - Adapter implement toàn bộ `PlaybackGateway`, forward snapshot stream.
  - Mỗi UI command gọi internal handler/coordinator operation với source `ui`.
  - OS override không đi qua adapter và dùng source `systemRemote`.
- Test:
  - Mọi command UI giữ arguments/order và source `ui`.
  - Fake OS override cùng operation nhưng source `systemRemote`.
  - Cubit không thể nhận concrete `AppAudioHandler` qua composition root.

### PLR-034 — Cubit `open` và `openQueue` `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-008, PLR-009, PLR-033.
- Files:
  - `lib/features/player/application/player_cubit.dart`
  - `test/features/player/application/player_cubit_open_test.dart`
- Thực hiện:
  - `open(item, autoplay)` delegate thành queue một item/index 0.
  - `openQueue(items, initialIndex, autoplay)` giữ đúng arguments.
  - Không emit current item/loading giả trong Cubit.
- Test:
  - Delegate đúng một lần.
  - Empty/invalid input được gateway xử lý theo boundary, Cubit không mutate state.
  - Gateway throw không tạo playing/current item giả.

### PLR-035 — Cubit play, pause và toggle `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-008, PLR-033.
- Files:
  - `lib/features/player/application/player_cubit.dart`
  - `test/features/player/application/player_cubit_playback_test.dart`
- Thực hiện:
  - `play`, `pause` delegate.
  - `togglePlayback` dùng private `_pendingDesiredPlaying`: đảo pending intent
    nếu có, nếu không đảo snapshot đã xác nhận; snapshot/failure reconcile intent.
  - Pending intent không nằm trong `PlayerState` và không đổi icon optimistically.
  - Áp dụng rapid-intent matrix PLR-008; Cubit không tự debounce bằng timer.
- Test:
  - Play/pause đúng một call.
  - Icon/state không đổi trước fake snapshot.
  - Engine/gateway error giữ state cũ.
  - Double Toggle từ paused route desired Play → Pause dù snapshot chưa đổi;
    icon/state không tạo trạng thái UI giả.

### PLR-036 — Cubit stop, seek và skip `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-004, PLR-008, PLR-033, PLR-041.
- Files:
  - `lib/features/player/application/player_cubit.dart`
  - `test/features/player/application/player_cubit_timeline_test.dart`
- Thực hiện:
  - `stop`, `seekTo`, `skipBackward`, `skipForward`.
  - Cubit truyền `Duration` thật; clamp thuộc handler/validator.
- Test:
  - Seek giữ chính xác Duration.
  - Skip dùng chính xác ±10 giây.
  - Stop không tự clear state trước snapshot idle.

### PLR-037 — Cubit next và previous `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-008, PLR-014, PLR-033.
- Files:
  - `lib/features/player/application/player_cubit.dart`
  - `test/features/player/application/player_cubit_navigation_test.dart`
- Thực hiện:
  - Delegate `next`/`previous`.
  - Không tự đổi queue/current index.
- Test:
  - Mỗi command đúng một call.
  - Queue boundary không khiến Cubit tự đoán item mới.

### PLR-038 — Cubit speed, repeat và shuffle `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-001, PLR-002, PLR-008, PLR-014, PLR-033, PLR-041.
- Files:
  - `lib/features/player/application/player_cubit.dart`
  - `test/features/player/application/player_cubit_options_test.dart`
- Thực hiện:
  - `setSpeed`.
  - `cycleRepeatMode` từ confirmed state.
  - `toggleShuffle` từ confirmed state.
- Test:
  - Repeat off → one → all → off.
  - Shuffle truyền giá trị đối nghịch confirmed state nhưng không emit sớm.
  - Speed invalid tuân theo contract.

### PLR-039 — Cubit retry `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-003, PLR-009, PLR-033.
- Files:
  - `lib/features/player/application/player_cubit.dart`
  - `test/features/player/application/player_cubit_retry_test.dart`
- Thực hiện:
  - Delegate atomic `retry()` theo contract đã chốt.
  - Không tự ghép `load → seek → play` trong UI layer nếu gateway đã có transaction.
- Test:
  - Mỗi lần user gọi Retry, Cubit delegate đúng một lần; Gateway chịu trách nhiệm
    trả `retryUnavailable` nếu non-recoverable/no context.
  - State chỉ đổi khi snapshot mới tới.

### PLR-040 — Cubit lifecycle và command failure `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-008, PLR-034 đến PLR-039.
- Files:
  - `lib/features/player/application/player_cubit.dart`
  - `test/features/player/application/player_cubit_lifecycle_test.dart`
- Thực hiện:
  - Cancel snapshot subscription trong `close()`.
  - Surface typed command failure theo matrix PLR-008, không tạo unhandled async
    error và không chuyển nó thành engine snapshot giả.
  - Close Cubit không stop/dispose handler.
- Test:
  - Snapshot sau close không emit.
  - Subscription cancel đúng một lần.
  - Close không ghi command Stop/Dispose vào fake gateway.
  - Command exception không làm Cubit emit guessed playback state.

### Gate Phase 3

- Chạy:

```bash
flutter test test/features/player/application
flutter analyze
```

- Điều kiện:
  - Toàn bộ Cubit test chạy không cần plugin.
  - PlayerCubit không còn timer, fake progress hoặc navigation state.

## 8. Phase 4 — Infrastructure pure policies và mappers

### PLR-048 — Tạo engine port, clock và test doubles `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-006, PLR-025, PLR-041.
- Files:
  - `lib/features/player/infrastructure/engine/playback_engine.dart`
  - `lib/features/player/infrastructure/player_clock.dart`
  - `test/features/player/support/fake_playback_engine.dart`
  - `test/features/player/support/fake_player_clock.dart`
  - `test/features/player/support/player_call_recorder.dart`
  - `test/features/player/support/playback_test_seams_test.dart`
- Thực hiện:
  - Port chỉ expose streams/commands thực sự handler cần.
  - `load` chỉ prepare source với `initialIndex`; autoplay được handler thực hiện
    sau commit/publication để giữ đúng ordering của PLR-063.
  - Fake engine chủ động emit player state/timeline/index/options/error.
  - Load dùng controllable `Completer`.
  - Fake clock advance đồng bộ, không sleep.
  - Recorder giữ call name, arguments, source và order.
- Test:
  - Mọi stream emit được độc lập.
  - Load completer success/error/stale deterministic.
  - Dispose/call counters quan sát được.

### PLR-049 — Tạo failure mapper riêng `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-001, PLR-009, PLR-021.
- Files:
  - `lib/features/player/infrastructure/player_failure_mapper.dart`
  - `test/features/player/infrastructure/player_failure_mapper_test.dart`
- Thực hiện:
  - Normalize network/not-found/unsupported/audio-output.
  - Internal stale/interrupted load không thành user-visible failure.
- Test:
  - Recoverability/itemId/message cho từng nhóm.
  - Unknown exception fallback an toàn.
  - Initial/replace/stale load context theo PLR-009.

### PLR-050 — Tạo constants và queue validator `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-001, PLR-009, Gate Phase 2.
- Files:
  - `lib/features/player/infrastructure/player_policies.dart`
  - `test/features/player/infrastructure/player_policies_test.dart`
- Thực hiện:
  - Chỉ giữ policy hạ tầng: URI/source validation và cadence publication.
  - Validate queue, initial index, duplicate ID và URI theo contract.
  - Dùng invariant của `PlayerItem` cho deep-copy/immutability của `extras`;
    queue boundary không nhận raw extras và không phát sinh `invalidExtras`.
  - Dùng command constants từ Application khi policy downstream cần chúng;
    không định nghĩa lại 10/3 giây.
- Test:
  - Empty queue.
  - Index âm/quá range.
  - Duplicate ID.
  - Queue trả về là defensive immutable copy và giữ thứ tự.
  - URI matrix `https`/asset/file theo web/native; `http`/scheme khác bị từ chối.
  - Valid single/multi-item queue.
  - Các nhóm extras bị từ chối được kiểm tra tại
    `test/features/player/domain/player_item_test.dart` theo PLR-001.

### PLR-051 — Tạo seek/skip/previous policy pure `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-041, PLR-050.
- Files:
  - `lib/features/player/infrastructure/playback_position_policy.dart`
  - `test/features/player/infrastructure/playback_position_policy_test.dart`
- Thực hiện:
  - Clamp seek.
  - Tính target skip.
  - Quyết định previous: restart current hay chuyển previous index.
- Test:
  - Duration zero/unknown.
  - Target âm/vượt duration.
  - Position đúng 3 giây và lớn hơn 3 giây.
  - Queue index đầu/null/invalid.

### PLR-052 — Mapper `PlayerItem → MediaItem` `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-022, PLR-011.
- Files:
  - `lib/features/player/infrastructure/player_item_mapper.dart`
  - `test/features/player/infrastructure/player_item_mapper_test.dart`
- Thực hiện:
  - Map id/title/artist/album/art/duration.
  - Đặt `audioUri` trong extras theo key duy nhất.
  - Không biến URL thành content ID.
- Test:
  - Optional fields null.
  - Chỉ preserve extras scalar tương thích `MediaItem`: `int`, `String`, `bool`,
    finite `double`; complex extras tiếp tục thuộc Domain.
  - Domain extras không được ghi đè reserved `audioUri`.
  - HTTPS/asset trên mọi platform; file chỉ native; HTTP/scheme khác đã bị
    validator chặn trước mapper.

### PLR-053 — Mapper `PlayerItem → AudioSource` `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-052.
- Files:
  - `lib/features/player/infrastructure/player_item_mapper.dart`
  - `test/features/player/infrastructure/player_audio_source_mapper_test.dart`
- Thực hiện:
  - Tạo source từ `audioUri`.
  - Gắn tag `MediaItem` nếu package flow cần metadata.
  - Không fetch network trong mapper test.
- Test:
  - URI và tag đúng.
  - Queue order giữ nguyên.

### PLR-054 — Mapper processing, repeat và shuffle `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-002, PLR-014, PLR-020, PLR-011.
- Files:
  - `lib/features/player/infrastructure/playback_mappers.dart`
  - `test/features/player/infrastructure/playback_mappers_test.dart`
- Thực hiện:
  - Map 5 processing states engine và error overlay domain.
  - Map repeat domain ↔ engine/audio_service.
  - Map shuffle.
- Test:
  - Mọi enum branch.
  - Engine event hợp lệ sau retry clear failure.

### PLR-055 — Builder OS controls/actions `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-008, PLR-014, PLR-024, PLR-054.
- Files:
  - `lib/features/player/infrastructure/system_controls_builder.dart`
  - `test/features/player/infrastructure/system_controls_builder_test.dart`
- Thực hiện:
  - Chọn Play/Pause, Stop, Seek, rewind/fast-forward, next/previous theo state và queue boundary.
  - Không dùng next/previous cho ±10 giây.
  - Chỉ advertise action platform hỗ trợ.
- Test:
  - Idle, ready paused, ready playing, buffering playing, completed, error.
  - Queue đầu/giữa/cuối.
  - Capability khác nhau không phá core commands.

### PLR-056 — Mapper `PlaybackSnapshot → audio_service.PlaybackState` `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-007, PLR-014, PLR-015, PLR-054, PLR-055.
- Files:
  - `lib/features/player/infrastructure/system_playback_state_mapper.dart`
  - `test/features/player/infrastructure/system_playback_state_mapper_test.dart`
- Thực hiện:
  - Map controls, system actions, processing, playing, updatePosition, bufferedPosition, speed, queueIndex, repeat và shuffle.
  - `updateTime`/clock lấy ở thời điểm publication.
  - Map OS error code/message sanitization đúng bảng PLR-007.
- Test:
  - Tất cả field OS-relevant.
  - Position/speed/queueIndex chính xác.
  - Error/idle theo PLR-007.

### PLR-057 — Snapshot reducer/accumulator atomic `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-009, PLR-014, PLR-023, PLR-024, PLR-049, PLR-054.
- Files:
  - `lib/features/player/infrastructure/playback_snapshot_reducer.dart`
  - `test/features/player/infrastructure/playback_snapshot_reducer_test.dart`
- Thực hiện:
  - Merge player state, position, buffer, duration, index, speed, loop, shuffle, error vào latest snapshot.
  - Current index select item an toàn.
  - Không emit tuple item/index/queue không nhất quán.
- Test:
  - Từng event chỉ đổi field liên quan.
  - Index null/out-of-range.
  - Duration đến sau Ready.
  - Duration giảm nhỏ hơn position.
  - Error rồi load mới.

### PLR-058 — Publication diff và duplicate suppression `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-057.
- Files:
  - `lib/features/player/infrastructure/playback_publication_diff.dart`
  - `test/features/player/infrastructure/playback_publication_diff_test.dart`
- Thực hiện:
  - Phân loại thay đổi:
    - snapshot domain;
    - OS playback state;
    - media item;
    - queue.
  - Không publish metadata theo position tick.
  - Không publish queue theo play/pause/buffering.
- Test:
  - Snapshot giống hệt bị bỏ qua.
  - Position chỉ trigger đúng outputs.
  - Item đổi trigger metadata.
  - Queue/order đổi trigger queue.

### PLR-059 — Generation guard và serializer cho command thay source `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-003, PLR-004, PLR-009.
- Files:
  - `lib/features/player/infrastructure/load_generation_guard.dart`
  - `test/features/player/infrastructure/load_generation_guard_test.dart`
- Thực hiện:
  - Mỗi load/retry có generation.
  - Source navigation/load mới và Stop invalidate generation; publication epoch
    phân biệt event trước/sau Stop barrier.
- Test với controllable completer:
  - A rồi B, A success/error sau B đều stale.
  - Stop khi A pending.
  - Retry pending rồi load item mới.
  - Không deadlock khi command throw.

### PLR-067 — Tạo command coordinator/serializer `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-002, PLR-004, PLR-008, PLR-014, PLR-048, PLR-059.
- Files:
  - `lib/features/player/infrastructure/playback_command_coordinator.dart`
  - `test/features/player/infrastructure/playback_command_coordinator_test.dart`
- Thực hiện:
  - Serialize load/retry/stop/source-index switching.
  - Coalesce Play/Pause trùng và áp dụng last desired intent cho rapid Toggle.
  - Không giữ lock cho position event; platform call được await/cancel theo
    transaction contract.
- Test:
  - Hai Play, hai Pause, Play→Pause, Pause→Play khi call đầu pending.
  - Load/Retry/Stop/Next interleaving.
  - Throw không deadlock; call order đúng decision matrix.

### Gate Phase 4

- Chạy:

```bash
flutter test test/features/player/infrastructure
flutter analyze
```

- Điều kiện:
  - Mọi mapper, reducer, validation, race guard chạy như unit test.
  - Plugin/platform chưa cần khởi tạo trong các test này.

## 9. Phase 5 — `AppAudioHandler` core và state broadcasting

### PLR-060 — Tạo handler, engine ownership và initial snapshot `[CODE]` `[UNIT]`

- Phụ thuộc: Gate Phase 4, PLR-006, PLR-042, PLR-048.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `lib/features/player/infrastructure/engine/just_audio_playback_engine.dart`
  - `test/features/player/infrastructure/app_audio_handler_initial_test.dart`
- Thực hiện:
  - Extend `BaseAudioHandler`, mix `QueueHandler`, `SeekHandler`, implement
    internal `UiPlaybackCommandTarget`; `UiPlaybackGatewayAdapter` mới implement
    public `PlaybackGateway`.
  - `JustAudioPlaybackEngine` tạo/sở hữu đúng một production `AudioPlayer`.
  - `AppAudioHandler.production()` tạo đúng một engine adapter; test constructor
    inject fake engine và fake clock.
  - Giữ latest idle snapshot.
  - `snapshots` là broadcast và replay đúng một latest value bất đồng bộ cho mỗi
    subscriber, không cần thêm Rx dependency.
  - Giữ danh sách subscriptions.
- Test:
  - Initial fields idle.
  - Subscriber mới nhận latest.
  - Không publish system card khi idle.
  - Injectable factory/count assertion chứng minh production path tạo một engine.
  - UI adapter nhận snapshot/commands từ handler mà vẫn giữ provenance.

### PLR-061 — Bind engine streams vào reducer `[CODE]` `[UNIT]` `[INTEGRATION]`

- Phụ thuộc: PLR-048, PLR-057, PLR-058, PLR-060.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_streams_test.dart`
- Thực hiện:
  - Subscribe player state, position, buffered position, duration, current index, speed, loop và shuffle.
  - Mọi callback đi qua reducer/diff.
  - Lifecycle/error events emit ngay; position đi qua UI projector 200 ms và OS
    position-only projector 1 giây.
- Test:
  - Event sequence tạo snapshot đúng.
  - Event trùng không emit.
  - Current item/OS metadata không stale.
  - Pause ở ready giữ processing ready.
  - Play intent ở buffering không ép processing ready.
  - Seek khi paused giữ playing false.

### PLR-062 — Implement `loadQueue` validation và loading state `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-008, PLR-009, PLR-050, PLR-059, PLR-061, PLR-067.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `lib/features/player/infrastructure/playback_contexts.dart`
  - `test/features/player/infrastructure/app_audio_handler_load_validation_test.dart`
- Thực hiện:
  - Validate trước khi chạm engine.
  - Tăng generation.
  - Tạo `PendingLoadContext`; initial load có outward item/queue rỗng, replace
    load giữ `ActivePlaybackContext` và metadata cũ trong lúc loading.
  - Emit processing loading với input hợp lệ nhưng không publish pending target
    thành current metadata/queue.
  - Map source/media item từ cùng `PlayerItem` list.
- Test:
  - Invalid input không gọi engine/publication.
  - Loading đến trước engine load.
  - Không publish queue/metadata chưa được latest-confirmed.
  - Replace load giữ active metadata theo PLR-009.

### PLR-063 — Commit load success và autoplay ordering `[CODE]` `[UNIT]` `[INTEGRATION]`

- Phụ thuộc: PLR-009, PLR-014, PLR-052, PLR-053, PLR-062.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_load_commit_test.dart`
- Thực hiện:
  - Sau engine ready và generation vẫn latest:
    1. commit queue/index/item;
    2. publish queue/media item;
    3. emit ready paused;
    4. nếu autoplay, gọi play đúng một lần;
    5. chỉ emit playing khi engine stream xác nhận.
- Test:
  - Autoplay false và true.
  - Metadata có trước Play.
  - Không optimistic playing.
  - Engine Play failure không để state playing.

### PLR-064 — Latest-load-wins end-to-end trong handler `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-059, PLR-063.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_load_race_test.dart`
- Test-first scenarios:
  - A pending → B starts → B ready → A ready.
  - A pending → B starts → A interrupted error → B ready.
  - A ready nhưng chưa publish → B invalidates A.
- Điều kiện:
  - Chỉ B xuất hiện ở domain snapshot, OS media item và queue.
  - Stale exception không thành `PlayerFailure`.

### PLR-065 — UI position cadence `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-015, PLR-048, PLR-061.
- Files:
  - `lib/features/player/infrastructure/player_position_projector.dart`
  - `test/features/player/infrastructure/player_position_projector_test.dart`
- Thực hiện:
  - Projection UI mục tiêu khoảng 200 ms.
  - Lifecycle event không bị throttle.
  - Metadata/artwork không republish theo tick.
- Test với fake clock:
  - Nhiều tick trong một cadence giữ latest.
  - Completed/error/buffering emit ngay.
  - Position tick không publish media item/queue.

### PLR-068 — OS timeline cadence và immediate events `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-015, PLR-048, PLR-056, PLR-058, PLR-061, PLR-065.
- Files:
  - `lib/features/player/infrastructure/system_timeline_projector.dart`
  - `test/features/player/infrastructure/system_timeline_projector_test.dart`
- Thực hiện:
  - Position-only resync mỗi 1 giây theo PLR-015.
  - Lifecycle/load commit/item/index/Play/Pause/Seek/Speed/Repeat/Shuffle/
    Buffering/Completed/Error/Stop publish ngay.
  - Dùng updatePosition/updateTime/speed để OS nội suy.
- Test bằng fake clock:
  - N position ticks không tạo N OS publications.
  - Mọi immediate event không bị đợi cadence.
  - Không publish metadata/queue theo position-only event.

### PLR-066 — Broadcast queue, media item và playback state `[CODE]` `[UNIT]` `[INTEGRATION]`

- Phụ thuộc: PLR-014, PLR-058, PLR-063, PLR-065, PLR-068.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_publication_test.dart`
- Thực hiện:
  - Publish đúng output khi diff yêu cầu.
  - Queue/index/item cùng nguồn domain.
  - Artwork failure không làm playback failure.
- Test:
  - Item đổi cập nhật media item đúng một lần.
  - Queue đổi cập nhật queue đúng một lần.
  - Play/pause/buffering chỉ cập nhật playback state.

## 10. Phase 6 — Commands, queue navigation và remote callbacks

### PLR-069 — Replay completed transaction `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-002, PLR-008, PLR-061, PLR-067.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_replay_test.dart`
- Thực hiện:
  - `completed × playing=false` + Play seek `Duration.zero` trên current item rồi
    mới play.
  - Không clear metadata/session.
- Test:
  - Call order seek → play.
  - Play đúng một lần và state chỉ đổi sau engine confirmation.

### PLR-070 — Play/Pause idempotent `[CODE]` `[UNIT]` `[INTEGRATION]`

- Phụ thuộc: PLR-008, PLR-061, PLR-063, PLR-067, PLR-069.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_play_pause_test.dart`
- Thực hiện:
  - Play bình thường gọi engine một lần.
  - Pause giữ queue/current item/media session.
  - Command không emit confirmed state.
  - Coalesce command trùng và last-intent-wins theo PLR-008.
- Test:
  - Play/Pause rejection.
  - Pause không clear system card.
  - Rapid Play/Play, Pause/Pause, Play/Pause và Pause/Play.

### PLR-071 — Seek và skipBy dùng chung validator `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-008, PLR-041, PLR-051, PLR-061, PLR-067.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_seek_test.dart`
- Thực hiện:
  - UI và OS seek vào cùng operation.
  - Clamp 0..duration.
  - Không có current item trả `noCurrentItem`; duration unknown/zero trả
    `seekUnavailableUnknownDuration`; cả hai không gọi engine.
  - `skipBy` chỉ tính target rồi gọi seek.
- Test:
  - Âm, trong range, quá duration, duration zero.
  - ±10 giây không gọi next/previous.
  - State chỉ đổi sau engine position event.

### PLR-072 — Next/Previous operation canonical `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-002, PLR-008, PLR-014, PLR-051, PLR-059, PLR-061, PLR-067.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_navigation_test.dart`
- Thực hiện:
  - Một private operation cho UI `next/previous` và OS `skipToNext/skipToPrevious`.
  - Previous tuân ngưỡng 3 giây.
  - Dùng effective queue; repeat all wrap, repeat off/one boundary no-op và
    repeat one không chặn explicit navigation.
- Test:
  - Queue đầu/giữa/cuối.
  - Repeat off/all.
  - Previous >3s, =3s, <3s.
  - Switching item không interleave load/stop.
  - Next cuối + repeat off/all và explicit Next khi repeat one.
  - Shuffle dùng đúng effective order PLR-014.

### PLR-073 — Rewind/Fast-forward remote callbacks `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-061, PLR-071.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_remote_seek_test.dart`
- Thực hiện:
  - Override remote rewind/fast-forward.
  - Dùng cùng `skipBy(-10s/+10s)`.
- Test:
  - Mỗi callback gọi seek operation đúng một lần.
  - Không gọi queue navigation.

### PLR-074 — Speed `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-001, PLR-008, PLR-041, PLR-054, PLR-061, PLR-067.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_speed_test.dart`
- Thực hiện:
  - Validate speed.
  - Gọi engine.
  - Snapshot/OS chỉ đổi sau stream confirmation.
- Test:
  - Mọi UI preset `0.5/0.75/1.0/1.25/1.5/1.75/2.0` hợp lệ.
  - API finite trong `[0.5, 2.0]` hợp lệ; outside/non-finite trả `invalidSpeed`.
  - PlaybackState speed đúng.

### PLR-075 — Repeat mode `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-002, PLR-008, PLR-014, PLR-054, PLR-061, PLR-067.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_repeat_test.dart`
- Thực hiện:
  - Map off/one/all sang engine loop mode.
  - Không double-handle completion.
- Test:
  - Mọi mode.
  - Engine event xác nhận mới đổi snapshot.
  - End-of-queue behavior đúng owner.

### PLR-076 — Shuffle `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-008, PLR-014, PLR-054, PLR-061, PLR-067.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_shuffle_test.dart`
- Thực hiện:
  - Enable/disable engine shuffle.
  - Publish effective queue/order theo decision PLR-014.
- Test:
  - Toggle đúng một call.
  - Snapshot confirmation.
  - Current item/index vẫn nhất quán.

### PLR-077 — Remote callbacks parity `[CODE]` `[UNIT]` `[INTEGRATION]`

- Phụ thuộc: PLR-015, PLR-061, PLR-069 đến PLR-076.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_remote_callbacks_test.dart`
- Test matrix:
  - Play, Pause, Seek.
  - Rewind/Fast-forward.
  - Next/Previous.
  - Speed/repeat/shuffle khi platform expose.
- Điều kiện:
  - Callback OS không đi qua Cubit.
  - Callback UI và OS hội tụ một handler operation.
  - Cubit tạo sau remote command nhận latest snapshot.
  - Remote Stop được bổ sung trong PLR-086 sau khi Stop transaction tồn tại.

## 11. Phase 7 — Error, Retry, interruption, Stop và cleanup

### PLR-080 — Error normalization và error snapshot `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-005, PLR-007, PLR-009, PLR-049, PLR-061.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_error_test.dart`
- Thực hiện:
  - Normalize lỗi load/network/source/format/output.
  - Initial failure giữ outward item/queue/index empty/null; runtime failure giữ
    active context; replace A→B failure giữ A outward và attach failure/Retry
    target B.
  - Set processing error và `playing=false`; không tạo playing giả. Stop failure
    là nhánh riêng ở PLR-086 và giữ engine-confirmed state gần nhất.
  - Broadcast OS error với sanitized message và stable code PLR-007.
- Test:
  - Recoverable/non-recoverable.
  - Không playing giả.
  - Stale load error bị bỏ.
  - Item metadata được giữ để UI giải thích lỗi.
  - Initial load failure giữ queue/item/index empty/null, không publish system
    metadata và mini không có item để hiển thị.
  - Replace-load failure giữ active/pending context theo PLR-009.

### PLR-081 — Atomic Retry `[CODE]` `[UNIT]` `[INTEGRATION]`

- Phụ thuộc: PLR-003, PLR-009, PLR-059, PLR-067, PLR-080.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_retry_test.dart`
- Thực hiện:
  1. Tạo generation mới và invalidate transaction cũ.
  2. Reload exact `RetryContext` target với autoplay false.
  3. Xác nhận latest, đọc duration và clamp/seek saved position.
  4. Xác nhận latest lần nữa rồi atomic commit/publish.
  5. Play đúng một lần chỉ khi latest desired intent vẫn true.
- Test:
  - Call order load → seek → commit/publication → conditional Play.
  - Không play hai lần.
  - Initial/runtime/replace failure chọn đúng Retry target.
  - User chọn item mới trong lúc retry.
  - Retry throw cập nhật failure mới nhưng không loop vô hạn.
  - Prior-paused restore position nhưng không play.
  - Saved position vượt duration mới được clamp.
  - User Pause trong retry giữ reload nhưng chặn Play; Stop/load/navigation mới
    invalidate retry; stale result không publish.
  - No context/non-recoverable trả `retryUnavailable`, engine call count zero.

### PLR-082 — Buffering projection `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-061.
- Files:
  - `test/features/player/infrastructure/app_audio_handler_buffering_test.dart`
- Thực hiện:
  - `buffering × playing` giữ play intent.
  - Ready trở lại không gọi Play lần nữa.
- Test:
  - Ready playing → buffering playing → ready playing.
  - Buffering paused.
  - OS/UI nhận state nhất quán.
  - Play trong buffering không ép processing ready.
  - Pause ở ready không đổi processing state.

### PLR-083 — Completion và Replay state `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-002, PLR-069, PLR-070, PLR-075.
- Files:
  - `test/features/player/infrastructure/app_audio_handler_completion_test.dart`
- Thực hiện:
  - Repeat off ở cuối giữ metadata/current item.
  - Handler phát đúng một engine Pause normalization và outward state là
    `completed × playing=false`.
  - UI có thể render Replay.
  - Chỉ Stop mới clear.
- Test:
  - Completed không ẩn mini.
  - Completion duplicate không tạo thêm Pause/publication.
  - Play từ completed call order seek zero → play.
  - Repeat modes không double-advance.

### PLR-084 — Interruption ownership và conditional resume `[CODE]` `[UNIT]` `[INTEGRATION]`

- Phụ thuộc: PLR-005, PLR-048, PLR-061.
- Files:
  - `lib/features/player/infrastructure/interruption_observer.dart`
  - `test/features/player/infrastructure/interruption_observer_test.dart`
- Thực hiện:
  - `AudioSession.configure` vẫn chỉ thuộc PLR-090 composition root.
  - Không tạo listener gọi pause/resume cạnh tranh nếu just_audio đã xử lý
    runtime interruption.
  - Observer chỉ project/log trạng thái engine-confirmed; không gọi Play/Pause.
- Test khả thi:
  - Observer event có engine call count zero.
  - Integration chứng minh một interruption event tạo tối đa một engine Pause do
    just_audio sở hữu; user Pause không bị app tự resume.
  - Integration/manual event thật ở PLR-125, PLR-144, PLR-145 và PLR-148.

### PLR-085 — Becoming noisy `[CODE]` `[UNIT]` `[INTEGRATION]`

- Phụ thuộc: PLR-084.
- Files:
  - `test/features/player/infrastructure/becoming_noisy_policy_test.dart`
- Thực hiện:
  - Passive-observe engine Pause khi route audio mất.
  - Không có application Play khi tai nghe/Bluetooth quay lại.
- Test:
  - App observer có engine call count zero.
  - Integration chứng minh một becoming-noisy event tạo đúng một engine Pause do
    just_audio sở hữu, không có listener thứ hai gọi Pause cạnh tranh.
  - Platform behavior xác nhận trong manual QA.
  - Route audio quay lại không gọi Play.

### PLR-086 — Stop transaction `[CODE]` `[UNIT]` `[INTEGRATION]`

- Phụ thuộc: PLR-004, PLR-059, PLR-066, PLR-067, PLR-077.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_stop_test.dart`
- Thực hiện:
  - Mở publication barrier/epoch, invalidate source transaction, await engine
    Stop, reset baseline, atomic clear context/snapshot, publish media null →
    queue empty → OS idle → đúng một Domain idle, rồi đóng barrier.
  - Chặn event trong barrier và bỏ event epoch cũ.
  - Engine Stop failure giữ session/card và expose `stopFailed`; không pop route.
  - Option-reset failure sau engine Stop vẫn cleanup outward; load mới reapply
    baseline trước Ready.
  - Giữ handler reusable.
- Test:
  - Call/order recorder.
  - Stop khi playing/paused/loading/error/completed.
  - Stop thứ hai sau thành công không gọi engine/republish.
  - Stop failure không publish idle giả và Stop sau failure có thể retry.
  - Không có outward snapshot trung gian trong barrier.
  - Late load không hồi sinh state.
  - Load mới sau Stop.
  - Remote Stop callback đi vào đúng transaction và gỡ system card.

### PLR-087 — Handler dispose và subscription cleanup `[CODE]` `[UNIT]` `[INTEGRATION]`

- Phụ thuộc: PLR-061, PLR-086.
- Files:
  - `lib/features/player/infrastructure/app_audio_handler.dart`
  - `test/features/player/infrastructure/app_audio_handler_dispose_test.dart`
- Thực hiện:
  - Cancel toàn bộ subscriptions đúng một lần.
  - Close snapshot controller.
  - Dispose engine đúng một lần khi process/composition teardown.
  - Route dispose/Cubit close không gọi handler dispose.
- Test:
  - Mọi subscription được cancel.
  - Event sau dispose bị bỏ an toàn.
  - Double dispose không crash theo contract.

### PLR-088 — Structured logging không ảnh hưởng command path `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-015, PLR-063, PLR-070 đến PLR-086.
- Files:
  - `lib/features/player/infrastructure/player_logger.dart`
  - `test/features/player/infrastructure/player_logging_test.dart`
- Thực hiện:
  - Event:
    - `player_load_started`/`player_load_ready` với generation/index/latency.
    - `player_play`/`player_pause`.
    - `player_seek` với from/to/source.
    - `player_item_changed` với old/new/reason.
    - `player_buffering_started`/`player_buffering_ended` với durationMs.
    - `player_interrupted`.
    - `player_error` với code/item/recoverable.
    - `player_stopped` với reason.
  - Fields không chứa secret/PII.
  - Source dùng `ui`, `systemRemote`, `interruption` và chỉ chi tiết hơn khi
    platform callback thật sự cung cấp provenance.
  - Logger là optional/no-op; logger failure không phá playback.
- Test:
  - Event name/fields/source.
  - Logger throw không thay đổi result command.

### Gate Phase 7

- Chạy:

```bash
flutter test test/features/player
flutter analyze
```

- Điều kiện:
  - Unit tests cover load race, retry order, Stop order, buffering và completion.
  - Không còn unhandled subscription trong test.

## 12. Phase 8 — Bootstrap ứng dụng

### PLR-089 — Tạo `AudioServiceConfig` factory `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-007, PLR-041.
- Files:
  - `lib/features/player/infrastructure/player_audio_service_config.dart`
  - `test/features/player/infrastructure/player_audio_service_config_test.dart`
- Thực hiện:
  - Dùng literal channel ID `com.vilisten.playback`.
  - Channel name `Đang phát`.
  - Fast-forward/rewind interval 10 giây từ command policy.
  - Set explicit `androidStopForegroundOnPause: false`; không dùng default ngầm.
- Test:
  - Mọi field config đúng literal/policy.
  - Channel ID chỉ được định nghĩa ở một nơi.

### PLR-090 — Tách composition function có thể test `[CODE]` `[UNIT]`

- Phụ thuộc: Gate Phase 7, PLR-007, PLR-060, PLR-084, PLR-089.
- Files:
  - `lib/main.dart`
  - `lib/app/player_bootstrap.dart`
  - `lib/features/player/infrastructure/unavailable_playback_gateway.dart`
  - `test/app/player_bootstrap_test.dart`
- Thực hiện:
  - `main()` async.
  - `WidgetsFlutterBinding.ensureInitialized()`.
  - `AudioService.init` trước `runApp`.
  - Dùng config factory PLR-089.
  - `AudioSessionConfiguration.speech()`.
  - Tạo một `UiPlaybackGatewayAdapter(handler)` và inject adapter vào
    `PlayerCubit`; OS vẫn gọi handler trực tiếp.
- Test:
  - Với seam bootstrap, assert call order.
  - Handler/Cubit/player/UI-gateway-adapter cardinality mỗi loại bằng một.
  - Dev/test bootstrap failure rethrow original error/stack.
  - Production bootstrap failure inject `UnavailablePlaybackGateway`, phát
    `bootstrapUnavailable`, command trả `commandUnavailable` và engine/player
    creation count sau failure bằng zero; không retry ngầm.

### PLR-091 — Tạo dual-provider migration bridge `[CODE]` `[WIDGET]`

- Phụ thuộc: PLR-016, PLR-029, PLR-090.
- Files:
  - `lib/main.dart`
  - `test/app/player_provider_bridge_test.dart`
- Thực hiện:
  - Cung cấp target `PlayerCubit` phía trên `MaterialApp`/app shell.
  - Tạm tiếp tục cung cấp `LegacyPlayerCubit` để widget chưa migrate vẫn build.
  - Cả hai provider không được sở hữu engine; target Cubit dùng cùng một handler,
    legacy Cubit chỉ giữ fake state cũ.
  - Gắn TODO bắt buộc xóa ở PLR-110.
- Test:
  - Cả widget legacy và target resolve đúng provider trong migration.
  - Widget rebuild không tạo engine/handler mới.
  - Push/pop route không đổi identity target Cubit/gateway.

### PLR-092 — App lifecycle không điều khiển playback `[CODE]` `[UNIT]` `[WIDGET]`

- Phụ thuộc: PLR-077, PLR-091.
- Files:
  - `lib/app/app_lifecycle_observer.dart` nếu app cần observer thụ động.
  - `test/app/player_app_lifecycle_test.dart`
- Thực hiện:
  - Background/inactive/paused không gọi Play/Pause/Stop.
  - Remote command vẫn được handler xử lý khi UI background.
  - Resumed/foreground đọc latest snapshot; không tạo reconciliation engine thứ
    hai và không replay command.
- Test:
  - Simulate paused/inactive/detached/resumed.
  - Command recorder vẫn rỗng với lifecycle-only events.
  - Emit remote snapshot khi background rồi resume; UI render đúng latest.

## 13. Phase 9 — UI migration theo lát nhỏ

### PLR-100 — Chuẩn bị dual-provider widget-test harness `[CODE]` `[WIDGET]`

- Phụ thuộc: PLR-031, PLR-091, PLR-092.
- Files:
  - `test/widget_test.dart`
  - Test support files.
- Thực hiện:
  - Inject target `PlayerCubit(FakePlaybackGateway)` cùng
    `LegacyPlayerCubit` qua migration bridge PLR-091.
  - Target fake snapshot là idle nhưng legacy `PlayerHost` vẫn được phép giữ
    baseline UI cho đến PLR-101.
  - Chỉ đổi harness/provider ở task này; chưa đổi expectation mini/progress cũ.
- Test:
  - App shell render không plugin và cả hai provider resolve đúng.
  - Test baseline legacy vẫn pass, giữ build xanh.
  - Acceptance “idle không hiện mini/bỏ 45%” chuyển sang PLR-101 ngay khi Host
    migrate sang target Cubit.

### PLR-101 — Migrate `PlayerHost` khỏi navigation state `[CODE]` `[WIDGET]`

- Phụ thuộc: PLR-032, PLR-100.
- Files:
  - `lib/features/player/presentation/widgets/player_host.dart`
  - `test/features/player/presentation/widgets/player_host_test.dart`
  - `test/widget_test.dart`
- Thực hiện:
  - Hiện mini iff `currentItem != null`.
  - Push route trực tiếp; bỏ `expand/minimize`.
  - Chặn push expanded trùng khi route đang mở.
  - Đổi app-level expectations sang target idle; bỏ assumption mini 45%.
- Test:
  - Idle ẩn mini.
  - Ready/loading/error/completed có item thì hiện mini theo UI policy.
  - Stop snapshot ẩn mini.
  - Tap nhanh không push hai route.

### PLR-102 — Migrate metadata của MiniPlayer `[CODE]` `[WIDGET]`

- Phụ thuộc: PLR-101.
- Files:
  - `lib/features/player/presentation/widgets/mini_player.dart`
  - `test/features/player/presentation/widgets/mini_player_test.dart`
- Thực hiện:
  - Title, artist, duration, artwork/semantics từ current item/state.
  - Play/Pause icon từ confirmed playing.
  - Buffering indicator tách khỏi play intent.
  - Progress từ snapshot.
- Test:
  - Không còn chuỗi hard-code BBC trong UI.
  - Metadata đổi khi current item đổi.
  - Buffering playing vẫn hiển thị Pause intent + spinner.
  - Tap command không đổi icon trước fake snapshot.

### PLR-103 — Migrate `PlayerArtwork` `[CODE]` `[WIDGET]`

- Phụ thuộc: PLR-102.
- Files:
  - `lib/features/player/presentation/widgets/player_artwork.dart`
  - `test/features/player/presentation/widgets/player_artwork_test.dart`
- Thực hiện:
  - Nhận `artUri`.
  - Có placeholder/fallback nếu null/load lỗi.
  - Giữ Hero tag/animation.
  - Inject `ImageProvider`/resolver trong widget test; không gọi network thật.
- Test:
  - Null/valid/error artwork.
  - Artwork đổi theo item.
  - Position tick không rebuild/fetch artwork lại.

### PLR-104 — Tách formatter Duration pure `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-024.
- Files:
  - `lib/features/player/presentation/player_duration_formatter.dart`
  - `test/features/player/presentation/player_duration_formatter_test.dart`
- Thực hiện:
  - Format elapsed/remaining từ `Duration`.
  - Không clamp ở 159 giây.
- Test:
  - 0, dưới phút, nhiều phút, trên giờ, remaining zero/âm.

### PLR-105 — Chuyển `PlayerControlDock` sang state thật `[CODE]` `[WIDGET]`

- Phụ thuộc: PLR-036 đến PLR-038, PLR-104.
- Files:
  - `lib/features/player/presentation/widgets/player_control_dock.dart`
  - `test/features/player/presentation/widgets/player_control_dock_timeline_test.dart`
- Thực hiện:
  - Dùng position/duration/bufferedPosition thật.
  - Disable slider khi duration unknown/zero.
  - Bind play/pause và ±10s.
  - Completed đổi main action thành Replay.
- Test:
  - Timestamp/duration không hard-code.
  - Playback/timeline control delegate đúng command.

### PLR-106 — Local seek preview và single commit `[CODE]` `[WIDGET]`

- Phụ thuộc: PLR-105.
- Files:
  - `lib/features/player/presentation/widgets/player_control_dock.dart`
  - `test/features/player/presentation/widgets/player_seek_preview_test.dart`
- Thực hiện:
  - `isDragging` và `previewPosition` là state cục bộ.
  - `onChanged` chỉ render preview.
  - `onChangeEnd` gọi `seekTo` đúng một lần.
  - Engine snapshot sau commit ghi đè preview.
- Test:
  - Nhiều pointer updates → zero gateway seek.
  - Drag end → một gateway seek với giá trị cuối.
  - Snapshot tới trong lúc drag không giật preview.
  - Duration trở thành zero khi drag được xử lý an toàn.

### PLR-111 — Migrate queue/options controls trong dock `[CODE]` `[WIDGET]`

- Phụ thuộc: PLR-037, PLR-038, PLR-105.
- Files:
  - `lib/features/player/presentation/widgets/player_control_dock.dart`
  - `test/features/player/presentation/widgets/player_control_dock_options_test.dart`
- Thực hiện:
  - Bind next/previous, speed, repeat và shuffle.
  - Enabled/disabled state theo confirmed queue/options.
- Test:
  - Mỗi control delegate đúng command một lần.
  - Queue boundary và option icon/semantics đúng snapshot confirmed.

### PLR-107 — Migrate Expanded Player metadata/state `[CODE]` `[WIDGET]`

- Phụ thuộc: PLR-103, PLR-105, PLR-111.
- Files:
  - `lib/features/player/presentation/expanded_player_screen.dart`
  - `test/features/player/presentation/expanded_player_screen_test.dart`
- Thực hiện:
  - Title, artist, duration, artwork từ PlayerState.
  - Giữ gesture, sheet, Hero và animation hiện hữu.
  - Chỉ giữ sheet extent/dismiss/local seek preview cục bộ.
  - Không giữ playing/item/queue/options chính thức trong State widget.
- Test:
  - Metadata đổi theo snapshot.
  - Layout/gesture tests hiện hữu vẫn pass.
  - Completed/error/buffering render đúng.

### PLR-108 — Route independence và lifecycle widget `[CODE]` `[WIDGET]`

- Phụ thuộc: PLR-101, PLR-107.
- Files:
  - `lib/features/player/presentation/expanded_player_screen.dart`
  - `test/features/player/presentation/player_route_lifecycle_test.dart`
- Test:
  - Push/pop/back/swipe down không ghi play/pause/stop/dispose command.
  - Route dispose chỉ dispose controller của màn hình.
  - Playback snapshot tiếp tục cập nhật mini sau khi pop.
  - Stop/current item null tự pop player route đúng một lần nếu route đó đang
    top-most; không pop route khác, không gửi thêm Stop/Pause và không hồi sinh
    mini sau route completion.

### PLR-109 — Fine-grained selectors và rebuild budget `[CODE]` `[WIDGET]`

- Phụ thuộc: PLR-102 đến PLR-107.
- Files:
  - Các widget player đã migrate.
  - `test/features/player/presentation/player_rebuild_budget_test.dart`
- Thực hiện:
  - Metadata/artwork selector.
  - Playing/processing selector.
  - Position/duration/buffer selector.
  - Speed/repeat/shuffle selector.
  - Queue-navigation selector.
- Test instrumentation:
  - Position tick không rebuild artwork/full expanded screen.
  - Metadata đổi không tạo command.
  - Transcript chỉ rebuild vùng cue nếu feature đó dùng position.
- Hoàn thành khi:
  - Không có `BlocBuilder` toàn màn hình rebuild theo cadence 200 ms.

### PLR-110 — Xóa toàn bộ legacy Cubit/provider bridge `[CODE]` `[WIDGET]`

- Phụ thuộc: PLR-100 đến PLR-109, PLR-111.
- Files:
  - `lib/main.dart`
  - `lib/features/player/presentation/cubit/player_cubit.dart`
  - Toàn bộ imports legacy dưới `lib/features/player/presentation/`.
  - `test/app/player_provider_bridge_test.dart`
- Thực hiện:
  - Xóa `LegacyPlayerCubit`, `LegacyPlayerState`, `LegacyPlayerPresentation`.
  - Xóa dual-provider bridge; chỉ còn target `PlayerCubit`.
  - Xóa fake progress/navigation methods.
- Test:
  - App/widget suite pass chỉ với target Cubit.
  - Static search không còn `LegacyPlayer` hoặc legacy API.

### Gate Phase 9

- Chạy:

```bash
flutter test test/widget_test.dart
flutter test test/features/player/presentation
flutter analyze
```

- Kiểm tra bằng search:

```bash
rg -n "159|\\.45|The English We Speak|PlayerPresentation|LegacyPlayer|Timer" lib/features/player lib/main.dart
```

- Điều kiện:
  - Không còn metadata/duration/progress mô phỏng trong player.
  - Mini và expanded dùng cùng snapshot.
  - PLR-110 hoàn thành; chỉ còn một target PlayerCubit/provider.

## 14. Phase 10 — Cấu hình platform

### PLR-120 — Android permissions, service và receiver `[NATIVE-CODE]` `[INTEGRATION]`

- Phụ thuộc: PLR-089, PLR-090, Gate Phase 9.
- File:
  - `android/app/src/main/AndroidManifest.xml`
- Thực hiện:
  - Thêm `INTERNET`, `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`.
  - Thêm `xmlns:tools` nếu manifest dùng `tools:ignore`.
  - Khai báo service:
    - `android:name="com.ryanheise.audioservice.AudioService"`.
    - `android:foregroundServiceType="mediaPlayback"`.
    - `android:exported="true"`.
    - Intent action `android.media.browse.MediaBrowserService`.
    - `tools:ignore="Instantiatable"` nếu plugin setup yêu cầu.
  - Khai báo receiver:
    - `android:name="com.ryanheise.audioservice.MediaButtonReceiver"`.
    - `android:exported="true"`.
    - Intent action `android.intent.action.MEDIA_BUTTON`.
    - `tools:ignore="Instantiatable"` nếu plugin setup yêu cầu.
  - Dùng channel ID `com.vilisten.playback` và name `Đang phát` từ PLR-089.
  - Không bật cleartext toàn ứng dụng cho URL HTTPS.
- Kiểm tra:
  - Manifest merge debug/release.
  - Android build thành công.
  - Không duplicate service/receiver.

### PLR-121 — Android Activity base class `[NATIVE-CODE]` `[INTEGRATION]`

- Phụ thuộc: PLR-120.
- File:
  - `android/app/src/main/kotlin/com/viuniverse/vilisten/MainActivity.kt`
- Thực hiện:
  - Đổi sang `AudioServiceActivity` hoặc `AudioServiceFragmentActivity` nếu app cần FragmentActivity.
- Kiểm tra:
  - App start bình thường.
  - Plugin registration và deep/navigation behavior hiện hữu không regress.

### PLR-122 — Android notification/foreground policy ⚠️ `[MANUAL:DEVICE-QA]`

- Phụ thuộc: PLR-120, PLR-121.
- Thao tác tay:
  - Cài release/debug build trên Android 12+.
  - Xác nhận notification/system card, media buttons, Stop gỡ card.
  - Xác nhận behavior khi swipe recent tasks/restart theo PLR-007.
  - Xác nhận Pause giữ card/service với `androidStopForegroundOnPause=false`,
    pause dài vẫn resume được từ media button trên Android 12+.
  - Swipe recent tasks không tự gửi Stop; process death rồi cold bootstrap bắt
    đầu canonical idle, không auto-restore/autoplay.
  - Kiểm tra merged manifest/behavior notification của plugin trên API tương
    ứng; không thêm permission ngoài contract một cách máy móc.
- Evidence:
  - Device/API/build type, timestamp, pass/fail, ảnh/video/logcat khi fail.
  - Lưu merged release manifest làm artifact.

### PLR-123 — iOS `Info.plist` background audio `[NATIVE-CODE]`

- Phụ thuộc: PLR-090.
- File:
  - `ios/Runner/Info.plist`
- Thực hiện:
  - Thêm `UIBackgroundModes` với `audio`.
  - Không bật arbitrary ATS loads nếu không cần.
- Kiểm tra:
  - `plutil -lint ios/Runner/Info.plist`.
  - Không duplicate key sau khi thao tác Xcode ở PLR-124.

### PLR-124 — Bật iOS Background Modes trong Xcode ⚠️ `[MANUAL:XCODE-IOS]`

- Phụ thuộc: PLR-123.
- Đây là task bắt buộc làm tay:
  1. Mở `ios/Runner.xcworkspace` bằng Xcode.
  2. Chọn target `Runner`.
  3. Mở `Signing & Capabilities`.
  4. Thêm/bật `Background Modes`.
  5. Tick `Audio, AirPlay, and Picture in Picture`.
  6. Xác nhận `UIBackgroundModes/audio` chỉ có một lần.
  7. Xác nhận Team, Bundle ID và signing cho Debug/Release đúng môi trường.
- Hoàn thành khi:
  - Capability xuất hiện trên target đúng.
  - Xcode project diff/ảnh capability được lưu; cài device thật thuộc PLR-125.

### PLR-125 — iOS Now Playing và background QA ⚠️ `[MANUAL:DEVICE-QA]`

- Phụ thuộc: PLR-124.
- Bắt buộc test trên iPhone/iPad thật:
  - Background/lock screen.
  - Control Center và headset/Bluetooth.
  - Seek/±10s/next/previous.
  - Cuộc gọi/Siri interruption.
  - Rút tai nghe.
  - Stop gỡ Now Playing.
  - Khóa màn hình 30 phút.
- Evidence:
  - Device/iOS/build/source audio/timestamp/pass-fail.

### PLR-126 — macOS outbound network entitlements `[NATIVE-CODE]` `[INTEGRATION]`

- Phụ thuộc: PLR-090.
- Files:
  - `macos/Runner/DebugProfile.entitlements`
  - `macos/Runner/Release.entitlements`
- Thực hiện:
  - Thêm `com.apple.security.network.client = true` vào cả hai.
  - Giữ close-last-window kết thúc process trong scope hiện tại.
  - Xác nhận deployment target vẫn tối thiểu macOS 10.15 hoặc cao hơn.
- Kiểm tra:
  - `plutil -lint macos/Runner/DebugProfile.entitlements`.
  - `plutil -lint macos/Runner/Release.entitlements`.
  - Debug và release build.

### PLR-127 — Xác nhận macOS signing/entitlement ⚠️ `[MANUAL:XCODE-MACOS]`

- Phụ thuộc: PLR-126.
- Thao tác tay:
  - Mở target macOS Runner trong Xcode.
  - Xác nhận App Sandbox và Outgoing Connections phù hợp.
  - Xác nhận signed Release chứa network client entitlement.
  - Không tự ý đổi policy close-to-tray/menu bar.
- Evidence:
  - Ảnh Signing & Capabilities và output `codesign -d --entitlements :-` của
    signed Release.

### PLR-128 — macOS Control Center/media keys QA ⚠️ `[MANUAL:DEVICE-QA]`

- Phụ thuộc: PLR-127.
- Test:
  - Now Playing/Control Center.
  - Keyboard media keys.
  - Minimize tiếp tục phát.
  - Đóng cửa sổ cuối kết thúc theo policy.
  - Stop gỡ system card.
- Evidence:
  - macOS/model/build, screenshot Control Center, result media-key/minimize/close
    và pass/fail.

### PLR-129 — Web user gesture và Media Session fallback `[CODE]` `[INTEGRATION]`

- Phụ thuộc: PLR-090, PLR-077.
- Files:
  - `lib/features/player/infrastructure/web_media_session_capabilities.dart`
  - `integration_test/player_web_media_session_test.dart`
- Thực hiện:
  - Lần Play đầu bắt nguồn trực tiếp từ click/tap.
  - Feature-detect Media Session.
  - Không có Media Session vẫn dùng được UI player.
  - Browser chặn autoplay trả về UI paused/available, không playing giả.
- Test:
  - Browser automation bắt buộc cover supported API và injected unsupported
    capability fallback.
  - Không cam kết playback sau đóng tab.

### PLR-130 — Xác nhận CDN/audio/artwork ⚠️ `[MANUAL:EXTERNAL]`

- Phụ thuộc: PLR-129.
- Bắt buộc xác nhận ngoài repository:
  - Audio server hỗ trợ CORS.
  - Server hỗ trợ byte range request.
  - Audio và artwork dùng HTTPS, URL truy cập được từ OS/browser.
  - Nếu cần HTTP/header proxy/caching, chỉ mở network policy tối thiểu theo domain/localhost.
- Evidence:
  - URL test không chứa credential.
  - Request có `Range` nhận `206 Partial Content` và `Content-Range` hợp lệ.
  - CORS headers và browser result.

### PLR-131 — Web browser matrix ⚠️ `[MANUAL:DEVICE-QA]`

- Phụ thuộc: PLR-129, PLR-130.
- Test Chrome, Edge và Safari:
  - Có/không Media Session.
  - Autoplay bị chặn.
  - Tab background.
  - Remote controls khả dụng.
  - Đóng tab kết thúc.
  - Artwork load fail vẫn phát.
- Evidence:
  - Browser/OS/version, Media Session availability, screenshot/devtools log và
    pass/fail cho từng case.

### Gate Phase 10 — Automated platform build

- Phụ thuộc: PLR-120, PLR-121, PLR-123, PLR-126, PLR-129.
- Chạy trên host/CI có toolchain tương ứng:

```bash
flutter build apk --debug
flutter build web
flutter build macos --debug
flutter build ios --debug --no-codesign
```

- Release signed build và system-control behavior vẫn thuộc manual tasks.
- Điều kiện:
  - Platform config source-controlled compile.
  - Android merged manifest có đúng service/receiver/permissions.
  - PLR-089 unit test xác nhận channel ID/name và
    `androidStopForegroundOnPause` trong Dart `AudioServiceConfig`.

## 15. Phase 11 — Integration, reliability và QA release

### PLR-138 — Behavioral core suite với fakes `[CODE]` `[UNIT]` `[WIDGET]`

- Phụ thuộc: Gate Phase 9, Gate Phase 7.
- Files:
  - `test/features/player/behavior/player_core_behavior_test.dart`
- Implement:
  - UI Play/Pause.
  - Remote Pause.
  - Buffering.
  - Seek drag.
- Vì dùng fake engine/gateway và không mở platform channel, đây là automated
  behavioral unit/widget suite, không phải device integration.

### PLR-139 — Race/error/Stop behavioral suite `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-064, PLR-080, PLR-081, PLR-083, PLR-086.
- Files:
  - `test/features/player/behavior/player_reliability_behavior_test.dart`
- Implement:
  - Latest load wins.
  - Stop.
  - Retry order.
  - Completed → Replay.
  - Previous threshold.

### PLR-140 — Navigation/lifecycle behavioral suite `[CODE]` `[WIDGET]`

- Phụ thuộc: PLR-092, PLR-108, PLR-138.
- Files:
  - `test/features/player/behavior/player_lifecycle_behavior_test.dart`
- Implement:
  - Route independence.
  - Background không auto-pause.
  - Remote snapshot trong background và latest restore khi foreground.
  - Stop trong expanded route.

### PLR-141 — Local audio smoke test `[CODE]` `[INTEGRATION]`

- Phụ thuộc: PLR-013, PLR-138 đến PLR-140, Gate Phase 10.
- PLR-013 chỉ cung cấp và xác minh fixture trong asset bundle. PLR-141 là
  acceptance gate cho production adapter load/play fixture trên target thật.
- Files:
  - `integration_test/player_local_smoke_test.dart`
- Test:
  - Load asset.
  - Ready/play/pause/seek/stop.
  - Duration và position hợp lệ.
  - Handler/player chỉ một instance.
- Không dùng network.

### PLR-142 — Rapid command/race suite `[CODE]` `[INTEGRATION]`

- Phụ thuộc: PLR-064, PLR-081, PLR-086.
- Files:
  - `integration_test/player_rapid_commands_test.dart`
- Test:
  - Rapid Play/Pause.
  - Double toggle trước confirmation.
  - Rapid A/B/C switching.
  - Stop trong load.
  - Retry rồi load item mới.
  - Next/Previous trong switching.
- Hoàn thành khi:
  - Không stale metadata, unhandled Future hoặc deadlock.

### PLR-143 — Memory/subscription leak suite `[CODE]` `[INTEGRATION]`

- Phụ thuộc: PLR-087, PLR-108.
- Files:
  - `integration_test/player_lifecycle_leak_test.dart`
- Test:
  - Mở/đóng expanded ít nhất 100 vòng trong harness.
  - Recreate widget/Cubit subscription theo app lifecycle harness.
  - Engine/handler factory creation count vẫn bằng một.
  - Active Cubit/engine subscription counters trở về baseline sau mỗi teardown.
  - Handler/engine dispose counters đúng một ở composition teardown.

### Gate Phase 11 — Automated reliability

- Phụ thuộc: PLR-138 đến PLR-143.
- Chạy:

```bash
flutter test test/features/player/behavior
flutter test integration_test/player_local_smoke_test.dart -d macos
flutter test integration_test/player_rapid_commands_test.dart -d macos
flutter test integration_test/player_lifecycle_leak_test.dart -d macos
```

- Trên CI/device lab, chạy cùng integration targets cho Android/iOS. Web dùng:

```bash
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/player_local_smoke_test.dart \
  -d chrome
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/player_web_media_session_test.dart \
  -d chrome
```

- Nếu toolchain đã chốt dùng runner khác, command thay thế phải được ghi trong
  decision/CI và tạo cùng evidence.
- Điều kiện:
  - Tất cả automated behavior/reliability test pass trước manual device matrix.

### PLR-144 — Android device matrix ⚠️ `[MANUAL:DEVICE-QA]`

- Phụ thuộc: PLR-122, Gate Phase 11.
- Thiết bị/API: 24, 31, 33, 36.
- Chạy checklist chung ở PLR-148 và Android-specific:
  - Foreground service.
  - Notification permission.
  - Lock screen.
  - Swipe recent tasks.
  - Bluetooth/headset.

### PLR-145 — iOS device matrix ⚠️ `[MANUAL:DEVICE-QA]`

- Phụ thuộc: PLR-125, Gate Phase 11.
- Ít nhất một iPhone và một iPad thật.
- Chạy checklist chung ở PLR-148, interruption, route audio và background 30 phút.

### PLR-146 — Web matrix ⚠️ `[MANUAL:DEVICE-QA]`

- Phụ thuộc: PLR-131, Gate Phase 11.
- Chrome, Edge, Safari.
- Ghi rõ browser/OS/version, Media Session support và autoplay result.

### PLR-147 — macOS matrix ⚠️ `[MANUAL:DEVICE-QA]`

- Phụ thuộc: PLR-128, Gate Phase 11.
- Control Center, media keys, minimize, close-last-window và release entitlement.

### PLR-148 — Checklist tích hợp chung ⚠️ `[MANUAL:DEVICE-QA]`

- Phụ thuộc: PLR-144 đến PLR-147.
- Chạy trên mỗi platform:
  1. Play từ UI.
  2. Background/minimize.
  3. Play/Pause từ system controls.
  4. Seek.
  5. Tua ±10 giây.
  6. Next/Previous.
  7. Metadata/artwork/duration.
  8. Buffering.
  9. Track/queue completion và Replay.
  10. Stop làm system card biến mất.
  11. Foreground lại, UI đồng bộ.
  12. Repeat off/one/all và shuffle/effective queue ở boundary.
  13. Initial/runtime/replace failure Retry đúng target/position.
  14. Stop failure không giả idle; Stop lặp sau success không tạo side effect.
- Mobile bổ sung:
  - Lock/unlock.
  - Phone call/audio focus.
  - Rút tai nghe.
  - Bluetooth media buttons.
- Evidence template:

| Platform/device | OS/browser | Build | Audio source | Case | Kết quả | Evidence/bug |
|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |

### PLR-149 — Đo acceptance timing ⚠️ `[MANUAL:DEVICE-QA]`

- Phụ thuộc: PLR-148.
- Đo và ghi:
  - Remote Play/Pause phản ánh UI dưới khoảng 500 ms.
  - UI/system position lệch không quá 1 giây sau seek.
  - UI cadence khoảng 200 ms mà không rebuild artwork/full screen.
  - OS position-only publication khoảng 1 giây; immediate event không bị throttle.
  - Android/iOS lock screen 30 phút ổn định.
- Không đánh dấu pass bằng cảm tính; lưu timestamp/log/video khi cần.

## 16. Phase 12 — Final verification và cập nhật tài liệu

### PLR-180 — Static architecture guard `[CODE]` `[UNIT]`

- Phụ thuộc: PLR-110, Gate Phase 10, Gate Phase 11.
- Files:
  - `test/features/player/architecture/player_architecture_guard_test.dart`
- Thực hiện:
  - Thêm test/lint/script nhỏ nếu cần để phát hiện:
    - `just_audio`/`audio_service` import trong Domain/Presentation.
    - Application import ngược Infrastructure.
    - `AudioPlayer()` ngoài `JustAudioPlaybackEngine`.
    - `AppAudioHandler` implement public `PlaybackGateway`.
    - `Timer` trong PlayerCubit.
    - `PlayerPresentation`.
    - metadata/duration cũ hard-code.
- Hoàn thành khi:
  - Architecture regression có tín hiệu CI rõ.

### PLR-181 — Full automated verification `[CODE]`

- Phụ thuộc: PLR-180, Gate Phase 10, Gate Phase 11.
- Chạy:

```bash
dart format lib test integration_test
flutter analyze
flutter test
```

- Chạy lại toàn bộ commands của Gate Phase 10 và Gate Phase 11 trên target khả
  dụng; CI matrix phải ghi target nào đã chạy, không xem `flutter test` là thay
  thế cho `integration_test`.
- Hoàn thành khi:
  - Tất cả unit/widget/integration test khả dụng pass.
  - Không có analyze error.
  - Android/Web/macOS/iOS no-codesign build pass; signed release thuộc PLR-182.

### PLR-182 — Release configuration audit ⚠️ `[MANUAL:XCODE-IOS]` ⚠️ `[MANUAL:XCODE-MACOS]` ⚠️ `[MANUAL:EXTERNAL]` ⚠️ `[MANUAL:DEVICE-QA]`

- Phụ thuộc: PLR-124, PLR-127, PLR-130, PLR-148, PLR-149, PLR-181.
- Xác nhận lần cuối:
  - iOS Background Modes đúng target và signed Release.
  - macOS network entitlement có trong signed Release.
  - Android merged release manifest đúng.
  - Web CDN/CORS/range và autoplay evidence còn hợp lệ.
- Hoàn thành khi:
  - Không chỉ debug build được kiểm tra.
  - Mỗi platform có signed/release artifact hoặc lý do blocker rõ; task chỉ PASS
    khi không còn blocker.
  - Lưu Xcode capability screenshots, codesign entitlements, Android merged
    manifest và browser/CDN evidence.

### PLR-190 — Đồng bộ ADR và bốn tài liệu projection `[CODE]`

- Phụ thuộc: PLR-181, PLR-182.
- Cập nhật:
  - ADR decision version/status và affected task/test.
  - Behavioral diagrams, class diagram, implementation plan và task ledger theo
    source implementation thực tế.
  - Retry/Stop/completion/input/test seam/bootstrap/error/interruption/Android,
    command matrix, active/pending, effective queue và cadence/provenance.
- Hoàn thành khi:
  - Diagram, class/interface và implementation không mâu thuẫn source thật.
  - `docs/player-architecture-decisions.md` link ngược tới task/test thực tế.

## 17. Mapping về sáu PR gốc

Các nhóm dưới đây là assignment **không chồng lấn**. Có thể tách mỗi hàng thành
nhiều PR nhỏ hơn, nhưng một task không được tính hoàn thành ở hai PR.

| Nhóm | Task trong kế hoạch chi tiết | Gate chính |
|---|---|---|
| Preflight/decisions | PLR-010, PLR-001–009, PLR-014–016, PLR-011–013 | Decision records + dependency/harness xanh |
| PR 1 — Core playback | PLR-019–025, PLR-029–033, PLR-041–042, PLR-048–068 | Gate Phase 4 + handler load/publication core |
| PR 2 — Full commands/Cubit/reliability logic | PLR-034–040, PLR-069–077, PLR-080–088 | Gate Phase 7 |
| PR 3 — Bootstrap và UI migration | PLR-089–092, PLR-100–111 | Gate Phase 9; legacy bridge bị xóa |
| PR 4 — Platform integration | PLR-120–131 | Gate Phase 10 |
| PR 5 — Automated reliability | PLR-138–143 | Gate Phase 11 |
| PR 6 — QA thiết bị thật/release | PLR-144–149, PLR-182 | Manual QA PASS + release evidence |
| Finalization | PLR-180, PLR-181, PLR-190 | Full verification + docs đồng bộ |

Không bắt buộc giữ đúng sáu PR lớn. Khuyến nghị mỗi PR chỉ chứa 3–7 task liền nhau và kết thúc ở trạng thái test xanh.

## 18. Traceability hành vi → task/test

| Hành vi | Task chính |
|---|---|
| Bootstrap/singleton | PLR-060, PLR-090, PLR-091 |
| Initial idle/latest replay | PLR-023, PLR-033, PLR-060 |
| Load/autoplay ordering | PLR-062, PLR-063 |
| Latest load wins | PLR-059, PLR-064, PLR-142 |
| UI Play/Pause + provenance | PLR-035, PLR-042, PLR-070 |
| Remote Play/Pause + provenance | PLR-015, PLR-077 |
| Processing-state transitions | PLR-020, PLR-054, PLR-057, PLR-061, PLR-082 |
| Playing độc lập processing | PLR-057, PLR-070, PLR-082 |
| Position sync/UI cadence | PLR-057, PLR-065, PLR-109 |
| OS timeline cadence | PLR-015, PLR-056, PLR-058, PLR-068 |
| Slider seek | PLR-071, PLR-106 |
| Remote seek | PLR-071, PLR-077 |
| Skip ±10 giây | PLR-051, PLR-071, PLR-073 |
| Next/Previous + shuffle order | PLR-014, PLR-072 |
| Speed/repeat/shuffle | PLR-074, PLR-075, PLR-076 |
| Buffering | PLR-082 |
| Completion/Replay | PLR-002, PLR-083 |
| Error/Retry | PLR-003, PLR-080, PLR-081 |
| Interruption/noisy | PLR-005, PLR-084, PLR-085 |
| Media-session/system-card lifecycle | PLR-055, PLR-056, PLR-066, PLR-070, PLR-086 |
| Queue/current-item lifecycle | PLR-009, PLR-057, PLR-062–064, PLR-072, PLR-080, PLR-083 |
| Command validation/rapid intent | PLR-008, PLR-019, PLR-050, PLR-067, PLR-070–076 |
| Stop/Remote Stop/clear session | PLR-004, PLR-077, PLR-086 |
| Expanded route độc lập | PLR-101, PLR-108 |
| Background/foreground | PLR-092, PLR-122, PLR-125, PLR-128, PLR-131, PLR-140 |
| Duplicate publication suppression | PLR-058, PLR-066 |
| Logging/source provenance | PLR-015, PLR-042, PLR-088 |
| Timing/performance | PLR-065, PLR-068, PLR-109, PLR-149 |
| Platform configuration | PLR-120 đến PLR-131 |

## 19. Danh sách task thủ công tập trung

Đây là danh sách để không bỏ sót task không thể chứng minh chỉ bằng unit test:

- [x] PLR-001 — Input/boundary policy Accepted v1 ngày 2026-08-02. `⚠️ [MANUAL:DECISION]`
- [x] PLR-002 — Completion/auto-advance owner Accepted v1 ngày 2026-08-02. `⚠️ [MANUAL:DECISION]`
- [x] PLR-003 — Retry transaction/interface Accepted v1 ngày 2026-08-02. `⚠️ [MANUAL:DECISION]`
- [x] PLR-004 — Canonical Stop ordering Accepted v1 ngày 2026-08-02. `⚠️ [MANUAL:DECISION]`
- [x] PLR-005 — Interruption/becoming-noisy Accepted v1 ngày 2026-08-02. `⚠️ [MANUAL:DECISION]`
- [x] PLR-006 — Handler test seam Accepted v1 ngày 2026-08-02. `⚠️ [MANUAL:DECISION]`
- [x] PLR-007 — Bootstrap/OS error/Android service Accepted v1 ngày 2026-08-02. `⚠️ [MANUAL:DECISION]`
- [x] PLR-008 — Command-validity/rapid intent Accepted v1 ngày 2026-08-02. `⚠️ [MANUAL:DECISION]`
- [x] PLR-009 — Active/pending load semantics Accepted v1 ngày 2026-08-02. `⚠️ [MANUAL:DECISION]`
- [x] PLR-014 — Queue/shuffle/navigation semantics Accepted v1 ngày 2026-08-02. `⚠️ [MANUAL:DECISION]`
- [x] PLR-015 — OS cadence/logging provenance Accepted v1 ngày 2026-08-02. `⚠️ [MANUAL:DECISION]`
- [x] PLR-016 — Placement/cutover build-green Accepted v1 ngày 2026-08-02. `⚠️ [MANUAL:DECISION]`
- [ ] PLR-122 — Android notification/foreground service trên thiết bị. `⚠️ [MANUAL:DEVICE-QA]`
- [ ] PLR-124 — Bật Background Modes/Audio trong Xcode iOS. `⚠️ [MANUAL:XCODE-IOS]`
- [ ] PLR-125 — iPhone/iPad Now Playing/background/interruption. `⚠️ [MANUAL:DEVICE-QA]`
- [ ] PLR-127 — Xác nhận macOS signing/entitlement trong Xcode. `⚠️ [MANUAL:XCODE-MACOS]`
- [ ] PLR-128 — macOS Control Center/media keys. `⚠️ [MANUAL:DEVICE-QA]`
- [ ] PLR-130 — CDN CORS/range/HTTPS/artwork. `⚠️ [MANUAL:EXTERNAL]`
- [ ] PLR-131 — Chrome/Edge/Safari matrix. `⚠️ [MANUAL:DEVICE-QA]`
- [ ] PLR-144 — Android API matrix. `⚠️ [MANUAL:DEVICE-QA]`
- [ ] PLR-145 — iPhone/iPad matrix. `⚠️ [MANUAL:DEVICE-QA]`
- [ ] PLR-146 — Web matrix. `⚠️ [MANUAL:DEVICE-QA]`
- [ ] PLR-147 — macOS matrix. `⚠️ [MANUAL:DEVICE-QA]`
- [ ] PLR-148 — Checklist tích hợp chung. `⚠️ [MANUAL:DEVICE-QA]`
- [ ] PLR-149 — Đo timing/độ lệch/30 phút. `⚠️ [MANUAL:DEVICE-QA]`
- [ ] PLR-182 — Audit release configuration. `⚠️ [MANUAL:XCODE-IOS]` `⚠️ [MANUAL:XCODE-MACOS]` `⚠️ [MANUAL:EXTERNAL]` `⚠️ [MANUAL:DEVICE-QA]`

Lưu ý:

- PLR-123 sửa `Info.plist` là `[NATIVE-CODE]`; PLR-124 mới là thao tác Xcode bắt buộc.
- PLR-126 sửa entitlement là `[NATIVE-CODE]`; PLR-127 xác nhận signing/capability trong Xcode là manual.
- `AudioService.init(...)` và `AudioSession.configure(...)` là code, không phải cấu hình Xcode.

## 20. Release Definition of Done

- [ ] Chỉ có một audio stream, một `JustAudioPlaybackEngine`/`AudioPlayer`, một handler và một media session.
- [ ] Mini player, expanded player và system controls dùng cùng current item/state.
- [ ] UI/OS commands hội tụ cùng handler operation.
- [ ] Không có optimistic playing/progress trong Cubit/UI.
- [ ] Không còn metadata/duration/progress mô phỏng.
- [ ] Buffering giữ đúng play intent.
- [ ] Latest load wins và stale error không lộ ra UI/OS.
- [ ] Retry đúng target và thứ tự load → seek → commit → conditional Play; Pause/Stop/load/navigation mới thắng retry.
- [ ] Completed cuối repeat off là `playing=false`; Replay seek zero trước Play.
- [ ] Stop barrier không lộ state trung gian; success clear session, failure giữ session, Stop lặp idempotent và handler vẫn reusable.
- [ ] Route push/pop không gửi playback command.
- [ ] Unit/widget/integration tests pass.
- [ ] `flutter analyze` không lỗi.
- [ ] Gate Phase 10 và Gate Phase 11 pass trên matrix đã chốt.
- [ ] Android/iOS background và system controls đã kiểm tra trên thiết bị thật.
- [ ] Web fallback hoạt động khi không có Media Session.
- [ ] macOS Control Center/media keys và entitlement đã kiểm tra.
- [ ] PLR-149 đạt dưới khoảng 500 ms cho remote state, lệch không quá 1 giây sau
      seek và lock-screen 30 phút ổn định.
- [ ] Tất cả task manual ở trạng thái PASS, có evidence và không còn blocker mở.
- [ ] PLR-181, PLR-182 và PLR-190 hoàn thành.
- [ ] ADR và bốn projection Player đã đồng bộ với implementation.

## 21. Nhật ký rà soát tài liệu kế hoạch

Phần này ghi nhận các lượt rà soát kế hoạch và contract:

- [x] Rà soát lần 1 — Độ phủ yêu cầu và traceability — PASS ngày 2026-07-26.
- [x] Rà soát lần 2 — Kích thước task, dependency, unit-testability và
      acceptance criteria — PASS ngày 2026-07-26.
- [x] Rà soát lần 3 — Nhãn manual/Xcode/native, tính nhất quán, link và định
      dạng — PASS ngày 2026-07-26.
- [x] Rà soát lần 4 — ADR normative, behavioral/class/plan/task consistency và
      acceptance oracle — PASS ngày 2026-08-02.

Các lỗi phát hiện qua lịch sử rà soát và đã được đóng ở lần 4, gồm:

- Dependency vòng/impossible-to-compile của typed test fixture.
- Migration cutover làm app mất build xanh.
- Handler thiếu engine/clock/publication test seam.
- Remote Stop và app lifecycle thiếu dependency/test.
- Policy command/load/retry/shuffle/Stop/logging trước đây chưa khóa; nay đã
  Accepted v1 tại PLR-001–009 và PLR-014–016.
- Gateway/Handler/Engine ownership, completed playing state, Retry ordering,
  Stop failure/barrier, active/pending context và OS cadence từng khác nhau giữa
  các projection.
- ID task hỏng, mapping PR chồng lấn và integration gate thiếu Web.
- Nhãn/evidence manual Xcode/native/external/release chưa đầy đủ.
