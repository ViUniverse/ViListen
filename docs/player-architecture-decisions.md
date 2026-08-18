# Player Architecture Decisions

> Trạng thái: Normative contract ledger cho Player v1<br>
> Cập nhật gần nhất: 2026-08-19<br>
> Owner: Player team

## 1. Quy tắc sử dụng tài liệu

- Tài liệu này là nguồn sự thật normative cho policy, ownership, ordering và
  error semantics của Player.
- `player-class-diagram.md` mô tả structure/interface/ownership; không tự tạo
  policy khác decision record.
- `player-behavioral-diagrams.md` minh họa các contract đã chốt; diagram không
  được xem là nguồn của một behavior mới.
- `player-implementation-plan.md` mô tả cách hiện thực contract.
- `player-detailed-implementation-tasks.md` chia contract thành task và test
  oracle; task không được nới hoặc thay đổi decision ngầm.
- Nếu các tài liệu mâu thuẫn, decision record này được ưu tiên để xác định ý
  định, nhưng mâu thuẫn phải được sửa trong cùng change set; không chờ PLR-190.
- Mỗi decision `Accepted` chỉ được sửa bằng một revision mới có ngày, lý do và
  cập nhật đồng thời mọi projection bị ảnh hưởng.

## 2. Decision index

| Decision | Status | Version | Chủ đề |
|---|---|---:|---|
| PLR-001 | Accepted | 1 | Input, boundary, constants, extras và URI |
| PLR-002 | Accepted | 1 | Completion, repeat, auto-advance và Replay |
| PLR-003 | Accepted | 1 | Atomic Retry và retry context |
| PLR-004 | Accepted | 1 | Canonical Stop transaction |
| PLR-005 | Accepted | 1 | Interruption và becoming-noisy |
| PLR-006 | Accepted | 4 | Handler test seam và adapter boundary |
| PLR-007 | Accepted | 2 | Bootstrap, OS error và Android service |
| PLR-008 | Accepted | 1 | Command-validity và rapid intent |
| PLR-009 | Accepted | 1 | Active/pending load và replace failure |
| PLR-014 | Accepted | 1 | Queue, shuffle và manual navigation |
| PLR-015 | Accepted | 1 | Timeline cadence và logging provenance |
| PLR-016 | Accepted | 1 | Layer placement và migration cutover |

---

## PLR-001 / 2026-08-02 / Owner: Player team

**Status:** Accepted<br>
**Decision version:** 1

### Context

Player cần một contract duy nhất cho validation, boundary values, command
constants, speed, `PlayerItem.extras` và source URI. Các rule này phải cho kết
quả giống nhau trên UI, Gateway, handler và test, không phụ thuộc default ngầm
của plugin hoặc platform.

### Decision

#### Input và boundary

| Topic | Canonical decision | Runtime owner | Target file |
|---|---|---|---|
| Empty queue | Trả `PlayerCommandFailure.emptyQueue`; không gọi engine, không mutate snapshot | Queue validator | `infrastructure/player_policies.dart` |
| Invalid initial index | Reject nếu `< 0` hoặc `>= queue.length` bằng `initialIndexOutOfRange`; không clamp | Queue validator | `infrastructure/player_policies.dart` |
| Duplicate ID | Duplicate `PlayerItem.id` trong cùng queue bị reject bằng `duplicateItemId` | Queue validator | `infrastructure/player_policies.dart` |
| Unknown duration | Domain dùng `Duration.zero` | Snapshot reducer | `infrastructure/playback_snapshot_reducer.dart` |
| Seek khi duration zero | UI disable; Gateway vẫn trả `seekUnavailableUnknownDuration`; engine không được gọi | UI + position validator | `presentation/**`, `infrastructure/playback_position_policy.dart` |
| Skip interval | `const Duration(seconds: 10)` | Application policy | `application/player_command_policies.dart` |
| Previous threshold | `const Duration(seconds: 3)` | Application policy | `application/player_command_policies.dart` |
| Previous boundary | `position > 3s` restart current; `position <= 3s` điều hướng previous theo PLR-014 | Position policy | `infrastructure/playback_position_policy.dart` |
| UI speed presets | `0.5`, `0.75`, `1.0`, `1.25`, `1.5`, `1.75`, `2.0` | Application policy | `application/player_command_policies.dart` |
| Gateway speed range | Mọi `double` hữu hạn trong miền đóng `[0.5, 2.0]`; UI preset không giới hạn caller khác | Application speed policy | `application/player_command_policies.dart` |
| Invalid speed | Reject `NaN`, infinity, `< 0.5` hoặc `> 2.0` bằng `invalidSpeed`; không gọi engine | Infrastructure command handler | `infrastructure/app_audio_handler.dart` |
| Invalid programmer input | Queue/URI input hoàn tất bằng typed `PlayerCommandFailure`; extras lỗi bị reject khi tạo `PlayerItem`; không tạo `PlayerFailure` và không mutate snapshot | Command/domain boundary | `domain/player_command_failure.dart` |
| Valid source load failure | Normalize thành `PlayerFailure` | Failure mapper | `infrastructure/player_failure_mapper.dart` |

`PlayerCommandFailure.code` tối thiểu gồm:

