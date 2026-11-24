# Banmaku 手动选源与发现页改版实施计划

**目标** 让用户在发现页和搜索页直接选择片源。切源后能继续搜索，旧收藏和观看历史仍能从正确的作品和剧集打开。首轮界面采用深色桌面影院风格。

**实现结构** 沿用 Riverpod、现有片源设置和本地存储。先让作品身份与当前主源解耦，再接入共享片源选择器，最后调整发现页和搜索页的布局。

## 第一阶段 · 手动选源

### 1. 固定作品身份与旧数据兼容

**改动位置** `lib/services/scraper/lziapi_scraper.dart`、`lib/providers/scraper_provider.dart`、`lib/services/database_service.dart`、`lib/core/utils/history_resume.dart`。

- [ ] 用两个本地测试源返回相同的 `vod_id`。先补回归，验证切换主源前后同一源的作品 ID 一致，两源同号作品的收藏和历史仍独立。保存一份旧版数据样本，覆盖默认源的裸数字 ID、带前缀 ID，以及既往把其他源设为主源后生成的裸数字 ID。
- [ ] 生成 ID 时按固定的片源配置 ID 判断。保留 LziApi 的裸数字兼容格式，其他源固定用 `<sourceConfigId>:<vodId>`。解码时包含当前选中的源。详情请求用作品所属源解析，影视站之间同号 ID 各自独立。
- [ ] 读取旧收藏时优先用保存的 API 地址辨认来源。旧历史可用唯一匹配的已保存来源名称辨认。仅在来源和作品能确认时使用对应源查询，并继续使用那条旧记录的存储键。在兼容性用例里同时从搜索结果和原记录打开同一作品，验证不会新增重复收藏或丢失原进度。来源不明或有歧义时保留记录，提供重新搜索和选集入口。
- [ ] 运行以下回归。预期同号作品隔离、旧 ID 可读、错误来源没有收到作品详情请求。

```powershell
flutter test test/source_identity_storage_test.dart test/services/lziapi_scraper_test.dart test/services/history_resume_test.dart test/services/history_resume_lzi_integration_test.dart test/services/database_sources_test.dart
```

### 2. 接入发现页和搜索页的片源选择器

**改动位置** 新增 `lib/shared/widgets/source_picker.dart`。修改 `lib/providers/scraper_provider.dart`、`lib/providers/search_provider.dart`、`lib/providers/home_provider.dart`、`lib/features/home/home_screen.dart`、`lib/features/search/search_screen.dart`、`lib/features/settings/source_management_screen.dart`。

- [ ] 发现页和搜索页复用一个选择器。入口显示当前源名称，菜单列出已启用的源。选中后沿用 `active_source_v1` 保存，重启能恢复选择。用户之前保存过的选源随升级保留。
- [ ] 默认仅请求选中的源。失败状态显示「重试」和「切换片源」。设置里提供默认关闭的自动回退开关。开启时仅发现和搜索请求异常才查备用源，正常的空结果保持为空。列表若由备用源返回，显示实际来源。源管理的「测试」用单源请求，明确报告该源的结果。
- [ ] 搜索页切源后以最后一次已提交的关键词重新请求第一页，清除旧结果、分页和类型筛选条件。没有已提交关键词时停在搜索入口。发现页保留分类并重载；新源没有该分类时允许回到「全部」。慢请求回包后检查当前源和请求版本，避免覆盖新结果。
- [ ] 补测试用例。A 的请求先发但最后返回，切换到 B 后列表里只有 B 的结果；切源后用原关键词请求第 1 页；手动模式下 A 失败产生换源入口且 B 收到 0 次请求；开启回退后 A 异常可见 B 的实际来源；单源测试 A 失败不显示 B 的结果。

```powershell
flutter test test/providers/search_provider_test.dart test/providers/search_pagination_test.dart test/source_failure_ui_test.dart test/home_layout_test.dart
```

### 3. 续播保持原源，手动换源时重新选集

**改动位置** `lib/core/utils/play_launcher.dart`、`lib/core/utils/history_resume.dart`、`lib/features/home/home_screen.dart`、`lib/features/history/history_screen.dart`、`lib/features/favorites/favorites_screen.dart`、`lib/features/detail/detail_screen.dart`。

- [ ] 首页、历史、收藏进入同一套续播流程。即使当前搜索选择了 B，A 源已有历史仍先刷新 A 的详情。原作品和剧集确认后，再沿用旧位置启动播放。详情页清楚显示所属源，播放地址跟随用户选择的来源。
- [ ] 原源失效、停用、删除，或找不到原集时，给出「重试」和「切换片源」。手动选新源后，带原片名进入该源的搜索，让用户确认季和集。新源播放使用该源的作品身份和自己的播放记录，原历史保留。
- [ ] 用原源第 2 集的 180 秒进度做验收。当前选 B 时，三个入口仍从 A 第 2 集续播。A 请求失败或 B 缺集时，旧记录的集数、位置和时间戳保持一致。用户确认 B 的一集后，新记录落在 B 的作品下。回归页面离开后迟到的请求不会抢走导航。

```powershell
flutter test test/home_layout_test.dart test/source_identity_storage_test.dart test/services/history_resume_test.dart test/services/history_resume_lzi_integration_test.dart
```

## 第二阶段 · 发现页和搜索页视觉调整

**改动位置** `lib/core/config/theme.dart`、`lib/shared/widgets/main_scaffold.dart`、`lib/shared/widgets/poster_card.dart`、`lib/features/home/widgets/video_card.dart`、`lib/features/home/home_screen.dart`、`lib/features/search/search_screen.dart`。

- [ ] 用深墨蓝做深色界面的底色，用暖琥珀突出当前导航、键盘焦点和进度。继续支持浅色和跟随系统，沿用现有中文字体回退配置。
- [ ] 收紧侧栏和顶部留白。把「搜索作品」和片源选择器放在同一工具栏，窄窗口可换行。有历史时优先展示「继续观看」，卡片显示片名、季集和进度。无历史时分类和海报网格直接接在工具栏下面。
- [ ] 统一海报为 2:3、两行片名和一行必要信息。使用现有占位图处理封面加载失败。播放操作在悬停和键盘聚焦时可见，播放入口支持 Enter。搜索保留列表与海报两种视图。
- [ ] 对发现页和搜索页分别验收加载、空结果、请求失败、长片名和缺图。现有测试中覆盖的 616×600、800×600、1120×720、1280×800 窗口应能访问搜索和换源。深色、浅色各留一组实机截图，手动验证 Tab 焦点、菜单选择、续播卡可点，以及缩放后无溢出。

```powershell
flutter test test/home_layout_test.dart test/refreshed_pages_test.dart test/source_failure_ui_test.dart test/providers/search_provider_test.dart
```

## 集成验收和交付边界

- [ ] 第一批提交先交付稳定身份、选源行为和续播兼容。第二批提交交付发现页和搜索页样式，播放器与详情页的整体换肤留给后续迭代。
- [ ] 在与仓库锁定依赖一致的环境运行完整检查，再在 Windows 11 沙盒按新包重测启动、选源、搜索、续播、下载暂停后重启继续、离线播放和旧数据升级。至少用一个当前可访问的真实源验证从搜索到播放的链路。备用源切换与故障路径用可控片源复现。
- [ ] 记录测试提交、系统版本、ZIP 哈希、界面截图和结果。当前 Preview 1 草稿与本次改版分别验收。改版进入后续构建，发布决定依据对应候选包的实测记录。

```powershell
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build windows --release
powershell -ExecutionPolicy Bypass -File scripts/package-portable.ps1
```
