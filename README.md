# YARP recovery for Xiaomi 14 (houji / SM8650)

> ⚠️ 免责声明：本仓库产物**未经真机开机、触摸与解密验证**。刷写 recovery 存在变砖或丢失数据的风险，请先备份并自担风险。

在 GitHub Actions 云端构建小米 14（houji，SM8650）的 **YARP** recovery。YARP（Yet Another Recovery Project）是 [TWRP-Test](https://github.com/TWRP-Test) `twrp-16.0` 分支内置的 LVGL GUI2 界面。本仓库只包含构建配置——源码版本锁定（`sources.json`）、构建脚本与云端工作流；**全程云端编译，本地无需安装任何工具链**。

## 设备

| 项目 | 值 |
| --- | --- |
| 代号 | houji |
| 型号 | 23127PN0CC 等（小米 14 全系） |
| SoC | 骁龙 8 Gen 3（SM8650） |
| 平台 | pineapple |
| Recovery | TWRP-Test `twrp-16.0`（默认 YARP GUI2） |
| 产物 | `YARP-houji-8a58fc3-recovery.img`（ramdisk-only，Android v4 boot header） |

## data 解密支持（本仓库的重点）

小米 14 的 userdata 使用 **FBE v2 + metadata 加密**，密钥链为：
metadata 解密 → 挂载 userdata → 输入锁屏密码 → **Weaver** → **KeyMint 3.0 StrongBox**（位于嵌入式安全芯片 eSE）→ 为加密目录安装密钥 → userdata 解密完成。

关键难点：KeyMint StrongBox 需要通过 **OMAPI**（`android.se.omapi.ISecureElementService`）访问 eSE。在系统里该服务由 `SecureElementApplication.apk`（Java）提供，无法直接在 recovery 中运行——这是社区 houji TWRP 树长期无法解密 data 的原因（见 [lolipuru 的分析](https://github.com/lolipuru/device_xiaomi_houji_TWRP)）。

本仓库的做法：

1. **平台锁定 TWRP-Test `twrp-16.0`** —— 自带原生 OMAPI 实现（`TW_INCLUDE_OMAPI` 开关）；
2. **`scripts/apply-device-overlay.sh`** —— 构建前为设备树开启 `TW_INCLUDE_OMAPI := true`（幂等，日志可见）；
3. **设备树**（`lolipuru/device_xiaomi_houji_TWRP`，commit 已锁定）自带其余解密配置：
   `TW_INCLUDE_CRYPTO`、`TW_INCLUDE_CRYPTO_FBE`、`TW_INCLUDE_FBE_METADATA_DECRYPT`、`BOARD_USES_QCOM_FBE_DECRYPTION`、`TW_USE_FSCRYPT_POLICY := 2`、`BOARD_USES_METADATA_PARTITION`，以及 KeyMint/Weaver/SE 所需的 vendor 组件；
4. **`scripts/verify-image.py`** —— 打包阶段对产物做**解密静态校验**：fstab 的 `fileencryption=` / `metadata_encryption=` 标志、ramdisk 内 keymint / weaver / gatekeeper / omapi / qseecom 组件是否就位，结果写入 `verification.json`。

> 诚实声明：静态校验只保证"解密所需的组件与配置已编入镜像"，**不等于真机解密已验证**。真机验证步骤见下文。

## 构建（全程 GitHub，本地无需任何环境）

1. 新建一个 GitHub 仓库（例如 `yarp-houji`），把本目录全部文件推送上去。
2. 打开仓库 → **Actions** → **Build YARP Houji** → **Run workflow**。
3. 构建约 3～6 小时。完成后在该次运行的 **Artifacts** 下载产物（保留 14 天）。

> `Build YARP Houji (ccache)` 为带编译缓存的版本：首次构建不受益，第二次起明显更快，推荐日常使用。

### 产物

| 文件 | 说明 |
| --- | --- |
| `YARP-houji-8a58fc3-recovery.img` | 可刷入的 recovery 镜像 |
| `SHA256SUMS.txt` | 镜像校验和 |
| `verification.json` | 静态校验报告（YARP 资源 + 解密组件） |
| `source-manifest.xml` | 解析后的源码清单（完整可复现记录） |
| `-logs` artifact | sync / build / verification 与资源日志 |

## 刷入（风险自负）

~~~bash
# 先临时启动试水（不落盘，重启即回正常系统）
adb reboot bootloader
fastboot boot YARP-houji-8a58fc3-recovery.img

# 确认可用后再正式刷入（houji 为 A/B 设备，recovery 在 recovery_a/_b）
adb shell su -c 'dd if=/dev/block/by-name/recovery_a of=/sdcard/recovery_a_stock.img'  # 备份
fastboot flash recovery_a YARP-houji-8a58fc3-recovery.img
fastboot reboot recovery
~~~

## 解密验证步骤（真机）

1. `fastboot boot` 临时进入 YARP；
2. 首次进入会提示输入锁屏密码，输入后等待；
3. 若 `/data` 挂载成功、文件管理能看到内部存储 → metadata → weaver → keymint-strongbox → fscrypt 解密链路打通；
4. 也可在 YARP 的"挂载"菜单手动挂载 `data` 验证。

若卡在密码界面或提示解密失败：收集 `adb pull /tmp/recovery.log` 与本仓库构建的 `verification.json`、`build.log` 一并排查（重点看 keymint-strongbox 与 omapi 服务日志）。

## 目录结构

~~~
.
├── .github/workflows/
│   ├── build.yml                # 原始工作流（无缓存）
│   └── build-ccache.yml         # ccache 缓存加速
├── scripts/
│   ├── build-yarp.sh            # sync / build / package 主脚本
│   ├── apply-device-overlay.sh  # data 解密启用层（OMAPI）
│   ├── source-lock.py           # 按 sources.json 固定源码版本
│   ├── verify-image.py          # 产物静态校验（含解密检查）
│   ├── prepare-runner.sh        # 清理 runner 磁盘 + 16 GiB swap
│   └── resource-report.sh       # 构建期资源监控
├── sources.json                 # 源码 pin 清单（manifest / 平台项目 / 设备树）
└── README.md
~~~

## 源码锁定说明

`sources.json` 锁定三类源码：

- `manifest`：`TWRP-Test/platform_manifest_twrp_aosp` @ `814b553`（`twrp-16.0`）；
- `projects`：`build/soong`、`bootable/recovery`（YARP/GUI2）、`external/lvgl`、`external/libvpx`、`external/libwebm` 各自固定 commit；
- `device`：houji 设备树（`owner/name/revision`）。当前锁定 `lolipuru/device_xiaomi_houji_TWRP` 的 `twrp-12.1` 分支 commit `762a9581`（"houji: update libs from OS1.0.11.0"）。设备树只读引用，无需 fork；要自行修改可 fork 后改 `owner`，要跟进设备树更新则把 `revision` 换成新 commit。

`scripts/source-lock.py overlay` 把这些 pin 写进 `.repo/local_manifests/yarp-pins.xml`；`verify` 在 sync 后逐项目 `git rev-parse HEAD` 校验，任何漂移都会使构建失败。升级版本 = 改 `sources.json`。

若 `device.revision` 填的是分支名而非 commit SHA，构建仍可用（日志会给出提示），产物里会额外输出 `device-revision.txt`（本次构建实际使用的设备树 commit）与 `source-manifest.xml`。把该 SHA 回填进 `sources.json` 即可锁定到确定版本，保证可复现。

## Hosted runner 资源策略与磁盘旋钮

GitHub 托管 runner（ubuntu-24.04）磁盘约 72 GiB、内存约 8 GiB；prepare-runner.sh 会清理预装 SDK 并分配 swap，构建以 2 jobs、单 Soong bootstrap、SOONG_GOMEMLIMIT=8GiB 运行，systemd scope 限内存 13 GiB / swap，resource-report.sh 每分钟写资源快照，另附全盘 du 诊断。

所有磁盘阈值都可以在 workflow 的 env 里直接调：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| YARP_SWAP_GIB | 8 | swap 文件大小（GiB）。swap 文件占的就是构建磁盘，内存够用时调小可多省磁盘 |
| YARP_MIN_FREE_GIB | 25 | swap 分配后要求的剩余磁盘（GiB），不足则在准备阶段失败 |
| YARP_MIN_FREE_AFTER_SYNC_GIB | 4 | 源码同步后要求的剩余磁盘（GiB），不足则中止以保留诊断日志 |
| SYNC_JOBS / BUILD_JOBS | 8 / 2 | repo 同步并发 / 编译并发 |

> 排错：
> - 日志出现 "Less than 95 GiB is available..." —— 这是旧版阈值，已改为可配置（默认 25 GiB，适配 72 GiB runner），同步最新的脚本即可；
> - repo sync 阶段磁盘写满（ENOSPC）—— 该 runner 放不下源码树，换更大磁盘的 runner（改 runs-on）或把 SYNC_JOBS 调小后重试；
> - 编译阶段 OOM / runner 掉线 —— 适当调大 YARP_SWAP_GIB 或把 BUILD_JOBS 降为 1。

## 致谢

- [TWRP-Test](https://github.com/TWRP-Test)（`twrp-16.0` / YARP GUI2 平台与 SM8650 解密能力）
- [lolipuru/device_xiaomi_houji_TWRP](https://github.com/lolipuru/device_xiaomi_houji_TWRP)（houji 设备树、vendor 组件与解密链路分析）
- [MDXRosmontis/yarp-sm8850](https://github.com/MDXRosmontis/yarp-sm8850)、[mzsy123/Yarp-macan](https://github.com/mzsy123/Yarp-macan)（构建脚手架）

上游代码自其原仓库获取并保留其原始许可证。