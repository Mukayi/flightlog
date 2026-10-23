# FlightLog 飞行日志

> 一个突发奇想的 vibecoding 产物。FlightLog 飞行日志，可以记录你的航线，记录天上的轨迹，记录抵达的地方。

FlightLog 是一款离线优先的 macOS 航班日志应用，使用 SwiftUI、SwiftData、MapKit 和 Swift Charts 构建，最低支持 macOS 15。

## 功能

- **单机多用户档案**：支持在应用内创建、切换、重命名和管理多个本地用户档案（仅保存昵称与预设对比色，不采集账号或云端身份），每个用户的航班、统计、地图和示例数据相互隔离。
- **共同旅程对比（2–4 人）**：在“对比”章节选择 2–4 位同行者，查看各自飞行护照摘要、严格匹配的“我们共同去过”（共同航班、双向共同航线、共同机场/城市/国家）、多年份同行趋势柱状图，以及区分“所有人共同航线 / 部分同行航线 / 个人独有航线”的叠加航线地图。
- **航班录入与管理**：新增、编辑、搜索、筛选和删除航班，按机场时区保存当地起降时间与历史夏令时偏移。
- **离线全球机场库（支持中文）**：离线搜索全球机场资料，支持 IATA、ICAO、英文名称以及中文机场/城市别名，并把机场名称、坐标、国家和时区保存为历史快照。
- **航线地图与统计面板**：在世界地图上聚合往返航线（支持跨国际日期变更线大圆航线分段渲染），查看年度/月度趋势、常用机场/航司/航线、最长航班及国内/国际构成。
- **多用户备份与跨设备带入**：支持导出当前用户或全部用户的 JSON v2 备份、导出当前用户 CSV；支持把朋友导出的 JSON/CSV 备份导入到新建或指定用户档案，并提供档案映射预览与危险操作二次确认。
- **一键示例数据**：可为当前用户生成 24 条跨年份、国内和国际的可重复示例数据；重复业务键会自动跳过。
- **可选 AeroDataBox 联网查询**：按航班号和当地起飞日期查询航班，核对候选航班后一键填充编辑草稿。

常用快捷键：

- `Command-N`：新增航班
- `Command-F`：前往航班页并聚焦搜索
- `Command-1` 至 `Command-6`：概览、航班、地图、统计、设置、对比

## 在 Xcode 中打开

1. 安装包含 Swift 6 的 Xcode。
2. 在 Xcode 中选择“文件 → 打开”，选中仓库根目录的 `Package.swift`。
3. 选择 `FlightLog` scheme 和“My Mac”，然后运行。

也可以从终端打开：

```sh
open -a Xcode Package.swift
```

## 运行测试

```sh
swift test
```

机场生成脚本的 Python 测试：

```sh
python3 -m unittest discover -s scripts -p 'test_*.py' -v
```

`scripts/generate_airports.py` 会合并 OurAirports 的 `keywords` 与
`scripts/data/wikidata_zh_airport_aliases.json` 离线快照。后者包含
Wikidata CC0 中文标签，以及单独标记的人工常见国际枢纽事实映射；应用运行时不访问网络。
OurAirports 下载固定到不可变提交并校验 SHA256。生成日期、源 URL/哈希、
alias 快照哈希及 277 个区域定期民航机场 IATA 清单记录在
`scripts/data/airport_coverage_manifest.json`，可由上述 Python 测试复核。

Release 编译检查（Apple Silicon）：

```sh
xcodebuild \
  -scheme FlightLog \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  build
```

Intel Mac 请把 `arch=arm64` 改为 `arch=x86_64`。打包脚本使用独立的 `.build-app` scratch path、当前 Mac 架构和显式关闭的代码覆盖率配置，不复用测试构建缓存。

## 数据存储与备份

航班记录由 SwiftData 保存在当前 macOS 用户的本地 Application Support 数据区，不会上传到服务器。系统负责实际数据库文件和旁路文件的位置与结构，不建议手工移动或编辑。

设置页提供两种导出：

- JSON：包含记录 ID、时间戳和完整机场快照，适合无损备份与恢复。
- CSV：适合在表格软件中查看或编辑常用字段；重新导入时会使用当前机场库生成快照。

建议在清空数据、替换恢复或迁移电脑前导出 JSON。JSON 文件未加密、未签名，请按普通敏感个人数据妥善保管。机场资料是随应用打包的离线快照，许可说明见 `Sources/FlightLog/Resources/AIRPORT_DATA_LICENSE.md`。

## AeroDataBox 联网查询

1. 在 [RapidAPI 的 AeroDataBox 页面](https://rapidapi.com/aedbx-aedbx/api/aerodatabox) 注册并订阅合适的套餐，复制 RapidAPI API key。
2. 打开 FlightLog“设置 → 联网航班查询”，输入并保存 key。
3. 在新增或编辑航班时填写航班号及当地起飞日期，点击“联网查询”，核对候选航班后再确认填充。

API key 只保存在当前用户的 macOS 钥匙串中，使用稳定标识 `local.flightlog.FlightLog.aerodatabox` / `rapidapi-key`，并设为仅本设备可用；不会写入 UserDefaults、日志、FlightLog 数据库、JSON/CSV 备份或源码，界面也不会回显完整 key。联网请求会把航班号和当地起飞日期发送给 RapidAPI/AeroDataBox，请自行确认服务商当前的隐私、数据保留、配额和计费条款。查询失败不会影响手动录入或清除现有草稿。

## 构建和本地安装

在仓库根目录执行：

```sh
./scripts/build_app.sh
```

脚本会执行 Release 构建、生成标准应用包、复制机场资源、进行 ad-hoc 签名并严格验证。产物位于：

```text
dist/FlightLog.app
```

应用图标是本项目原创生成资产；当前 V2.1 设计为简化深蓝护照、扩大白飞机、
高亮粗青航线与克制金色圆章。当前原始图保存在 `Assets/FlightLogIconSource.png`，
V2/V1 历史源分别保存在 `Assets/FlightLogIconSourceV2.png` 和
`Assets/FlightLogIconSourceV1.png`；`scripts/generate_icon.sh` 会生成带真实透明边角的
`Assets/FlightLogIconMaster.png`、完整 `FlightLog.iconset` 和 `FlightLog.icns`。
脚本只使用 macOS 自带的 Swift/CoreGraphics、`sips` 与 `iconutil`，可从任意工作目录运行。
生成来源、源文件 SHA256、机械处理链和再分发用途见
[`Assets/FLIGHTLOG_ICON_PROVENANCE.md`](Assets/FLIGHTLOG_ICON_PROVENANCE.md)。

直接打开：

```sh
open dist/FlightLog.app
```

如需长期使用，可在 Finder 中把 `FlightLog.app` 拖到 `~/Applications` 或 `/Applications`。该构建仅用于本机安装，采用 ad-hoc 签名，没有 Developer ID 签名或 Apple 公证，不适合作为互联网分发包；无需也不应修改系统安全设置。