```text
emptyQueue
initialIndexOutOfRange
duplicateItemId
unsupportedUriScheme
invalidExtras  # raw-input boundary only; not loadQueue(List<PlayerItem>)
seekUnavailableUnknownDuration
invalidSpeed
noCurrentItem
retryUnavailable
commandUnavailable
```

#### `PlayerItem.extras`

Public type là `Map<String, Object?>`. Value hợp lệ được định nghĩa đệ quy:

```text
null
bool
int
finite double
String
Uri
Duration
List<Object?>
Map<String, Object?>
```

- Reject `Set`, custom object, map key không phải `String`, non-finite `double`
  và cyclic list/map tại `PlayerItem` construction boundary.
- Constructor và `copyWith` deep-copy toàn bộ list/map, sau đó wrap recursively
  thành collection không thể mutate.
- Getter chỉ expose immutable graph đã copy; không có nhánh "copy nếu cần".
- List equality phụ thuộc thứ tự; map equality không phụ thuộc thứ tự insert.
- Hash code phải tuân cùng deep-equality policy.
- `PlaybackGateway.loadQueue()` nhận `List<PlayerItem>` đã được khởi tạo, nên
  extras lỗi không thể phát sinh tại queue boundary dưới contract hiện tại.
  `invalidExtras` vẫn là mã reserved cho một raw-input boundary trong tương lai;
  không dùng nó làm oracle cho `loadQueue(List<PlayerItem>)`.

#### Source URI matrix

| Scheme | Android | iOS | macOS | Web | Mapping |
|---|---:|---:|---:|---:|---|
| `https` | Có | Có | Có | Có | `AudioSource.uri` |
| `asset` | Có | Có | Có | Có | Adapter map rõ sang asset source; không fetch network |
| `file` | Có | Có | Có | Không | Native file source |
| `http` | Không | Không | Không | Không | Reject trong Player v1 |
| Scheme khác/rỗng | Không | Không | Không | Không | Reject trước engine call |

- Asset URI phải normalized theo một format duy nhất, ví dụ
  `asset:///assets/test_audio/player_fixture_2s.wav`.
- `artUri` chấp nhận `https` trên mọi platform và `file` trên native; từ chối
  `asset`, `http`, scheme khác/rỗng. Validator chạy trước MediaItem publication.
- Source URI matrix trên áp dụng cho `audioUri`; artwork policy không được dùng
  để nới audio source policy hoặc ngược lại.
- Nếu tương lai cần HTTP localhost, signed URL đặc biệt hoặc header proxy, mở
  decision mới cùng network-security policy; không nới validator ngầm.

### Alternatives rejected

- Clamp index hoặc seek unknown-duration: che giấu caller bug và tạo oracle mơ hồ.
- Dùng miền speed của engine: engine/platform không tạo cross-platform contract
  ổn định.
- Chấp nhận mutable/arbitrary `extras`: phá value equality và snapshot
  immutability.
- Chỉ validate URI tại engine: phân loại lỗi muộn và platform-dependent.

### Affected contracts/files

- `docs/player-behavioral-diagrams.md`
- `docs/player-class-diagram.md`
- `docs/player-implementation-plan.md`
- `docs/player-detailed-implementation-tasks.md`
- PLR-019, PLR-022, PLR-041, PLR-050, PLR-051, PLR-071 và PLR-074.

### Test oracle

- Mỗi invalid input trả đúng failure code, engine call count bằng zero và latest
  snapshot không đổi.
- Duration unknown publish `Duration.zero`; UI seek disabled và direct Gateway
  seek vẫn bị reject.
- Boundary đúng tại `3s`, `10s`, `0.5x`, `2.0x`, `NaN` và infinity.
- Mutate input extras sau constructor không đổi item; mọi collection expose ra
  không mutate được; nested equality/hash nhất quán; domain test bao phủ Set,
  non-string key, direct/nested cycle, NaN và cả hai infinity.
- Mỗi URI scheme/platform đi đúng nhánh matrix trước khi mapper gọi engine.

---

## PLR-002 / 2026-08-02 / Owner: Player team

**Status:** Accepted<br>
**Decision version:** 1

### Context

Engine sequence có thể tự chuyển item và tự áp dụng loop mode. Nếu handler cũng
seek khi nhận completion, một lần completed có thể nhảy hai item. Đồng thời
`just_audio` giữ `playing=true` khi tới cuối, trong khi UI/OS cần một Replay
contract không mơ hồ.

### Decision

- Engine sequence/loop mode là owner duy nhất của auto-advance, repeat-one và
  repeat-all.
- Handler không gọi seek/replay thủ công cho completion giữa queue hoặc completion
  do repeat mode xử lý.
- Handler chỉ quan sát `currentIndexStream`, effective sequence, player state và
  option streams để publish item/index/state mới.
- Khi engine tự chuyển N → N+1, handler publish đúng một item/index transition và
  không phát command navigation thứ hai.
- `Repeat one` và `repeat all` không có exception path ở handler.
- Tại item cuối với repeat off, handler thực hiện một end-normalization duy nhất:
  1. xác nhận current request/index vẫn active và chưa normalize;
  2. gọi `pause()` đúng một lần nếu engine còn `playing=true`;
  3. giữ item/index/queue/position/duration;
  4. publish Domain và OS state `completed × playing=false`.
- End-normalization là state normalization, không phải ownership auto-navigation.
- Main action ở completed là Replay. Replay dùng canonical transaction
  `seek(Duration.zero, currentIndex) → play()`; không clear media session.
