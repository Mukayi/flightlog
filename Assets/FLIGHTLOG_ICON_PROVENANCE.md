# FlightLog 图标来源记录

当前版本：V2.1  
生成及核验日期：2026-08-19

## V2.1 生成来源

当前图标原始图由 Cursor 的 `GenerateImage` 功能生成。生成时仅以项目自己的
V1/V2 图标作为项目内方向参考；没有提供外部下载图片、第三方图标、商标图形或
素材库资源。

生成 prompt 的完整设计摘要（根据本次生成任务记录整理，并非工具内部逐字日志）：

> 为离线 macOS 航班日志应用 FlightLog 生成原创 1024×1024 V2.1 app icon。
> 保持 V2 简化、正面的深蓝护照、克制金色圆章和无文字构图，但针对 16/32 像素
> 辨识度显著扩大白色飞机，提高飞机在护照上的面积与轮廓清晰度；把青色弧形航线
> 加粗并提高亮度和饱和度，保留左下圆点、弧线、中间圆点以及接近飞机尾部的走向。
> 不恢复球体经纬线、页缝、倾斜书本或复杂细节，不加入品牌、商标、SF Symbols、
> 第三方素材或额外物体；白飞机和青航线必须在深蓝底上形成强对比。

`GenerateImage` 导出的 V2.1 PNG 是 1024×1024 RGB 文件，外围包含已烘焙的浅色中性
棋盘格像素；项目没有额外绘制或叠加棋盘格。机械渲染步骤只清除与画布边缘连通的
中性背景像素，以得到真正透明的 master，不重绘图案。

本记录只陈述项目中可核验的生成与处理事实，不对著作权归属、独创性门槛、商标
可用性或任何司法辖区的法律状态作结论。

## V2.1 采用文件

- 原始生成源：`Assets/FlightLogIconSource.png`
  - SHA256：`4f5f1d952a7221bdb46805bbe42281034ec09b902bc6f3295832e14bb64fe02a`
- 透明 1024 master：`Assets/FlightLogIconMaster.png`
  - SHA256：`98c56c47919fc4517b70f2defa1dae5484703c10eac8a14190f739086ee5d7f2`
- ICNS：`Assets/FlightLog.icns`
  - SHA256：`6e644c3e10134166203f675d00a5cba4e9be03b8344ab58476d5a63a21c49ac6`

## 机械处理链

1. `scripts/render_icon_master.swift` 将源图等比放入 1024×1024 RGBA 画布并保留
   20 px 外层画布边距。
2. 渲染器从四边开始做连通区域扫描，仅把透明像素及满足亮度/中性色差阈值的
   GenerateImage 外围背景清为 alpha 0；白飞机、青航线、金圆章和深蓝主体不重绘。
3. `scripts/verify_icon_alpha.swift` 检查透明四角、主体安全边距，以及 16/32 像素
   中深蓝、白色和青色的最小像素数、3:1/4.5:1 对比度、连通组件、bounding box
   跨度，以及航线与飞机的邻近关系；master 还核验 navy/white/cyan/gold 均未误删。
4. `scripts/generate_icon.sh` 使用 macOS 自带 Swift/AppKit、`sips` 和 `iconutil`
   机械缩放为完整 iconset，编码 ICNS，并执行 `iconutil` roundtrip。16/32 像素通过
   `scripts/render_icon_small.swift` 对 master 中原有白飞机和青航线做分区覆盖率采样，
   仅避免缩小时被海军蓝平均掉，不使用 SF Symbols，也不生成新的图形路径。
5. 处理链不下载或引入任何新插画、第三方素材或外部资产。

## V2 历史

- V2 原始源保留为：`Assets/FlightLogIconSourceV2.png`
- V2 源 SHA256：`9d132133f1c29bb50ff323ce99f9249c49aa06f3a7f4e5734a460758d3f964ba`
- V2 master SHA256：`14b97027fde3355b4618bca8da73f0e13bdfd41f16a41f2f50a61dd2c27c9fc9`
- V2 ICNS SHA256：`fd7c3ec846e68d94c9ec3665af86101cd036837feca973eb67532d61c08891c7`
- V2 因 16 px 青航线对比仅 1.76:1、白飞机仅 3 个分类像素而被审查为 NOT_READY；
  默认流水线不再引用 V2。

## V1 历史

- V1 原始源保留为：`Assets/FlightLogIconSourceV1.png`
- V1 源 SHA256：`bb9f9e4f755de74c4369fe46a0b3e85083575fec35919dc4221547ea9fcb32e6`
- V1 曾使用深蓝护照、球体经纬线、白飞机和青色航线；默认流水线不再引用 V1。

## 再分发用途

图标用于 FlightLog 项目源码中的构建资产，以及随 FlightLog 应用包、项目备份和
项目发布产物一同再分发。任何再分发者仍需自行评估其适用场景和合规要求。
