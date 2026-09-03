# 单词桌宠 🐱

Windows 桌面单词记忆桌宠：**阅读驱动式查词 + 剪贴板例句记录 + 自适应记忆曲线复习**。

## 功能

- 🖱️ **系统托盘**：托盘右键菜单支持"呼出输入栏 / 显示·隐藏桌宠 / 退出"。
- 🖱️ **紧凑悬浮**：面板收起时窗口自动缩小为桌宠尺寸，减少对桌面的遮挡；点击桌宠切换面板开/关，按住桌宠可拖动窗口。
- ⌨️ **快捷键全家桶**：`Alt+W` 呼出输入栏；`Alt+E` 隐藏输入栏；`Alt+P` 显示/隐藏桌宠，手不离键盘即可录入单词。
- 🔄 **开机自启动**：设置页一键开启。
- 📖 **多词汇本**：可新建自定义词汇本、切换，并可删除自建词汇本（内置四级/六级词汇本不可删除）；查词、复习、导入导出均作用于当前词汇本。
- 📕 **内置四级词汇本**：内置 3815 个 CET-4 词条（含音标、中文释义、词频），来源 [cet-words-cli](https://www.npmjs.com/package/cet-words-cli)（MIT License）。
- 📘 **内置六级词汇本**：内置 1945 个 CET-6 词条（含音标、中文释义、词频），来源 [cet-words-cli](https://www.npmjs.com/package/cet-words-cli)（MIT License）。
- 📦 **离线词典 5760 词**：内置 CET4 + CET6 完整词表，离线即可查绝大多数六级词汇；在线查过的词自动缓存到本地，之后无网也能查。
- 🔍 **多源在线兜底**：离线未命中时依次尝试 有道词典（中文多义 + 音标）→ MyMemory 翻译 → Free Dictionary API（英文释义），任一成功即返回并缓存。
- 📋 **例句自动记录**：自动读取剪贴板，找到包含该词的句子则提取并翻译保存；没有/不匹配则静默跳过。
- 🔍 **查词体验**：查询结果上方始终显示你刚刚查的单词；输入栏查完自动清空；慢查询不会覆盖新查询结果。
- ⌨️ **键盘浏览**：面板内容较多时，可用 `↑ / ↓` 方向键滚动浏览。
- 🧠 **识读复习**：看英文（有原文则贴原文）→ 键入中文意思（无选项）→ 展示原文与正确释义 → 自评 0～10 掌握度。
- ⏱️ **当天高密度复习**：前 3 次复习按 2h → 4h → 8h 短间隔，之后进入 1 天 → 6 天 → interval × ease；手机端在 08:00–22:00 每 2 小时提醒一轮。
- 📈 **自适应记忆曲线**：基于 SM-2/FSRS 风格算法，高分拉长间隔、低分拉短间隔，用户无需理解细节。
- 📚 **单词本**：搜索、编辑、删除、导入（CSV/JSON/TXT）、导出（CSV，可导入 Anki）。
- 📊 **统计与打卡**：今日新增/复习/平均自评、连续打卡、当前词汇本词数/已掌握/待复习。
- 🎨 **新野兽派 UI**：粗黑描边、硬阴影、高饱和色块；桌宠复用 `素材/` 目录 GIF。

## 界面预览

| 查词 | 识读复习 | 单词本/词汇本 |
| --- | --- | --- |
| ![查词](ui-preview.png) | ![复习](ui-preview-review.png) | ![单词本](ui-preview-words.png) |

## 运行

```bash
npm install
npm start
```

> 需要 Node.js 18+。首次安装会下载 Electron；项目内置 `.npmrc` 与 `scripts/ensure-electron.js`，使用 npmmirror 镜像自动补齐二进制。
> 可用 `npm test` 运行自动化冒烟测试（查词 + 复习流程）。

## 打包为 exe

```bash
npm install
npm run dist
```

产物在 `dist/` 目录：

- `单词桌宠-0.3.6-Setup.exe` —— 安装版（NSIS，可选择安装目录）
- `单词桌宠-0.3.6-Portable.exe` —— 绿色便携版，双击即用

> 已配置 electron-builder（NSIS + Portable），应用图标为 `assets/icon.ico`；`dist/` 已在 `.gitignore` 中忽略，不会提交到 git。

## 使用提示

| 操作 | 方式 |
| --- | --- |
| 呼出输入栏 | 全局快捷键 `Alt + W`，或点击桌宠，或托盘菜单 |
| 隐藏输入栏 | `Alt + E`，或再次点击桌宠 |
| 显示/隐藏桌宠 | `Alt + P`（或托盘"显示 / 隐藏桌宠"） |
| 查词 | 输入英文单词回车；查询后自动入当前词汇本 |
| 切换词汇本 | 单词本页顶部下拉框；"新建"可创建自定义词汇本 |
| 删除词汇本 | 单词本页顶部"删除"按钮（仅自建词汇本可删，内置四级/六级不可删） |
| 例句 | 查词前/时剪贴板里恰好有包含该词的句子，会自动记录 |
| 复习 | 进入"复习"页；答完自评 0～10；支持跳过/已会 |
| 开机自启动 | 设置页勾选"开机自启动" |
| 导入词表 | CSV/TXT 每行 `单词,释义`（可加 `,例句,例句译文`），JSON 为对象数组；勾选“导入后自动补全释义”可用离线/在线词典补全单薄释义 |

## 项目结构

```
单词桌宠/
├── main.js               # Electron 主进程：窗口/托盘/快捷键/自启动/剪贴板/在线查词/翻译
├── preload.js            # 安全桥接（contextBridge）
├── LICENSE               # 双许可总括声明
├── LICENSE-CODE          # 代码 MIT 许可
├── LICENSE-ASSETS        # 素材 CC BY-NC-SA 4.0 许可
├── NOTICE                # 第三方归属/许可/数据来源声明
├── assets/
│   ├── tray-icon.png     # 托盘图标
│   ├── icon.png          # 应用图标（256x256）
│   └── icon.ico          # Windows 图标
├── scripts/
│   ├── ensure-electron.js# 自动补齐 Electron 二进制
│   ├── build-cet6.js     # 从 cet-words-cli 生成内置六级词汇本
│   ├── build-cet4.js     # 从离线词典提取生成内置四级词汇本
│   ├── build-dict.js     # 从 cet-words-cli 生成完整离线词典（5760 词）
│   ├── make-icon.js      # 生成应用图标
│   └── make-tray-icon.js # 生成托盘图标
├── renderer/
│   ├── index.html        # 界面
│   ├── styles.css        # 新野兽派风格
│   ├── app.js            # 页面逻辑
│   ├── dictionary.js     # 离线词典索引 + 本地查询缓存
│   ├── dict-data.js      # 完整离线词典（CET4+CET6，5760 词，由脚本生成）
│   ├── cet6-data.js      # 内置 CET-6 词表（1945 词，由脚本生成）
│   ├── cet4-data.js      # 内置 CET-4 词表（3815 词，由脚本生成）
│   └── scheduler.js      # SM-2/FSRS 风格自适应调度
└── 素材/                 # 桌宠 GIF（直接复用）
```

## 数据

- 数据保存在 Electron 用户数据目录：`%APPDATA%/word-pet/word-pet-data.json`。
- 可在"设置"里导入示例词；"单词本 → 导出"可备份（CSV 带 BOM，Excel 可直接打开）。
- 在线查词仅在用户主动查询时，把查询词发送给有道 / MyMemory / Free Dictionary API 等第三方服务；本项目不上传词库，也不收集任何账户信息。接口数据版权归原站，详见 [NOTICE](NOTICE)。

## 后续规划

- UIA 前台选中文本读取、OCR 截图取词
- 发音朗读、自适应 FSRS 完整实现
- 自定义桌宠形象与更多动画状态
- 安装包与自动更新

## 📄 许可声明（双许可）

本项目采用「代码 / 素材」分离的双许可模式，总括说明见 [LICENSE](LICENSE)，第三方归属与数据说明见 [NOTICE](NOTICE)：

| 范围 | 许可证 |
| --- | --- |
| 源代码（`main.js`、`preload.js`、`renderer/`、`scripts/` 等全部代码与配置文件，及脚本生成的应用/托盘图标） | [MIT](LICENSE-CODE) |
| 表情包素材（`素材/` 内全部 GIF 动画） | [CC BY-NC-SA 4.0](LICENSE-ASSETS) |

> 打包产物（`dist/*.exe`）会包含 `LICENSE`、`LICENSE-CODE`、`LICENSE-ASSETS`、`NOTICE` 与 `README.md`。

### 素材版权与署名

本项目包含的「蓝色大肥鱼」表情包素材，其版权链如下：

- **原创角色「鲸鱼娘'溟月'」**：© [@上善无形](https://space.bilibili.com/4456176)（B站）
- **「女仆鲸鱼娘（DS鲸鱼娘）」二创形象**：© [@ZipZipPipe](https://space.bilibili.com/4168597)（B站）
- **「蓝色大肥鱼」表情包**：© [@赤风RED LUE UP](https://space.bilibili.com/356746604)（B站）

以上素材的著作权与许可权归原作者所有，原作者以 **[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)** 协议授权：可自由分享与改编，但**不得用于商业用途**；二次分发或演绎时须以相同协议授权，并完整保留上述署名信息。

> 本项目为非商业的同人/学习性质作品，与上述原作者无隶属关系。如版权方提出要求，本项目将及时移除相关素材。