- UI/OS chọn Replay/Play theo `isCompleted`, không suy ra chỉ từ `playing`.
- Explicit Next/Previous vẫn đi qua handler operation và tuân effective order,
  boundary, repeat semantics tại PLR-014.
- Repeat-one chỉ chi phối auto-completion; explicit Next không bị giữ ở current
  item nếu có next item.

### Alternatives rejected

- Handler sở hữu toàn bộ completion/repeat: tăng race và double-advance.
- Giữ native `completed × playing=true` nhưng vẫn dùng `seek → play`: tạo lệnh
  Play thừa và khiến UI/OS khó chọn Play/Pause.
- Handler seek thủ công riêng cho repeat one/all: hybrid ownership khó test.

### Affected contracts/files

- Completion sequence/state machine trong behavioral diagrams.
- Processing/play-intent contract trong implementation plan.
- State ownership và handler operations trong class diagram.
- PLR-054, PLR-055, PLR-069, PLR-072, PLR-075 và PLR-083.

### Test oracle

- Auto-completion N → N+1 chỉ đổi index một lần, handler navigation call count
  bằng zero.
- Repeat one/all không tạo manual seek/pause/replay từ completion path.
- Final repeat-off gọi Pause tối đa một lần và publish
  `completed × playing=false` với item cuối còn nguyên.
- Replay call order là seek → play; mỗi engine call đúng một lần.
- Explicit Next ở repeat-one chuyển item nếu có next.
- Domain queue/index/item và OS queueIndex luôn khớp engine effective state.

---

## PLR-003 / 2026-08-02 / Owner: Player team

**Status:** Accepted<br>
**Decision version:** 1

### Context

Retry phải khôi phục đúng transaction lỗi. "Queue hợp lệ cuối cùng" không đủ để
phân biệt runtime failure của active A với replace A → B thất bại. Retry cũng
phải tôn trọng Play/Pause/Stop mới xảy ra khi reload đang pending.

### Decision

- `PlaybackGateway` expose first-class command `Future<void> retry()`.
- `PlayerCubit.retry()` chỉ delegate; không tự ghép load/seek/play.
- Handler giữ immutable internal `RetryContext`:

```text
targetQueue
targetIndex
restorePosition
desiredPlaying
failureGeneration
failureItemId
```

- Context theo loại failure:
  - runtime failure của active A: target A, last valid position và desired intent
    trước failure;
  - initial load B failure: target B, position zero và autoplay intent của request;
  - replace A → B failure: outward active vẫn là A, nhưng target Retry là B,
    position zero và autoplay intent của request B.
- Retry chỉ hợp lệ cho recoverable failure có context còn current. Trường hợp
  khác trả `PlayerCommandFailure.retryUnavailable`; không no-op và không gọi
  engine.
- Retry transaction dùng publication barrier:
  1. tạo generation mới, invalidate load/retry cũ;
  2. load target với `autoplay=false`;
  3. kiểm tra generation còn latest;
  4. đọc duration mới và clamp restore position;
  5. seek restore position;
  6. kiểm tra generation lần nữa;
  7. atomic commit queue/item/index/snapshot rồi publish metadata/queue/ready;
  8. nếu latest `desiredPlaying=true`, gọi Play đúng một lần;
  9. chỉ publish playing khi engine stream xác nhận.
- Không publish target retry như active item tại position zero trước khi restore.
- Trong retry pending:
  - Pause đổi `desiredPlaying=false`; reload có thể tiếp tục nhưng không Play sau
    commit;
  - Play đổi `desiredPlaying=true`;
  - Stop, load mới hoặc source-navigation mới invalidate retry;
  - stale success/error không mutate active/pending/current snapshot.
- Retry thất bại lần nữa publish failure mới cho cùng target và thay context bằng
  generation mới; không auto-loop/backoff.

### Alternatives rejected

- UI gọi lại `loadQueue`: làm mất target/position/intent và orchestration bị lặp.
- Retry active item trong mọi trường hợp: sai với pending replacement failure.
- Commit trước seek: UI/OS thấy target ở position zero rồi nhảy vị trí.
- Freeze play intent trước lỗi: có thể tự phát sau khi user đã Pause.
- `retry()` no-op khi context thiếu: che command bug và không observable.

### Affected contracts/files

- `PlaybackGateway`, `UiPlaybackCommandTarget`, adapter và test doubles.
- Error/Retry behavioral sequence.
- PLR-030, PLR-039, PLR-059, PLR-067, PLR-080, PLR-081 và PLR-142.

### Test oracle

- Initial, active-runtime và replace-pending failure tạo đúng Retry target.
- Call order là load → seek → commit/publication → conditional Play.
- Prior playing Play đúng một lần; prior paused không Play.
- Pause trong pending retry thắng saved intent; Stop/load/navigation invalidate.
- Stale retry không publish metadata, snapshot hoặc failure.
- No context/non-recoverable trả `retryUnavailable`, engine call count zero.

---

## PLR-004 / 2026-08-02 / Owner: Player team

**Status:** Accepted<br>
**Decision version:** 1

### Context

Stop phải clear engine/session/domain atomically, không để engine events trong
lúc `AudioPlayer.stop()` tạo snapshot trung gian hoặc late request hồi sinh
state. Stop failure cũng không được publish idle giả khi engine chưa xác nhận
dừng.

