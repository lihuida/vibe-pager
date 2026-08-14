# Vibe Pager

Vibe Coding 的传呼机：把飞书、钉钉、微信、Telegram 接到本机 Cursor / Codex，离开电脑也能收完工消息、下下一轮指令。

要求 **macOS 13+**。

## 它做什么

用来打通 **Cursor / Codex** 和 **飞书、钉钉、微信、Telegram**：一边接收任务完成消息，一边从聊天里把任务指令发回电脑上的 IDE。

跑在 **macOS** 上，藏在右上角菜单栏。点土拨鼠打开面板，打开远程通讯，同步就开始。电脑不在身边，也能继续 vibe coding。

Agent 在 IDE 里跑、你在等的那段时间，可以去做别的事。跑完了手机会及时收到，看一眼结果，随时下一句指令。

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

脚本会按当前芯片编译（Intel 或 Apple Silicon），拷进「应用程序」，并自动打开。大约几分钟。

装好后要从屏幕**右上角菜单栏**打开，不要在 Dock 里找。看时钟 / Wi-Fi 左边的土拨鼠，点它打开面板：

![从菜单栏点土拨鼠打开 Vibe Pager](docs/menubar.png)

找不到图标时：带刘海的 Mac 上它可能被挡住，按住 **Command** 拖动其他菜单栏图标腾出位置；或打开「应用程序」里的 Vibe Pager，面板会再弹出来。

以后更新：

```bash
cd vibe-pager
git pull
./install.sh
```

### 或者下载现成 zip

GitHub Releases 里的 `Vibe-Pager-universal.zip` 解压后拖进「应用程序」并打开。装好后同样从**右上角菜单栏**点土拨鼠，不要在 Dock 里找。苹果芯片第一次请 **右键 → 打开**。若提示「已损坏」：

```bash
xattr -cr "/Applications/Vibe Pager.app"
```

## 使用

1. 从屏幕右上角菜单栏点土拨鼠，打开面板。
2. 绑定至少一个渠道，点 **发送测试**。
3. 打开 **远程通讯**。第一次会要辅助功能权限，用来把回复粘贴进 IDE。
4. 按需打开 Cursor / Codex 接入（会写本机 hook）。
5. 让 Agent 跑完一轮，手机上应收到推送。回复那条消息（或带上 `#编号`）会交回对应的 IDE。钉钉必须带编号。

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

勾选后必须从菜单栏点「退出」再打开，权限才会生效。列表里如果出现多个 Vibe Pager，或带黄色警告，删掉旧项，只勾选当前正在运行的这个。

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
