# Vibe Pager

macOS 菜单栏小工具。Cursor / Codex 做完一轮，把结果推到飞书、钉钉、微信或 Telegram；你也可以从这些通道把任务指令发回 IDE。

要求 **macOS 13+**。原生 SwiftUI，不是网页，也不是套壳浏览器。

## 它做什么

- 菜单栏点开面板，绑定通讯渠道，打开 **远程通讯**。
- Cursor、Codex 两套通道互相独立，只显示你本机已安装的。
- 任务结束会推一条带编号的消息，例如：`【#2 vibe_remote-改一下按钮】`。
- 在手机上回复这条消息（或带上 `#编号`），会交回对应的 IDE。钉钉必须带编号。
- 关掉远程通讯后，本机 hook 仍可能进来，但不会外发。

## 安装（推荐：git clone + 本机编译）

在自己电脑上编译，系统不当成「网上下载的不明软件」，一般不用公证，也不用右键打开。

**1. 安装编译工具（一台电脑只需一次）**

打开「终端」执行，弹出窗口就点安装：

```bash
xcode-select --install
```

装的是 Xcode Command Line Tools，不必装完整 Xcode。

**2. 克隆仓库并安装**

```bash
git clone https://github.com/lihuida/vibe-pager.git
cd vibe-pager
./install.sh
```

脚本会按当前芯片编译（Intel 或 Apple Silicon），拷进「应用程序」，并自动打开。大约几分钟。菜单栏出现土拨鼠图标就成功了。

以后更新：

```bash
cd vibe-pager
git pull
./install.sh
```

### 或者下载现成 zip

GitHub Releases 里的 `Vibe-Pager-universal.zip` 解压后拖进「应用程序」。苹果芯片第一次请 **右键 → 打开**。若提示「已损坏」：

```bash
xattr -cr "/Applications/Vibe Pager.app"
```

## 使用

1. 绑定至少一个渠道，点 **发送测试**。
2. 打开 **远程通讯**。第一次会要辅助功能权限，用来把回复粘贴进 IDE。
3. 按需打开 Cursor / Codex 接入（会写本机 hook）。
4. 让 Agent 跑完一轮，手机上应收到推送。

截图不会在完工时自动发。需要时让 Agent 执行：

```bash
~/.vibe-remote/send.sh --shot --source cursor "改了什么，一句话即可"
```

Codex 把 `--source` 换成 `codex`。远程通讯关闭或 App 没开时，这条命令会静默失败。

## 渠道

| 渠道 | 怎么连 |
| --- | --- |
| 飞书 | 企业自建应用 + 机器人，事件订阅选长连接，单聊发「你好」 |
| 钉钉 | 企业内部应用 + 机器人，消息接收选 Stream，单聊发「你好」 |
| 微信 | 打开即出码，微信扫一扫；手机弹出数字就填上。连上后再发一句「你好」 |
| Telegram | 用 BotFather 建机器人，粘贴 Token，给机器人发 `/start` |

飞书、钉钉走机器人单聊，不用群 Webhook。

## 权限

右上角齿轮里可以看到系统权限：

- **辅助功能**：把通道里的回复粘贴进 Cursor / Codex
- **屏幕录制**：只有主动发截图时才需要

换过 App 名字或重装后，系统设置里可能要重新勾选一次。

## 配置与本机接口

- 配置：`~/Library/Application Support/VibeRemote/config.json`
- 本机 hook：`127.0.0.1:17800`，`POST /hook`

不要把 `config.json` 提交到仓库，里面有渠道密钥。

## 从源码编译

`install.sh` 只打当前芯片，给自己用。发版或给别人现成包时，打通用包：

```bash
./macos/package-app.sh
```

产物：

- `dist/Vibe Pager.app`（Intel + Apple Silicon）
- `dist/Vibe-Pager-universal.zip`

源码在 `macos/Sources/VibeRemote/`。

## 作者

abo · [lihuida@gmail.com](mailto:lihuida@gmail.com)

有问题、想加渠道或发现 bug，欢迎发邮件，或直接提 Issue / PR。

## 开源协议

[MIT](LICENSE)