### Decision

#### Success path

1. Enter internal stopping publication barrier.
2. Tăng command/source epoch và invalidate load, retry, source navigation và
   seek cũ.
3. Serialize với mọi command có thể thay playback graph.
4. Await `AudioPlayer.stop()`.
5. Reset engine options về speed `1.0`, repeat off và shuffle false.
6. Atomically replace toàn bộ internal state bằng canonical
   `PlaybackSnapshot.idle`; clear active, pending, retry, failure và navigation
   contexts.
7. Publish `mediaItem=null`.
8. Publish queue rỗng.
9. Publish OS `processingState=idle`, `playing=false`, controls/actions rỗng,
   position/buffer zero, speed `1.0`, repeat off, shuffle false và queueIndex null.
10. Emit đúng một Domain idle snapshot.
11. Release publication barrier.

- Engine events phát trong barrier có thể cập nhật recorder nội bộ nhưng không
  được publish outward. Event thuộc epoch/source cũ bị bỏ sau barrier.
- Nếu một engine option reset thất bại sau khi engine đã Stop, cleanup outward
  vẫn hoàn tất; lỗi được log. Load tiếp theo bắt buộc reapply baseline options và
  nhận engine confirmation trước Ready.
- Stop không dispose handler/engine. Handler vẫn load queue mới được.

#### Idempotence

- Nếu handler đã canonical idle và không có pending transaction, Stop là no-op:
  không gọi engine, không republish và không tạo navigation reaction mới.
- Nếu Stop trước thất bại, Stop tiếp theo được phép retry engine Stop.

#### Stop failure

- Nếu `AudioPlayer.stop()` throw hoặc không xác nhận Stop, không publish idle giả.
- Generation vẫn bị invalidate, nhưng active metadata/queue/system card được giữ.
- Publish normalized non-recoverable `stopFailed` error với `playing` lấy từ
  engine-confirmed state gần nhất; command Future thất bại.
- Expanded route không pop; user có thể thử Stop lại hoặc app chuyển degraded
  unavailable theo PLR-007 nếu engine không còn dùng được.

#### Navigation reaction

- Sau successful idle snapshot, expanded player route chỉ pop một lần nếu route
  player vẫn top-most.
- Không pop route khác và không gửi thêm Stop/Pause từ navigation cleanup.

### Alternatives rejected

- Publish idle dù engine Stop thất bại: che audio có thể vẫn phát.
- Incrementally clear item rồi queue: tạo tuple state không nhất quán.
- Dispose singleton khi Stop: biến command thành process teardown.
- Republish idle ở mọi Stop lặp: tạo duplicate route/system side effects.

### Affected contracts/files

- Stop sequence/activity/ordering/Gherkin trong behavioral diagrams.
- Handler lifecycle và publication ownership trong class diagram.
- PLR-036, PLR-059, PLR-067, PLR-086, PLR-108 và PLR-139.

### Test oracle

- Recorder thấy đúng success ordering và đúng một Domain idle snapshot.
- Không có outward snapshot trung gian trong stopping barrier.
- Late load/retry/seek/navigation không hồi sinh state.
- Second Stop sau success có engine/publication call count bằng zero.
- Stop failure giữ metadata/session, không pop route và expose `stopFailed`.
- Load mới sau successful Stop reapply baseline options trước Ready.

---

## PLR-005 / 2026-08-02 / Owner: Player team

**Status:** Accepted<br>
**Decision version:** 1

### Context

Nếu `just_audio` và app cùng listen interruption/becoming-noisy để gọi Pause hoặc
Play, một OS event có thể tạo hai command và auto-resume trái user intent.

### Decision

- Composition root cấu hình `AudioSessionConfiguration.speech()` sau khi các
  audio plugin đã được khởi tạo.
- Production `JustAudioPlaybackEngine` bật runtime interruption handling của
  `just_audio`; đây là owner duy nhất gọi engine Pause/Play cho OS interruption
  và becoming-noisy.
- App/handler chỉ passive-observe normalized interruption events cho logging và
  eligibility bookkeeping; passive observer không gọi engine Pause/Play.
- Temporary interruption chỉ được auto-resume khi engine xác định playback đang
  active trước interruption và user không phát Pause/Stop/source intent mới.
- User Pause trong interruption xóa resume eligibility; Play mới của user là
  intent mới, không phải continuation của auto-resume cũ.
- Becoming-noisy luôn dẫn đến Pause và luôn xóa resume eligibility. Route audio
  quay lại hoặc tai nghe được cắm lại không tự Play.
- Một interruption/noisy event tạo tối đa một engine Pause.

### Alternatives rejected

- Listener app thứ hai gọi Pause/Play: double command và race.
- Auto-resume sau becoming-noisy: có nguy cơ phát loa ngoài ngoài ý muốn.
- App tự quản toàn bộ audio focus cross-platform: trùng trách nhiệm plugin.

### Affected contracts/files

- Interruption/noisy behavioral sequences.
- Engine adapter, bootstrap và logging contracts.
- PLR-084, PLR-085, PLR-090, PLR-125, PLR-145 và PLR-148.

### Test oracle

- Fake normalized event chứng minh app listener không gọi engine.
- Temporary interruption + prior playing có tối đa một Pause và một permitted
  resume từ engine owner.
- User Pause/Stop trong interruption chặn resume.
- Becoming-noisy không bao giờ tạo Play khi route trở lại.

