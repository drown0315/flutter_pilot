# Flutter Pilot

[English](README.md)

[文档](https://drown0315.github.io/flutter_pilot/)

Flutter Pilot 是一个面向 Flutter 应用的可复现 UI 调试上下文工具。它把一段
Flutter UI 操作路径描述成可提交、可分享、可重复执行的 YAML Scenario，并把
调试所需的上下文整理成适合开发者、CI 和 AI 编码代理阅读的产物。

> 项目状态：Flutter Pilot 仍在开发中。当前实现重点是 Dart CLI、Scenario
> YAML 解析与校验、报告生成和命令外壳；通过 `pilot_runtime` 驱动 Flutter
> UI 的执行能力正在建设中。

Flutter Pilot 通过 `pilot_runtime` 驱动 Flutter debug Runtime Target。
`pilot_runtime` 是 Flutter Pilot 自有的运行时包，负责应用侧交互和检查能力。

## 它能做什么

Flutter Pilot 把一次 UI 旅程视为一个可移植的 Scenario。Scenario 描述要点击
哪些 widget、在哪里输入文本、等待什么 UI 状态、何时滚动，以及在哪些步骤捕获
诊断产物。

Scenario metadata 也可以通过 `scenario.recording` 请求整次运行的设备视频录制。
录制属于运行级上下文：它在第一个 Step 执行前启动，在运行收尾时停止，并作为
Device Video Recording 产物记录，而不是某个 Step 的产物。

Runtime Target 的连接信息不会写进 YAML。相同的 Scenario 可以被校验、分享、
提交到仓库，并通过 CLI 参数在不同的 Runtime Target 上运行。

一次运行会在 `.runs/` 下生成运行目录。这个目录的目标是独立可读：开发者可以
查看截图和 HTML timeline，CI 可以归档产物，AI 代理可以读取结构化 Snapshot、
日志和 `run_report.json` 作为紧凑的调试上下文。

## 为什么需要它

Flutter UI 问题很难只靠一张截图和模糊的复现步骤交接。截图能展示外观，但不能
说明结构化 UI 状态、最近执行过的动作、运行日志，或问题出现在哪个精确 Step。

Flutter Pilot 通过可重复的 UI 旅程和周边运行时上下文，让开发者或代理能回答
更具体的问题：

- 用户在失败前做了什么？
- 当时有哪些可见文本和语义 UI 元素？
- 失败 Step 附近有哪些日志或运行时错误？
- 修复前后运行是否改变了预期的 UI 状态？

## 快速示例

```yaml
scenario:
  name: login_error
  description: Reproduce the invalid login message.
  recording:
    enabled: true

steps:
  - label: enter_email
    type:
      byType: textField
      text: bad@example.com

  - label: submit_login
    tap:
      byText: Continue
      byType: button

  - label: error_visible
    waitFor:
      byText: Invalid email or password
      timeoutMs: 5000

  - label: capture_failure
    capture: {}
```

这个 Scenario 只描述 UI 旅程。Flutter Pilot 会通过 `test` 命令启动 Target
App Package，并从 Flutter 的 machine output 中取得内部 Runtime Target。

`capture` 是一个 Step action。需要在某个位置保存诊断产物时，把它作为
`steps` 里的独立 Step 来写。

`recording.enabled: true` 会启用 Scenario Recording。省略 `recording` 表示不录制，
也可以用 `recording.enabled: false` 显式禁用。`recording: true` 这类布尔简写
是无效 YAML 形态。

HTML timeline report 会把同一次 UI 旅程转换成可视化审查界面。

## Quick Start

安装 Flutter Pilot CLI：

```bash
dart pub global activate flutter_pilot
```

Flutter Pilot 通过 `pilot_runtime` 驱动 Flutter 应用。目标应用需要先初始化
Pilot Runtime binding，`flutter_pilot test` 才能和它交互。

在 Target App Package 中初始化安全的应用侧配置：

```bash
flutter_pilot init
```

`init` 会在缺少 `pilot_runtime` 依赖时安装它。它不会修改 `lib/main.dart`；
如果缺少 `PilotRuntimeBinding.ensureInitialized()`，它会打印需要手动添加的
import 和 binding 调用：

```dart
import 'package:flutter/material.dart';
import 'package:pilot_runtime/pilot_runtime.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PilotRuntimeBinding.ensureInitialized();
  runApp(const MyApp());
}
```

完成必要的 `lib/main.dart` 修改后，检查应用侧配置：

```bash
flutter_pilot doctor
```

在 Flutter app package 中运行 `flutter_pilot test`。Flutter Pilot 会用
`flutter run --machine` 启动应用，从 Flutter 输出中读取 Runtime Target URI，
执行选中的 Scenario 或 Project Run，并在清理阶段停止已启动的应用。
人类可读运行会把 Target App Launch Progress 和 Step progress 写到 stderr；
最终的 `Run report:`、`HTML report:` 和 Project Run report 路径保持在
stdout，方便脚本读取。
`test --json` 会抑制这些进度输出。

不连接 Flutter 应用，只校验 Scenario：

```bash
flutter_pilot validate examples/smoke_scenario.yaml
```

通过启动当前 Target App Package 运行 Scenario：

```bash
flutter_pilot test examples/smoke_scenario.yaml
```

运行默认 Pilot Directory（`pilot/`）下的全部 Project Scenarios：

```bash
flutter_pilot test
```

运行指定目录下的全部 Project Scenarios：

```bash
flutter_pilot test pilot/regression
```

需要时可以选择 Target Device、Flutter flavor 或应用入口文件：

```bash
flutter_pilot test examples/smoke_scenario.yaml \
  --device <device-id-or-name> \
  --flavor staging \
  --target lib/main_staging.dart
```

运行到指定 Step 后停止，并打印捕获到的诊断上下文：

```bash
flutter_pilot test examples/smoke_scenario.yaml \
  --until wait_for_error \
  --print snapshot
```

基于已有运行目录重新生成 HTML timeline：

```bash
flutter_pilot report .runs/<run-directory>
```

比较两个已有运行目录：

```bash
flutter_pilot diff .runs/<before-run> .runs/<after-run>
flutter_pilot diff .runs/<before-run> .runs/<after-run> --json
```

## Scenario YAML

Scenario YAML 是 Flutter Pilot 对 UI 旅程的可移植描述。它支持有序 Steps、
Step Label、Step Include（引入复用的 Step Library）、Finder、动作、等待、
滚动和捕获检查点。

完整语法、示例和校验规则见 [Scenario DSL 参考](docs/reference/scenario-dsl.md)。

## 命令

```bash
flutter_pilot validate <scenario.yaml>
flutter_pilot validate <scenario.yaml> --json
flutter_pilot init
flutter_pilot doctor
flutter_pilot test
flutter_pilot test <scenario.yaml>
flutter_pilot test <scenario-directory>
flutter_pilot test <scenario.yaml> --device <device-id-or-name>
flutter_pilot test <scenario.yaml> --flavor <flavor> --target <entrypoint.dart>
flutter_pilot test <scenario.yaml> --until <step-or-label>
flutter_pilot test <scenario.yaml> --until <step-or-label> --print <snapshot|widget-tree|errors>
flutter_pilot report <run-directory>
flutter_pilot diff <before-run> <after-run>
flutter_pilot diff <before-run> <after-run> --json
```

`--print` 可以重复传入。请求多个诊断输出时，Flutter Pilot 会按稳定顺序打印：
Snapshot、Widget Tree、errors。

不传 Scenario 文件时，`test` 会从 `pilot/` 发现 Project Scenarios。传入目录时，
它会从该目录发现 Project Scenarios。目录发现会递归扫描 `.yaml` 和 `.yml` 文件，
但只运行带顶层 `scenario:` metadata 的文件；没有该 metadata 的 YAML 文件会被视为
Step Library 候选，不会被直接运行。

`run` 不再是 Flutter Pilot 命令。`test --target` 使用 Flutter CLI 的词义，
用于选择应用入口文件，不接受 VM service URI。

启用 `scenario.recording` 时，Flutter Pilot 会录制已解析的 Target Device。
这个 Target Device 必须同时是具有相同 device id 的 Recording Device。如果没有
传入 `--device`，只有在恰好一个受支持 Flutter Device id 同时可录制时才会自动
选择。

## 产物

Scenario Run 会在 `.runs/` 下写入一个运行目录。Project Run 会在 `.runs/`
下写入一个批量运行目录，并把子 Scenario Run 目录放在其中。产物模型同时面向
人工审查和机器消费。

- Screenshot：用户在屏幕上看到的画面。
- Snapshot：供工具和 AI 代理消费的结构化 UI 状态。
- Widget Tree：按需捕获的更深层 Flutter 层级数据。
- Logs：运行时和诊断输出。
- Device Video Recording：启用 `scenario.recording` 时保存的可选运行级视频，
  存储为 `artifacts/device-video-recording.<ext>`。
- `run_report.json`：机器可读的 Scenario Run 摘要。
- `timeline.html`：由运行产物生成的可视化 timeline。
- `project_run_report.json`：一次运行多个 Project Scenarios 时生成的机器可读
  Project Run 摘要。

## 开发

```bash
dart format .
dart analyze
dart test
```

添加 Dart 依赖时使用 `dart pub add`，保持依赖元数据一致。

## 文档

- [公开文档](https://drown0315.github.io/flutter_pilot/)：托管的指南和参考文档。
- [文档首页](docs/index.md)：概览和文档地图。
- [Getting Started](docs/guide/getting-started.md)：从安装到第一次运行的最短路径。
- [Write a Scenario](docs/guide/write-scenario.md)：编写可复现 UI 路径的 YAML。
- [Run a Scenario](docs/guide/run-scenario.md)：启动选项、检查点和诊断输出。
- [Scenario DSL](docs/reference/scenario-dsl.md)：字段、动作和 Finder 规则。
- [CLI Reference](docs/reference/cli.md)：命令和选项。

## 范围

Flutter Pilot 聚焦可复现的 Flutter UI 调试产物。第一版不会扩展成通用的视觉回归平台。
