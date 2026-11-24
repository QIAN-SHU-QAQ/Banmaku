# Banmaku Windows 安装与使用

## 单文件便携安装包

- 下载名称以 `-windows-x64-portable.exe` 结尾的安装包及对应 `.sha256`，校验后双击。选择自己有写权限的文件夹或 U 盘目录。安装包以普通用户权限运行，应用所需的 VC++ DLL 随包提供。
- 解压后从 `app\Banmaku.exe` 启动。`UserData` 保存历史、收藏、设置、自定义片源和下载。换电脑或盘符时，先退出主窗口和所有播放器，再复制整个 Banmaku 文件夹。
- 可以在向导中选择首次启动时导入本机历史、设置和下载。原文件会保留。弹弹play 的 AppId 和 AppSecret 需在便携版重新填写。
- 更新前退出主窗口和所有播放器，运行新版安装包并选择同一目录。更新只替换 `app`，保留 `UserData`。需要回退时先退出当前程序，再运行 `app.previous` 中的上一版程序。
- 安装包未做代码签名。首次运行前请用 GitHub Releases 提供的 SHA-256 校验文件核对下载内容。[GitHub Releases](https://github.com/QIAN-SHU-QAQ/Banmaku/releases)

## ZIP 解压版

- 当前便携包的验收目标是 Windows 11 x64。Windows 10 的兼容性待验证。
- ZIP 版随包提供所需的 VC++ DLL，运行时无需管理员权限。

1. 下载 ZIP 和对应的 `.sha256`。比较校验值后再解压。[GitHub Releases](https://github.com/QIAN-SHU-QAQ/Banmaku/releases)
2. 将 ZIP 解压到新目录，例如 `D:\软件\Banmaku`。更新前先退出主窗口和所有播放窗口。
3. 双击 `Banmaku.exe`，保留同目录的 DLL 和 `data/`。便携包未做代码签名，Windows SmartScreen 可能提示「未知发布者」。

当前用户配置保存在 `%APPDATA%\Banmaku\Banmaku`。从旧版升级时，先关闭旧程序和播放器。首次运行会复制已有的历史、收藏、设置和任务记录。新下载保存在「文档」目录中的 `Banmaku\Downloads`，旧下载仍可从下载页打开。

## 查找和播放作品

1. 在「发现」浏览 Bangumi 动画作品库，或打开「作品搜索」输入片名。点开作品预览后选择「查找片源」。已知片名时，也可直接进入「按片源搜索」。
2. 片源搜索同时查询所有启用的源。匹配的版本合并为一张作品卡片，明确不同的季或年份分别显示。若部分片源失败，可以继续使用已返回的结果，或点「重新查询」。
3. 点开作品后，选择一个片源进入详情并选集。可先点「测试全部」，它会抽查当前作品每个版本的首个剧集。结果只反映该抽样请求，后续剧集和实际解码以播放结果为准。

播放窗口是独立进程，关闭它后可以继续在主界面浏览。观看历史会记录片源和集数。从首页、历史或收藏续播时，应用会先从原片源刷新并定位原集。缺集或刷新失败时可重试，或在该片名下换源、重新选集。播放器无法确认起点时会保留原记录。[线上续播验收](https://github.com/QIAN-SHU-QAQ/Banmaku/blob/main/docs/reviews/2026-11-06-online-acceptance-next-phase.md)

## 添加自定义片源

1. 打开「设置 → 源管理 → 添加自定义源」。
2. 填入名称和 MacCMS 的 HTTP 或 HTTPS API 地址，例如 `https://example.com/api.php/provide/vod/`。源应提供可识别的国产动漫、日本动漫或日韩动漫分类，以及 HTTP 或 HTTPS 剧集地址。
3. 保存后可点「测试」检查该源的 API 连接与数据返回。启用的源会参与片源搜索。自定义片源配置保存在本机，可以随时停用或删除。

## 下载与弹幕

- 在详情页通过剧集旁的下载按钮加入队列。下载页支持暂停、继续和打开保存位置，完成后可离线播放。下载支持未加密且使用完整 TS 分片的 HLS 点播，fMP4、字节范围分片、独立音轨及直播会提示不支持。
- 在「设置 → 弹幕」填写自己的弹弹play AppId 和 AppSecret。自动匹配不准时，可在播放器手动选择。
- 更新需要重新下载对应的 Windows 包。[GitHub Releases](https://github.com/QIAN-SHU-QAQ/Banmaku/releases)

## 校验下载

在下载文件所在目录打开 PowerShell，将下方文件名替换为实际下载的 ZIP 或 EXE 后运行。

```powershell
Get-FileHash -LiteralPath '.\Banmaku-<版本>-windows-x64.zip' -Algorithm SHA256
```

输出的 `Hash` 应与对应 `.sha256` 文件开头的值一致。