---

## PLR-006 / 2026-08-02 / Owner: Player team

**Status:** Accepted<br>
**Decision version:** 4<br>
**Revision date:** 2026-08-10<br>
**Revision reason:** Bổ sung engine interrupt handshake cho latest-load-wins,
cập nhật test seam/affected contracts của PLR-062 và khóa guarantee prepare-only
ở trạng thái paused cho replacement load.

### Context

Race, ordering và publication policy phải unit test được không cần platform
plugin. Đồng thời Application không được phụ thuộc concrete BaseAudioHandler.

### Decision

- `PlaybackGateway` tại Application là public boundary duy nhất Cubit biết.
- `UiPlaybackGatewayAdapter implements PlaybackGateway` tại Infrastructure.
- Adapter nhận internal `UiPlaybackCommandTarget`; mọi UI command forward cùng
  `CommandSource.ui`.
- `AppAudioHandler` extends `BaseAudioHandler`, mix `QueueHandler`/`SeekHandler`
  và implements internal `UiPlaybackCommandTarget`; handler không implement
  public `PlaybackGateway`.
- OS overrides gọi cùng internal operation với `CommandSource.systemRemote` mà
  không đi qua Cubit hoặc UI adapter.
- Internal `PlaybackEngine` port chỉ expose streams/commands handler thực sự cần.
- Contract engine/clock được khóa tại PLR-048:
  - `load(sources, initialIndex)` phải pause source đang phát trước khi thay
    source, chỉ chuẩn bị nguồn và chờ load hoàn tất với engine ở trạng thái
    paused; không autoplay. Handler giữ autoplay trong pending context và chỉ
    gọi `play()` sau commit/publication theo PLR-063.
  - `interruptLoad()` là engine-level cancellation handshake cho load đang chờ;
    adapter phải yêu cầu engine dừng/cancel transaction hiện tại và chỉ hoàn tất
    handshake sau khi graph lane có thể chuyển sang load mới. Đây là thao tác nội
    bộ thay source, không phải canonical user Stop và không tự tạo outward idle
    publication.
  - Khi `interruptLoad()` làm load Future cũ kết thúc bằng stale/interrupted
    result, handler phải hấp thụ result đó theo generation guard; load mới không
    được chờ vô hạn vào Future cũ.
  - `effectiveSequenceStream` phát `List<int>` theo logical index; `errorStream`
    phát lỗi engine để failure mapper xử lý ở Infrastructure.
  - `PlayerClock` chỉ expose `ticks`, `elapsed` và `dispose`; fake clock advance
    đồng bộ, không dùng wall clock.
  - Recorder engine call có thể không có provenance; `source` nullable ở engine
    boundary và bắt buộc khi ghi nhận operation của handler.
- `JustAudioPlaybackEngine` là production adapter duy nhất tạo và sở hữu đúng một
  `just_audio.AudioPlayer`.
- `AppAudioHandler.production()` tạo đúng một production engine adapter; test
  constructor inject `FakePlaybackEngine`, `PlayerClock`, logger và recorder.
- Position cadence dùng injectable `PlayerClock`; unit tests không sleep/wall
  clock.
- `mediaItem`, `queue`, `playbackState` của handler là publication seam cho test;
  không tạo publisher global thứ hai.
- Pure collaborators: validators, reducer, mappers, generation/epoch guard,
  publication diff, timeline projector và command coordinator.
- Không mock `AudioPlayer` xuyên Application/Presentation.

### Alternatives rejected

- Handler trực tiếp implement Gateway: mất provenance UI/OS và leak concrete
  infrastructure boundary.
- Mock plugin object toàn app: brittle, vẫn phụ thuộc platform setup.
- Tạo một engine riêng cho test/integration fallback: phá singleton invariant.

### Affected contracts/files

- `application/playback_gateway.dart`
- `infrastructure/ui_playback_command_target.dart`
- `infrastructure/ui_playback_gateway_adapter.dart`
- `infrastructure/app_audio_handler.dart`
- `infrastructure/engine/playback_engine.dart`
- `infrastructure/engine/just_audio_playback_engine.dart`
- `infrastructure/playback_contexts.dart`
- `test/features/player/support/fake_playback_engine.dart`
- PLR-030, PLR-042, PLR-048, PLR-060, PLR-061, PLR-062, PLR-067 và PLR-090.

### Test oracle

- Cubit compile/run chỉ với Fake Gateway.
- UI adapter forward mọi argument và source `ui` đúng một lần.
- OS override và UI command hội tụ cùng internal operation nhưng khác source.
- Production factory count chứng minh đúng một engine/AudioPlayer.
- Race/cadence tests dùng fake engine/clock, không mở platform channel.
- Pending load A → load B gọi đúng một interrupt handshake; B bắt đầu mà không
  chờ vô hạn vào Future A, và stale A không tạo outward snapshot.

---

## PLR-007 / 2026-08-02 / Owner: Player team

**Status:** Accepted<br>
**Decision version:** 2<br>
**Revision date:** 2026-08-19<br>
**Revision reason:** Tách rõ failure trước và sau handler builder; chấp thuận
production fallback `UnavailablePlaybackGateway` cho cả failure tại
`WidgetsFlutterBinding.ensureInitialized()`, và cập nhật các projection
bootstrap/error liên quan.<br>
**Revision status:** Accepted<br>
**Revision approved:** 2026-08-19 / Player team

