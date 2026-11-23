# Banmaku Windows 便携预览版

## 启动与升级

- 当前便携包的验收目标是 Windows 11 x64。Windows 10 的兼容性待验证。
- 运行预览包无需管理员权限、Flutter 或 Visual Studio。若提示缺少运行库，请安装微软提供的 x64 运行库。[Microsoft Visual C++ x64 可再发行程序包](https://aka.ms/vc14/vc_redist.x64.exe)

1. 下载 ZIP 和对应的 `.sha256`。比较校验值后再解压。[GitHub Releases](https://github.com/QIAN-SHU-QAQ/NovaPlay/releases)
2. 将 ZIP 解压到新目录，例如 `D:\软件\Banmaku 预览版`。更新前先退出主窗口和所有播放窗口。
3. 双击 `nova_play.exe`，保留同目录的 DLL 和 `data/`。便携包未做代码签名，Windows SmartScreen 可能提示「未知发布者」。

Banmaku 从 `%APPDATA%\com.novaplay\nova_play` 读取历史、收藏、设置和自定义片源，包括旧版 NovaPlay 保存的数据。需要备份时，在退出应用后复制该目录。下载完成的文件默认位于系统「文档」目录内的 `NovaPlay\Downloads`。卸载时可删除解压目录，是否保留这两处用户数据由你决定。

## 查找和播放作品

1. 在「发现」浏览 Bangumi 动画作品库，或打开「作品搜索」输入片名。点开作品预览后选择「查找片源」。已知片名时，也可直接进入「按片源搜索」。
2. 片源搜索同时查询所有启用的源。匹配的版本合并为一张作品卡片，明确不同的季或年份分别显示。若部分片源失败，可以继续使用已返回的结果，或点「重新查询」。
3. 点开作品后，选择一个片源进入详情并选集。可先点「测试全部」，它会抽查当前作品每个版本的首个剧集。结果只反映该抽样请求，后续剧集和实际解码以播放结果为准。

播放窗口是独立进程，关闭它后可以继续在主界面浏览。观看历史会记录片源和集数。从首页、历史或收藏续播时，应用会先从原片源刷新并定位原集。缺集或刷新失败时可重试，或在该片名下换源、重新选集。播放器无法确认起点时会保留原记录。[线上续播验收](https://github.com/QIAN-SHU-QAQ/NovaPlay/blob/main/docs/reviews/2026-11-06-online-acceptance-next-phase.md)

## 添加自定义片源

1. 打开「设置 → 源管理 → 添加自定义源」。
2. 填入名称和 MacCMS 的 HTTP 或 HTTPS API 地址，例如 `https://example.com/api.php/provide/vod/`。源应提供可识别的国产动漫、日本动漫或日韩动漫分类，以及 HTTP 或 HTTPS 剧集地址。
3. 保存后可点「测试」检查该源的 API 连接与数据返回。启用的源会参与片源搜索。自定义片源配置保存在本机，可以随时停用或删除。

## 下载与弹幕

- 在详情页通过剧集旁的下载按钮加入队列。下载页支持暂停、继续和打开保存位置，完成后可离线播放。下载支持未加密且使用完整 TS 分片的 HLS 点播，fMP4、字节范围分片、独立音轨及直播会提示不支持。
- 在「设置 → 弹幕」填写自己的弹弹play AppId 和 AppSecret。自动匹配不准时，可在播放器手动选择。
- 更新需要重新下载便携包。[GitHub Releases](https://github.com/QIAN-SHU-QAQ/NovaPlay/releases)

## 校验 ZIP

在 ZIP 所在目录打开 PowerShell，替换下方文件名中的 `<版本>` 后运行。

```powershell
Get-FileHash -LiteralPath '.\Banmaku-<版本>-windows-x64.zip' -Algorithm SHA256
```

输出的 `Hash` 应与对应 `.sha256` 文件开头的值一致。
