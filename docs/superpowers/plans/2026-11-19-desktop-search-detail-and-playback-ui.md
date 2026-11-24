# Banmaku 桌面搜索与详情改版实施计划

> **执行方式** 按阶段实现和验收。每阶段先补当前版本会失败的回归，再提交可独立验证的变更。

**目标** 缩短从搜索到确认作品、选择剧集和开始播放的路径，让用户随时知道正在查哪个片库、实际播放来自哪里。

**基线** `codex/manual-source-discovery` 的 `cf0f736`。现版支持手动选源、海报与列表切换、原片源续播、深浅主题。详情把简介放在选集之前，搜索点进作品后会覆盖结果，播放器已经接收历史记录使用的来源名。

**实现结构** 沿用 Flutter、Riverpod 和 GoRouter。先调整独立详情，再复用详情摘要搭建宽屏搜索预览。播放器提示和发现页续播卡分别验收。片源身份和观看记录继续沿用现有数据契约。

参考 [Animeko 桌面探索页](https://github.com/open-ani/animeko/blob/main/.readme/images/features/pc-home.png) · [桌面搜索双栏](https://github.com/open-ani/animeko/blob/main/.readme/images/features/pc-search-detail.png) · [全屏播放器](https://github.com/open-ani/animeko/blob/main/.readme/images/features/player-fullscreen.png)

## 设计取舍

本轮优先调整「搜到 → 核对季与片源 → 选集 → 播放」。只调整详情风险较低，但用户比较多个同名结果时仍要反复返回。优先增加大图首页能最快改变观感，但对确认作品和选集的帮助较小。推荐先交付详情和宽屏搜索，再完善播放来源提示和发现页续播卡。

首版用 1120 逻辑像素作为搜索双栏断点。宽屏结果区约占 46%，其余空间给详情预览。窄窗口延续单列和独立详情路线。两种布局沿用 NovaPlay 的墨蓝与琥珀色、浅色主题和现有桌面导航。热门榜与新番日历另外评估，依赖有明确来源的榜单和排期数据。

## P0.1 · 把详情首屏让给选集

**文件** `lib/features/detail/detail_screen.dart`、`lib/core/config/routes.dart`、`lib/features/search/search_screen.dart`，新增 `lib/features/detail/widgets/subject_summary.dart`，测试 `test/refreshed_pages_test.dart` 和 `test/manual_source_selection_test.dart`。

- [ ] 新增组件测试。用两季同名作品、超长简介、缺失封面以及离线 Bangumi 响应验证。断言 616×600 和 1120×720 首屏能看见标题、年份、片源和「选集」入口，且测试不等待 Bangumi 完成。原版因长简介把选集推远而失败。
- [ ] 抽出只负责展示的 `SubjectSummary`，以 `VideoModel` 为输入，允许宿主传入操作区。显示片名、年份、实际片源、剧集数和可获得的评分，缺失字段省略。窄窗口用小海报与摘要并排，给选集留下空间。独立详情把选集排在简介前，简介可展开。现有 Bangumi 手动匹配和角色资料位于选集之后。
- [ ] 仅在 `DatabaseService().historyForVideo(video)` 找到该片源的记录时提供「继续观看」，调用现有 `resumeFromOriginalSource`。正常详情保留「立即播放」和逐集下载。换源恢复搜索打开详情时附带 `chooseEpisode=1`，路由将该标记传给 `DetailScreen`。该模式明确显示「请重新选集」，省略立即播放和续播按钮，即使同时收到 `play=1` 也等用户明确点集。无剧集显示「当前片源暂无剧集」，收藏、简介和资料仍可访问。
- [ ] 验证首屏可用，24 集、长片名、缺图和 Bangumi 不可用时布局稳定。分别点继续观看和明确选集，确认打开正确剧集且原进度保护生效。检查窄屏仍能调整 Bangumi 匹配，并确认逐集下载入口可用。

```powershell
flutter test --no-pub test/refreshed_pages_test.dart test/manual_source_selection_test.dart test/services/history_resume_test.dart
```

## P0.2 · 宽屏搜索增加详情预览

**文件** `lib/features/search/search_screen.dart`、`lib/shared/widgets/poster_card.dart`，新增 `lib/features/search/widgets/search_result_preview.dart`，复用 `lib/providers/video_provider.dart`，新增 `test/search_detail_preview_test.dart`。

- [ ] 补组件回归。准备 A、B 两季的独立详情响应，令 A 延迟、B 先返回。核对点选、分页与筛选、查询刷新、切源以及窄屏跳转。断言 B 显示后 A 即使晚到也无权替换它。
- [ ] `SearchScreen` 保存选中的作品 ID 和当时的片源实例。宽屏点击结果或用键盘选中时更新右侧预览，左侧列表保留查询、滚动位置和分页。预览与 `videoDetailProvider` 共用按片源实例和作品 ID 标识的详情请求。仅对选中作品发请求，切源时旧预览不会用新源重新查询。追加分页和网格／列表切换时保持选中作品；提交新查询或切源时清除选择，类型筛选隐藏当前作品时清除预览。左右区域分别滚动。
- [ ] 右侧复用摘要，按「选择作品」「加载中」「有结果」「读取失败」呈现。预览加载时可显示当前选中卡片的基础资料。失败时仅重试该作品详情，搜索结果仍可浏览。右侧「查看详情」进入完整详情。宽屏焦点停在结果卡片时 Enter 打开预览，焦点停在显式播放按钮时 Enter 才快捷播放。发现页和窄屏保留现有快捷键。换源恢复搜索沿用 `chooseEpisode=1`，只通过详情的剧集按钮启动播放。
- [ ] 验证 616×600、800×600 时沿用独立详情；1120×720、1280×800 时能边浏览边预览。返回搜索仍保留已经加载的结果。覆盖连续切源、同号不同源、自动回退结果的实际来源标注、快速切换结果，以及 160% 字体缩放下的布局和 Tab 焦点。

```powershell
flutter test --no-pub test/search_detail_preview_test.dart test/refreshed_pages_test.dart test/manual_source_selection_test.dart test/providers/search_provider_test.dart test/providers/search_pagination_test.dart
```

## P1.1 · 播放器显示实际来源

**文件** `lib/features/player/player_screen.dart`、`lib/features/player/player_window.dart`、`lib/core/utils/play_launcher.dart`、`lib/core/config/routes.dart`、`lib/features/download/download_screen.dart`，测试 `test/features/player/player_screen_test.dart`。

- [ ] 加入播放窗口测试。当前搜索源是 B，通过历史续播源 A，窗口顶栏显示 A。下载页打开已有文件，顶栏显示「本地文件」。没有来源资料时省略标签。检查普通窗口与全屏控件显示时的长标题和键盘操作。
- [ ] 在线播放沿用调用方传入的已确认来源名。独立窗口和应用内播放器走同一参数约定。离线下载入口显式传入 `isLocalFile: true`，旧参数缺省时按 `false` 解析。顶栏在标题旁显示实际来源；窄窗口可缩短标签，完整来源通过提示查看。
- [ ] 验证显示来源时不改变播放器会话 ID、起播位置、历史写回字段或现有快捷键。播放失败时保留现有「重试」路径。跨源恢复继续回到带片名的搜索并重新选集。

```powershell
flutter test --no-pub test/features/player/player_screen_test.dart test/features/player/playback_session_test.dart test/features/player/fullscreen_session_test.dart test/manual_source_selection_test.dart
```

## P1.2 · 强化发现页的继续观看

**文件** `lib/features/home/home_screen.dart`，测试 `test/home_layout_test.dart`。

- [ ] 添加同名、同集、不同片源的两条观看记录。断言两张卡片都可读且可键盘操作，并能分辨实际片源。空历史时，分类与海报紧接工具栏。
- [ ] 使用当前卡片和海报加载逻辑，强化「片名 → 第几集 → 进度」层级，第二行带实际片源。沿用现有横向滚动和一键续播，窄窗口中第一张卡完整可读。保持发现和搜索的手动选源入口位置。
- [ ] 在四种窗口尺寸、深浅主题和缺图场景复查继续观看，验证点开同名不同源的卡片时，各自使用原片源和原进度。

```powershell
flutter test --no-pub test/home_layout_test.dart test/discovery_visual_components_test.dart test/manual_source_selection_test.dart test/source_identity_storage_test.dart
```

## 交付验收

- [ ] P0 作为首个可交付批次，P1 按播放窗口和发现页拆开评审。每批单独记录测试与截图。
- [ ] 用两个可控片源制作同号、同名不同季、缺集或请求失败等样本。实际 Windows 复验「搜索比较两季 → 开详情 → 选第 2 集 → 播放 → 切搜索源 → 原源续播」。记录实际来源、剧集、起点和重启后的状态。对真实片源至少核实一条搜索到播放的链路。
- [ ] 同一套带封面样本分别截图深色和浅色，重点检查 616×600 和 1280×800。至少留存一张宽屏双栏、窄窗口详情首屏、播放器来源和继续观看的截图。
- [ ] 更新 README 中的操作说明。为 Windows 便携候选记录对应提交、ZIP SHA-256、测试结果和人工复验范围。

```powershell
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
flutter build windows --release --no-pub
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/package-portable.ps1
```