### Context

Bootstrap/service/error lifecycle cần behavior deterministic trên development,
production và Android background; tuyệt đối không tạo player thứ hai làm fallback.

### Decision

#### Bootstrap

- Failure trước khi `AudioService.init` gọi handler builder:
  - development/test fail-fast và giữ original stack trace;
  - production tạo `UnavailablePlaybackGateway` không sở hữu engine, replay một
    snapshot `processingState=error` với
    `PlayerFailure(code: bootstrapUnavailable, isRecoverable: false)`;
  - UI hiển thị player unavailable; mọi playback command trả typed
    `commandUnavailable`.
- Failure sau khi handler builder đã được gọi, bao gồm handler/player creation
  failure và `AudioSession.configure` failure, luôn fail-fast và giữ original
  stack trace ở mọi mode. Không `runApp`, không retry và không tạo playback
  stack thứ hai.

#### OS error mapping

- OS dùng `AudioProcessingState.error`, sanitized error message và stable integer
  error code. Load/runtime/bootstrap errors publish `playing=false`; riêng
  `stopFailed` giữ engine-confirmed `playing` gần nhất theo PLR-004 vì engine có
  thể vẫn đang phát:

| Domain failure | OS error code |
|---|---:|
| network/load | 1001 |
| source not found | 1002 |
| unsupported format | 1003 |
| audio output | 1004 |
| stop failed | 1005 |
| unknown engine failure | 1099 |
| bootstrap unavailable | 1100 |

- Không đưa exception, stack trace, credential hoặc raw signed URL vào OS state.
- Error giữ/clear metadata theo active/pending policy PLR-009.

#### Android service

- Player v1 đặt explicit
  `AudioServiceConfig.androidStopForegroundOnPause = false`.
- Pause giữ foreground service và system notification/card; explicit Stop mới
  publish idle và gỡ card.
- Swipe app khỏi recent tasks không tự gửi Stop. Nếu service/process còn sống,
  playback/session tiếp tục theo OS.
- Player v1 không persist queue để tự phục hồi sau process death. Bootstrap mới
  sau process death bắt đầu canonical idle; không tự phát.
- QA Android 12+ phải xác nhận pause dài, notification, media button, swipe
  recent tasks và explicit Stop.

### Alternatives rejected

- Fallback AudioPlayer: phá invariant một player/session.
- Production fallback sau khi handler/player đã tồn tại: bị loại vì không thể
  đáp ứng single-stack invariant; pre-handler failure vẫn degrade qua
  `UnavailablePlaybackGateway`.
- Dùng default `androidStopForegroundOnPause` ngầm: behavior có thể đổi theo
  dependency và khó audit.
- Auto-restore/play sau process death ở v1: cần persistence/security policy riêng.

### Affected contracts/files

- Bootstrap, error và Android lifecycle diagrams/plan.
- `player_audio_service_config.dart`, `player_bootstrap.dart`, failure mapper.
- PLR-056, PLR-080, PLR-089, PLR-090, PLR-122 và PLR-144.

### Test oracle

- Pre-handler dev bootstrap error rethrow; pre-handler production fallback tạo
  unavailable Gateway với engine creation count zero.
- Post-handler failure rethrow và không tạo handler/player thứ hai.
- Mỗi error category map đúng processing/error code/message sanitization.
- Config test assert `androidStopForegroundOnPause == false`.
- Pause không gỡ card; Stop gỡ card; device QA lưu Android/API/evidence.

---

## PLR-008 / 2026-08-02 / Owner: Player team

**Status:** Accepted<br>
**Decision version:** 1

### Context

Command cần kết quả xác định ở idle/loading/ready/buffering/completed/error và
khi nhiều intent đến trước engine confirmation.

### Decision

#### Command-validity matrix

| Command | Idle/no item | Loading/retry pending | Ready/buffering | Completed | Error |
|---|---|---|---|---|---|
| Valid `loadQueue` | Execute | Replace; latest wins | Replace | Replace | Replace |
| Play | `noCurrentItem` | Set desired Play; không optimistic state | Execute hoặc idempotent no-op nếu desired Play đã pending/confirmed | Execute Replay PLR-002 | `commandUnavailable`; dùng Retry/load |
| Pause | Idempotent no-op | Set desired Pause; không cần engine Pause nếu autoplay off | Execute hoặc idempotent no-op nếu đã Pause | Idempotent no-op | Idempotent no-op và clear pending resume intent |
| Stop | Idempotent no-op | Execute PLR-004 | Execute PLR-004 | Execute PLR-004 | Execute PLR-004 |
| Seek/skip | `noCurrentItem` | `commandUnavailable` | Execute nếu duration > 0, ngược lại PLR-001 failure | Execute seek; state chỉ đổi theo engine | `commandUnavailable` |
| Next/Previous | `noCurrentItem` | Invalidate pending load rồi execute trên committed active queue nếu target hợp lệ; nếu không có active item thì `commandUnavailable` | Execute/no-op boundary theo PLR-014 | Execute/no-op boundary theo PLR-014 | `commandUnavailable` |
| Speed/repeat/shuffle | `noCurrentItem` | Update desired option và apply trước commit; snapshot chỉ đổi sau engine confirm | Execute/coalesce | Execute/coalesce | `commandUnavailable` |
| Retry | `retryUnavailable` | Coalesce cùng retry target hoặc replace bằng explicit new retry generation | `retryUnavailable` | `retryUnavailable` | Execute chỉ khi recoverable context valid |

- Typed failure luôn hoàn tất Future bằng `PlayerCommandFailure`; không mutate
  playback snapshot và không tạo engine error snapshot.
- Boundary Next/Previous trên một queue hợp lệ là idempotent no-op, không phải
  failure; empty/no committed queue vẫn là typed failure.

#### Rapid intent

- Direct Play/Pause biểu diễn desired state, được coordinator serialize/coalesce.
- Hai Play pending tạo tối đa một engine Play; hai Pause tương tự.
- Play → Pause và Pause → Play dùng last desired intent wins.
- `PlayerCubit.togglePlayback()` giữ private `_pendingDesiredPlaying` chỉ để route
  command, không expose trong `PlayerState` và không đổi icon optimistically:
  - nếu pending intent tồn tại, Toggle đảo pending intent;
  - nếu không, Toggle đảo confirmed snapshot.playing;
  - confirmed engine snapshot hoặc command failure clear/reconcile pending intent.
- Coordinator không giữ source lock khi chỉ xử lý position event.

### Alternatives rejected

- Toggle liên tiếp chỉ đọc confirmed snapshot: hai tap nhanh có thể cùng thành
  Play thay vì Play → Pause.
- Optimistic Cubit state: UI có thể lệch khi platform reject command.
- Debounce bằng timer: làm mất intent hợp lệ và khó test.
- Một global command mutex cho mọi event: position/timeline dễ deadlock.

### Affected contracts/files

- Application Cubit commands, command coordinator, UI controls và remote callback.
- PLR-019, PLR-035, PLR-038, PLR-040, PLR-055, PLR-067, PLR-070–076.

### Test oracle

- Mỗi matrix cell ghi engine call count, Future result và final confirmed state.
- Double Toggle khi initial paused tạo desired sequence Play → Pause nhưng icon
  chỉ đổi khi snapshot xác nhận.
- Throw không giữ coordinator lock; command sau vẫn chạy.
- Boundary no-op không publish snapshot hoặc engine call.

---

## PLR-009 / 2026-08-02 / Owner: Player team

**Status:** Accepted<br>
**Decision version:** 1

### Context

Replace load cần phân biệt active state đã commit với pending request chưa được
phép xuất hiện ở metadata/queue. Failure/stale result phải gắn đúng target.

### Decision

- Handler giữ hai context riêng:

```text
ActivePlaybackContext? active
PendingLoadContext? pending
```

- Active chứa committed logical/effective queue, item/index, position/options và
  play intent.
- Pending chứa request queue/index/autoplay, generation, source mapping và loading
  status; pending không được dùng làm current metadata trước commit.
- Initial load:
  - outward queue/item/index vẫn empty/null;
  - processing có thể loading;
  - không publish mini/system metadata.
- Replace A → B:
  - A giữ outward current item/queue/index/system metadata trong lúc B loading;
  - pending B chỉ thể hiện bằng processing/loading context, không masquerade là
    active item;
  - B ready/latest mới atomic commit và thay toàn bộ outward queue/item/index;
  - B failure giữ A outward metadata, publish failure với `itemId` của B và tạo
    RetryContext target B.
- Stale success/failure không đổi active, pending mới hơn hoặc failure hiện tại.
- Stop clear cả active, pending và retry context.
- Load C sau B failure thay pending/retry B và trở thành latest generation.

### Alternatives rejected

- Publish B metadata ngay khi load bắt đầu: OS/UI hiển thị nội dung chưa playable.
- B failure retry A vì A đang outward current: sai user intent.
- Clear A trong replace loading: mini/system card nhấp nháy và mất context.

### Affected contracts/files

- Load/Error/Retry behavioral sequences và queue lifecycle state machine.
- Generation guard, reducer, failure mapper và handler load commit.
- PLR-049, PLR-057, PLR-059, PLR-062–064, PLR-080 và PLR-081.

### Test oracle

- Initial load failure không publish metadata/queue.
- Replace failure giữ A nhưng `failure.itemId`/Retry target là B.
- B ready commit queue/item/index atomically.
- Stale B after C không publish success hoặc error.
- Stop trong pending load clear mọi context; late result bị bỏ.

---

## PLR-014 / 2026-08-02 / Owner: Player team

**Status:** Accepted<br>
**Decision version:** 1

### Context

Shuffle tạo logical order và effective playback order. Domain, OS và manual
navigation phải cùng dùng một queue/index representation.

### Decision

- Handler giữ logical queue nội bộ để có thể tắt shuffle, nhưng publish một
  effective playback queue duy nhất cho Domain và OS.
- Khi shuffle off, effective order bằng logical order.
- Khi shuffle on, effective order lấy từ engine-confirmed effective sequence.
- `PlaybackSnapshot.queue`, OS queue, currentIndex, queueIndex,
  `hasNext/hasPrevious` và manual Next/Previous đều dùng effective order đang
  publish.
- Bật/tắt shuffle giữ current item ổn định; index được recompute trong order mới.
- Mọi effective-order change là queue publication, không phải position-only
  publication.
- Manual navigation:
  - repeat-one bị bỏ qua cho explicit Next/Previous;
  - repeat-all wrap Next cuối → đầu và Previous đầu → cuối;
  - repeat-off hoặc repeat-one tại boundary là idempotent no-op;
  - Previous trước hết áp dụng ngưỡng PLR-001; chỉ khi `position <= 3s` mới điều
    hướng effective queue.
- Engine vẫn là owner auto-repeat/advance theo PLR-002.

### Alternatives rejected

- Domain logical queue nhưng OS/effective index: queueIndex không còn cùng hệ quy
  chiếu.
- Shuffle chỉ đổi engine nhưng không republish queue: UI next/previous dự đoán sai.
- Repeat-one chặn explicit Next: trái user navigation intent.

### Affected contracts/files

- Queue/navigation/shuffle diagrams và state ownership.
- Reducer, mapper, system controls, handler navigation và shuffle operation.
- PLR-024, PLR-054–058, PLR-063, PLR-066, PLR-072, PLR-075 và PLR-076.

### Test oracle

- Shuffle on/off giữ item, recompute index và publish queue đúng một lần.
- Domain queue/index và OS queue/queueIndex giống nhau.
- Next/Previous theo effective order với off/one/all boundary.
- Previous >3s restart; =3s và <3s dùng effective previous/wrap/no-op.

---

## PLR-015 / 2026-08-02 / Owner: Player team

**Status:** Accepted<br>
**Decision version:** 1

### Context

UI cần position mượt nhưng OS không cần một platform publication mỗi tick.
Command logging cũng không được bịa caller provenance.

### Decision

#### Timeline cadence

- UI position projection target `200 ms` khi playback active.
- OS position-only resync cadence target `1 second`.
- Lifecycle, load commit, item/index, play, pause, seek completion, speed,
  repeat, shuffle, buffering, completed, error và Stop publish OS state ngay.
- N engine position ticks trong một OS cadence chỉ tạo tối đa một OS
  position-only publication với latest value.
- OS dùng updatePosition/updateTime/speed để nội suy giữa publications.
- Position-only event không publish media item hoặc queue.
- Clock/cadence injectable; test dùng fake clock.

#### Command provenance

```text
enum CommandSource { ui, systemRemote, interruption }
```

- UI Gateway adapter gọi internal operation với `ui`.
- BaseAudioHandler overrides gọi cùng operation với `systemRemote`.
- Runtime interruption logging dùng `interruption`.
- Chỉ ghi lock-screen/headset/notification/control-center nếu callback thực sự
  cung cấp thông tin đó; nếu không luôn dùng `systemRemote`.
- Logger optional/no-op; logger failure không đổi command result.

### Alternatives rejected

- Publish OS mỗi 200 ms: platform traffic không cần thiết.
- Dùng chung zero-argument method cho UI và OS rồi đoán caller: provenance sai.
- Wall-clock sleep trong unit test: flaky và chậm.

### Affected contracts/files

- Position/system timeline diagrams và logging contract.
- UI adapter, clock, position projector, system projector và logger.
- PLR-042, PLR-048, PLR-056, PLR-058, PLR-065, PLR-068 và PLR-088.

### Test oracle

- Fake clock chứng minh UI cadence 200 ms và OS cadence 1 giây.
- Immediate event không chờ cadence.
- N ticks không tạo N OS publications và không republish metadata/queue.
- UI/OS/interruption logs có đúng source; logger throw không phá playback.

---

## PLR-016 / 2026-08-02 / Owner: Player team

**Status:** Accepted<br>
**Decision version:** 1

### Context

Target Cubit thuộc Application nhưng legacy Cubit hiện nằm ở Presentation và
đang giữ fake state. Migration một lần sẽ làm nhiều commit không build-green.

### Decision

- Target `PlayerState` và `PlayerCubit` đặt tại
  `lib/features/player/application/`.
- Legacy types được rename `LegacyPlayerCubit`, `LegacyPlayerState` và
  `LegacyPlayerPresentation` mà không đổi behavior trong PLR-029.
- Core/Gateway/target Cubit phát triển và test song song với legacy UI.
- Sau bootstrap, app tạm provide cả target và legacy Cubit:
  - target Cubit dùng một `UiPlaybackGatewayAdapter`/handler duy nhất;
  - legacy Cubit chỉ giữ fake presentation state, không sở hữu engine/handler.
- Migrate widget theo lát: Host → Mini metadata/artwork → Dock/timeline/options →
  Expanded/lifecycle → selectors.
- PLR-110 bắt buộc xóa legacy types/provider/API trước platform/release QA.
- Mọi task/commit trong migration phải compile và test xanh.
- Dual-provider bridge là migration-only và không được tồn tại trong release.

### Alternatives rejected

- Big-bang migration: khó giữ build/test xanh và khó cô lập regression.
- Để target Cubit ở Presentation: trái dependency direction.
- Cho legacy và target mỗi bên một player: phá singleton/media-session invariant.

### Affected contracts/files

- Application/Presentation class diagrams và composition root.
- PLR-029, PLR-033, PLR-090, PLR-091, PLR-100–111 và PLR-180.

### Test oracle

- Mỗi migration slice build/test được với dual provider.
- Handler/engine creation count vẫn bằng một khi widget rebuild/push/pop.
- Sau PLR-110, static search không còn `LegacyPlayer` hoặc dual provider.
- Target Cubit/Application không import Infrastructure concrete.
