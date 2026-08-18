# CodexBar（fork）功能测试文档

## 1. 元信息 / 变更记录

| 字段 | 值 |
| --- | --- |
| 状态 | 生效 |
| Owner | Bearisbug |
| 关联设计文档 | `docs/claude-native-multi-account-clash.md` |
| 被测系统 | CodexBar 菜单栏 app（本仓库打包产物 `CodexBar.app`） |
| 最后更新 | 2026-07-17 |

变更记录（登用例增改，不登执行轮次）：

| 日期 | 改动 | 作者 |
| --- | --- | --- |
| 2026-07-17 | 初稿，TC-001~015（Claude 原生多账号 + Clash 联动域） | Bearisbug |
| 2026-07-17 | TC-010/TC-015 措辞随设计 v1.2 修正：菜单切换器为原生 NSMenu 行 | Bearisbug |
| 2026-07-17 | 随设计 v1.4：切换事务新增 token 过期刷新（API-004），刷新路径归自动化单测覆盖（§2 登记）；TC-003/TC-008 复测应不再出现 401 误判 | Bearisbug |
| 2026-07-17 | 随设计 v1.5：TC-003 步骤 1 预期补「切换全程无钥匙串授权弹窗」（凭据位重建改为 SecItem + 预授权 ACL） | Bearisbug |
| 2026-07-17 | 随设计 v1.6：校验降为 advisory——废弃 TC-004，新增 TC-016（断网切换未校验放行）；TC-003 弹窗预期依据改为缓存种子机制（写入回退 security CLI） | Bearisbug |
| 2026-07-17 | 随设计 v1.7：新增 TC-017（登录新账号，REQ-009） | Bearisbug |
| 2026-07-18 | 随设计 v1.8：TC-010/TC-015 预期改为分段切换器（活跃高亮、无备份置灰）；显隐与合并模式渲染已由无头测试覆盖 | Bearisbug |
| 2026-07-18 | 缺陷回归：TC-010 新增步骤 4（菜单保持打开跨一次数据刷新，切换器不消失）——smart update 重建路径曾丢弃原生切换器，已由无头测试 `test_nativeSwitcherSurvivesSmartUpdateInMergedMode` 覆盖 | Bearisbug |
| 2026-07-18 | 随设计 v1.9：TC-010 步骤 1 预期补「活跃按钮文字不压暗」、新增步骤 5（卡片邮箱跟随活跃账号）；TC-003 弹窗预期不变但实现补全（OAuth 缓存种子同步对齐钥匙串指纹），复测应全程零弹窗。无头覆盖：`seed_aligns_claude_keychain_fingerprint_so_freshness_sync_skips_item_read`、`test_nativeSwitcherKeepsActiveSegmentEnabled`、`maps_O_auth_usage_email_from_active_native_account` | Bearisbug |
| 2026-08-10 | 随设计 v1.10：TC-017 按 ADR-006 重写（PTY + 隐私窗口 + 粘贴 code），新增取消与错误分支步骤；解析逻辑由无头套件 `ClaudeAccountLoginSessionTests` 覆盖 | Bearisbug |

## 2. 测试范围 / 不测什么

- 覆盖：Claude 原生多账号（收录/切换/绑定/导入）与 Clash 联动的黑盒功能验收——菜单栏 UI、设置窗格、系统凭据位与 Clash 实机效果、日志隐私。
- 不测：

| 不测项 | 归属 |
| --- | --- |
| 单元 / 集成自动化（状态机迁移全集与回滚序列、CCSwitcher 字段映射 §25、Clash 响应解析、切换事务串行化 ERR-SWITCH-IN-PROGRESS、错误码分派、token 过期刷新与 401 重试 API-004） | 代码仓测试套件 `Tests/CodexBarTests`（策略见设计文档 §19；连点拒绝与刷新场景由单测覆盖，不设 TC） |
| claude-swap 适配器自身行为 | 上游既有测试与 `docs/claude.md`（本期零改动，仅测「启用时原生切换器隐藏」的交互面） |
| Clash Verge Rev 本身的代理转发正确性 | 外部软件，无归属——已知风险（本文档只验证「组内选中节点被切换」） |
| 性能压测 / 安全渗透 | 无归属——个人工具，已知风险 |

## 3. 环境与前置

- 启动：`./Scripts/compile_and_run.sh`（构建、打包、重启 `CodexBar.app` 并确认保持运行）；就绪判定：脚本输出确认 app 存活，菜单栏出现 CodexBar 图标。（冷启动已于 RUN-001 走通：打包成功、app 持续存活 ≥3 分钟无崩溃。）
- 入口：菜单栏 CodexBar 图标（Claude 菜单卡片）；设置窗口 Preferences → Providers → Claude → Accounts 区。
- 测试账号：

| 角色 | 账号 | 获取方式 |
| --- | --- | --- |
| 真实 Claude 账号 ×4（人工用例） | Zyeon / Dotra / Claude#1 / Claude#2（邮箱见 CCSwitcher 面板，文档不落邮箱） | 已在本机 CCSwitcher 中维护，含凭据备份与节点绑定 |
| 合成账号（AI 用例，仅展示层） | `synthetic-a@example.com`、`synthetic-b@example.com` | 直接写入 `~/Library/Application Support/CodexBar/managed-claude-accounts.json`（无凭据备份，天然「需收录」不可切换，绝不触发真实切换与钥匙串） |

- 种子数据与重置：
  - 基线重置：退出 app → 删除 `~/Library/Application Support/CodexBar/managed-claude-accounts.json` → 重启 app（Accounts 区回到空态）。CodexBar 自建的备份钥匙串条目经设置区「删除账号」清理。
  - 合成种子（AI 用例）：向上述 JSON 写入 2 个仅含元数据的账号（字段见设计文档 §9），`clashGroup/clashNode` 留空。
  - 「已导入过一次」状态（TC-009 前置）：先执行 TC-008。
- Clash 前置（TC-005/006/007）：Clash Verge Rev 运行中，`ls /tmp/verge/verge-mihomo.sock` 存在即就绪；TC-007 需要退出 Clash Verge 构造不可达。
- CCSwitcher 前置（TC-008/009）：`defaults read me.xueshi.ccswitcher com.ccswitcher.accounts` 有输出；钥匙串存在 service `me.xueshi.ccswitcher.backups` 条目。
- 工具：人工用例=肉眼观察 + `screencapture`；AI 用例=文件断言（JSON/日志）+ 菜单截图；日志查看：Console.app 或 app 日志文件过滤 category `claude-accounts`。
- 证据目录：`docs/test-runs/`（截图/日志摘录，引用以项目根为基准的相对路径）。

## 4. 用例库

### Claude 原生多账号 + Clash 联动

#### `TC-001` 收录当前账号（首个账号） — 对应 `REQ-001` · 级别: 冒烟 · 执行者: 人工

前置：基线重置完成；当前机器 Claude Code 已登录某账号（钥匙串有 `Claude Code-credentials` 且 `~/.claude.json` 有 `oauthAccount`）。

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | 打开 Preferences → Providers → Claude，找到 Accounts 区 | 空态：仅「添加当前账号」与「Import from CCSwitcher…」按钮，无账号行 |
| 2 | 点击「添加当前账号」 | 列表出现 1 行，邮箱 = 当前登录账号邮箱，带活跃标记（圆点/高亮） |
| 3 | 重启 app 后再看 Accounts 区 | 该账号仍在（元数据已持久化到 managed-claude-accounts.json） |

后置：无（保留账号供后续用例）。

#### `TC-002` 收录去重（同邮箱刷新备份） — 对应 `REQ-001` · 级别: 回归 · 执行者: 人工

前置：TC-001 已完成，列表已有当前账号。

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | 再次点击「添加当前账号」 | 列表行数不变（无重复行）；无报错 |

后置：无。

#### `TC-003` 无绑定账号切换成功 — 对应 `REQ-002` `REQ-003` · 级别: 冒烟 · 执行者: 人工

前置：列表 ≥2 个有备份的账号（可先跑 TC-008 导入）；目标账号「Clash 节点」下拉为「不绑定」；记录 Clash Verge 当前选中节点。

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | 在菜单或设置区点击目标（非活跃）账号的切换 | 数秒内活跃标记移到目标账号；**全程无钥匙串授权弹窗**（设计 v1.6：切换后种子 OAuth 缓存，CodexBar 不直读钥匙串条目） |
| 2 | 查看 Claude 菜单用量卡片 | 显示目标账号的用量/身份（与原账号数值明显不同或邮箱不同） |
| 3 | 打开 Clash Verge 面板 | 选中节点与切换前完全一致（未被触碰） |
| 4 | 终端跑 `claude /status`（或新开 Claude Code 会话看账号） | 显示目标账号邮箱 |

后置：无。

#### `TC-004` 校验失败自动回滚（断网模拟） — 已废弃，被 `TC-016` 取代

设计 v1.6 起校验为 advisory：网络不可用不再回滚，本用例语义失效。

#### `TC-016` 断网时切换未校验放行 — 对应 `REQ-002` · 级别: 回归 · 执行者: 人工

前置：列表 ≥2 个有备份账号（目标账号未绑定 Clash 节点）；记录当前活跃账号邮箱；断开网络（关 Wi-Fi）。

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | 点击切换到另一账号 | 切换完成、活跃标记移到目标账号，无「已回滚」类报错（用量卡片可显示获取失败/陈旧） |
| 2 | 终端跑 `claude /status` | 显示目标账号邮箱（凭据位已切换） |
| 3 | 恢复网络后点刷新 | 用量卡片恢复显示目标账号数据 |

后置：恢复 Wi-Fi。

#### `TC-005` 绑定节点保存与实时拉取 — 对应 `REQ-003` · 级别: 冒烟 · 执行者: 人工

前置：Clash Verge 运行中（socket 就绪）；列表 ≥1 账号。

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | 展开某账号行的「Clash 节点」下拉 | 选项 =「不绑定」+ GLOBAL 组实际节点列表（与 Clash Verge 面板一致） |
| 2 | 选择节点 N | 下拉显示 N；无报错 |
| 3 | `cat ~/Library/Application\ Support/CodexBar/managed-claude-accounts.json` | 该账号 `clashGroup:"GLOBAL"`、`clashNode:"N"` |

后置：按需要还原绑定。

#### `TC-006` 绑定账号切换先切代理 — 对应 `REQ-004` · 级别: 冒烟 · 执行者: 人工

前置：目标账号绑定节点 N（≠ Clash 当前选中）；目标账号有备份；网络正常。

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | 切换到目标账号 | 切换成功，活跃标记移动 |
| 2 | 打开 Clash Verge 面板看 GLOBAL 组 | 选中节点已变为 N |
| 3 | 查看 `claude-accounts` 日志该事务段 | Clash PUT 日志行早于凭据写入日志行 |

后置：无。

#### `TC-007` Clash 不可达时中止且凭据未动 — 对应 `REQ-004` · 级别: 回归 · 执行者: 人工

前置：目标账号绑定了节点；完全退出 Clash Verge（`ls /tmp/verge/verge-mihomo.sock` 不存在）；记录当前活跃账号。

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | 切换到该目标账号 | 提示 `ERR-CLASH-UNREACHABLE`（含检查 Clash 运行/socket 路径的引导） |
| 2 | 查看活跃标记与 `claude /status` | 均为原账号（凭据完全未动） |
| 3 | 设置区 Clash 连接状态行 | 显示不可达状态 |

后置：重启 Clash Verge。

#### `TC-008` CCSwitcher 全量导入 — 对应 `REQ-005` · 级别: 冒烟 · 执行者: 人工

前置：基线重置（Accounts 空）；CCSwitcher 前置就绪（§3）；CCSwitcher 中有 4 个 Claude 账号（Zyeon/Dotra/Claude#1/Claude#2）及节点绑定。

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | 点击「Import from CCSwitcher…」 | 弹出系统钥匙串授权框（针对 CCSwitcher 备份条目） |
| 2 | 点「允许」 | 结果提示：4 导入 / 0 跳过；列表出现 4 行 |
| 3 | 逐行核对别名/订阅/节点绑定 | Zyeon→Self、Dotra→Goh、Claude#1→ClaudeN1、Claude#2→ClaudeN2，组均 GLOBAL，订阅均 Max |
| 4 | 查看活跃标记 | 落在与当前 `~/.claude.json` 邮箱一致的账号上（而非 CCSwitcher 的旧标记） |
| 5 | 任选一账号看切换按钮 | 可点击（备份已随导入写入,无「需收录」标记） |

后置：无（保留导入结果供 TC-003/006 使用）。

#### `TC-009` 重复导入幂等 — 对应 `REQ-005` · 级别: 回归 · 执行者: 人工

前置：先执行 TC-008。

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | 再次点击「Import from CCSwitcher…」并允许授权 | 结果提示：0 导入 / 4 跳过；列表仍 4 行无重复 |

后置：无。

#### `TC-010` 菜单切换器显隐 — 对应 `REQ-006` · 级别: 回归 · 执行者: 皆可

前置：合成种子写入 2 个账号（§3；AI 执行用合成账号，不点击切换）；claude-swap 未启用。

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | 打开 Claude 菜单 | 顶部出现账号分段切换器（每账号一枚按钮显示别名），活跃账号高亮且文字不压暗（enabled 态，白字清晰；回归项：曾因 disabled 被系统压灰） |
| 2 | 编辑 JSON 只留 1 个账号，重启 app 后开菜单 | 账号小节不出现，菜单与改动前基线一致 |
| 3 | 恢复 2 账号，设置里启用「Read accounts from claude-swap」（路径随意填），重开菜单 | 原生账号行隐藏（ADR-005）；关闭该开关后恢复显示 |
| 4 | 保持 Claude 菜单打开，等待或触发一次数据刷新（约 1 分钟内的自动 tick 即可） | 切换器持续存在、不闪失（回归项：smart update 重建曾丢弃它；无头测试 `test_nativeSwitcherSurvivesSmartUpdateInMergedMode` 覆盖同场景） |
| 5 | 看 Claude 用量卡片头部右侧（OAuth 用量源） | 显示活跃账号邮箱（Hide Personal Info 开启时遮蔽）；切换账号后邮箱跟随变化，不再空白 |

后置：关闭 claude-swap 开关；清理合成种子。

#### `TC-011` 设置区管理：改别名与删除 — 对应 `REQ-007` · 级别: 回归 · 执行者: 皆可

前置：合成种子 2 账号（AI）或导入后的真实账号（人工）。

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | 把账号 A 别名改为「主号」 | 行内即时显示「主号」；菜单切换器同步显示「主号」 |
| 2 | `cat` managed-claude-accounts.json | A 的 `customLabel:"主号"` |
| 3 | 删除账号 B | 行消失；JSON 中 B 整条移除；若 B 有备份，重新添加同邮箱账号后显示「需收录」（备份条目已随删除清理） |

后置：清理测试改动。

#### `TC-012` 日志隐私：零 token 零邮箱 — 对应 `REQ-008` · 级别: 回归 · 执行者: 皆可

前置：本轮已执行过至少一次切换（TC-003/006）与一次导入（TC-008）；AI 执行时可仅基于合成账号操作（收录失败路径 + 菜单渲染）产生日志。

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | 导出 `claude-accounts` 类别全部日志，搜索 `sk-ant` | 零命中 |
| 2 | 搜索本机各账号邮箱字符串（含 `@`） | 零命中（账号以 UUID 指代） |
| 3 | 抽查一条切换事务日志 | 各行带同一事务短 UUID 前缀 |

后置：无。

#### `TC-013` Hide Personal Info 遮蔽邮箱 — 对应 `REQ-008` · 级别: 边缘 · 执行者: 皆可

前置：合成种子 2 账号；找到现有 Hide Personal Info 开关（General 设置）。

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | 开启 Hide Personal Info，看菜单切换器与 Accounts 区 | 邮箱显示为遮蔽形式（与现有 Claude 卡片遮蔽风格一致）；别名不遮蔽 |
| 2 | 关闭开关 | 邮箱恢复明文 |

后置：还原开关。

#### `TC-014` 空态呈现 — 对应 `REQ-007` · 级别: 边缘 · 执行者: 皆可

前置：基线重置（无任何原生账号）。

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | 打开 Accounts 区 | 仅「添加当前账号」+「Import from CCSwitcher…」（CCSwitcher plist 不存在时导入按钮隐藏或置灰并说明）；无账号行 |
| 2 | 打开 Claude 菜单 | 无切换器，与功能加入前的菜单一致 |

后置：无。

#### `TC-015` 备份缺失账号不可切换 — 对应 `REQ-002` · 级别: 边缘 · 执行者: 皆可

前置：合成种子 2 账号（仅元数据，无备份条目）。

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | 查看设置区两个合成账号行 | 均带「needs capture」标记，Switch 按钮置灰（`ERR-BACKUP-MISSING` 语义） |
| 2 | 打开 Claude 菜单分段切换器点击合成账号按钮 | 按钮置灰不可点；`claude-accounts` 日志无 `switch` 事务开始行 |

后置：清理合成种子。

#### `TC-017` 登录新账号 — 对应 `REQ-009` · 级别: 回归 · 执行者: 人工

前置：`claude` CLI 可用；列表已有活跃账号 A（有备份）；手头有另一个可登录的 Claude 账号；浏览器当前已登录账号 A（构造「登录态复用」风险场景）。

| # | 操作 | 预期 |
| --- | --- | --- |
| 1 | Accounts 区点击「Login new account…」 | 弹出登录弹窗，显示授权链接；**隐私窗口**（Edge/Chrome）自动打开 Claude 登录页且**未沿用账号 A 的登录态**（要求重新登录）；按钮区进入忙碌态；无 `Socket is closed` 报错 |
| 2 | 在隐私窗口用新账号完成登录，复制页面给出的 code 粘贴进弹窗 → Sign in | 弹窗关闭；列表新增该账号并标活跃；提示「Signed in and captured …」 |
| 3 | 点击原账号 A 的 Switch | 可正常切回（A 的备份在登录前已刷新） |
| 4 | 再次点击「Login new account…」，弹窗直接点取消 | 弹窗关闭并提示已取消；`ps` 中无残留 `claude auth login` 进程；账号列表不变 |
| 5 | 再次登录，在 code 框输入无效字符串提交 | 提示登录失败并附 CLI 失败行；账号列表不变；账号 A 凭据不受影响 |

后置：无。

## 5. 回归策略

- **全量轮**（全部用例）：首次成稿、里程碑、跨功能域改动、地基变更（环境/鉴权/数据模型）。
- **局部轮**（受影响用例 + 全部冒烟级）：单一功能改动。受影响用例 = 本次改动触及的 `REQ-*` 反查对应 TC；无 REQ 变更的改动按触及功能域圈定；影响面不确定时升级全量轮。
- **复测轮**（上轮失败用例 + 全部冒烟级）：修复失败项之后。
- **人工收口轮**（仅上轮「待人工」用例）：AI 轮之后由人工补测收口，不要求冒烟级。

## 6. 执行记录

轮次汇总：

| 轮次 | 日期 | 被测版本 | 执行者 | 范围 | 结果 |
| --- | --- | --- | --- | --- | --- |
| RUN-001 | 2026-07-17 | b7920f1a + 未提交工作区（本功能全部变更） | AI(Claude Code) | 全量 | 待人工 15 · 阻塞 0（环境冷启动通过；自动化套件 58/58 组全绿另见交付说明） |
| RUN-002 | 2026-07-18 | 48cb4e63 + 未提交工作区（smart update 丢弃原生切换器修复） | AI(Claude Code) | 局部（TC-010；冒烟级 TC-001/003/005/006/008 需真实凭据仍待人工） | 自动化 4/4 绿（含新增无头用例复现步骤 4 场景）；打包 app 重启成功，TC-010 步骤 4 实机观察待人工 |
| RUN-003 | 2026-07-18 | 48cb4e63 + 未提交工作区（v1.9 三缺陷修复：切换弹窗/活跃按钮压暗/卡片邮箱空白） | AI(Claude Code) | 局部（TC-003 弹窗预期 + TC-010 步骤 1/5；冒烟级人工项同前待人工） | 三个新增无头用例绿 + 受影响套件全绿；实机复测待人工 |
| RUN-004 | 2026-08-10 | a4d638ee + 未提交工作区（REQ-009 登录改 PTY + 隐私窗口 + 粘贴 code） | AI(Claude Code) | 局部（TC-017；冒烟级人工项同前待人工） | 无头 43/43 绿（含新增 `ClaudeAccountLoginSessionTests` 5 例）；TC-017 需真实第二账号，实机待人工 |

明细（仅登非「通过」项）：

| 轮次 | 用例 | 结果 | 现象 / 证据 | 跟进 |
| --- | --- | --- | --- | --- |
| RUN-001 | TC-001~TC-009 | 待人工 | 需真实 Claude 凭据、系统钥匙串授权弹窗、Clash Verge 实机操作，AI 按红线不触碰真实凭据 | 交用户按用例执行（人工收口轮） |
| RUN-001 | TC-010~TC-015 | 待人工 | 菜单栏/设置窗口 UI 观察项，无人值守自动化点击不可靠；AI 已验证的替代证据：打包 app 启动并持续存活 ≥3 分钟、无账号文件时功能休眠（App Support 无 managed-claude-accounts.json、日志无 claude-accounts 条目，即 TC-014 步骤 2 的「与基线一致」侧证） | 交用户按用例执行（人工收口轮） |
| RUN-002 | TC-010 | 待人工 | 用户实机曾复现步骤 4 缺陷（旧 10:10 打包产物未含修复）；无头测试 `test_nativeSwitcherSurvivesSmartUpdateInMergedMode` 通过（开菜单→数据 tick 走 smart update→切换器仍在）；11:15 已重新打包并启动带修复版本 | 交用户开菜单跨一次刷新确认切换器不消失 |
| RUN-003 | TC-003 | 待人工 | 用户实机复现「每次切换都弹钥匙串授权、始终允许不生效」；根因：切换 delete+add 重建条目销毁 ACL 授权 + OAuth freshness 同步把自家写入当外部变更去重读条目密文（ACL 转储佐证：条目 11:23 重建、CodexBar 被用户手点进 applications 列表）；修复：种子同步对齐钥匙串指纹，无头测试 `seed_aligns_claude_keychain_fingerprint_so_freshness_sync_skips_item_read` 通过 | 交用户实机切换确认全程零弹窗 |
| RUN-003 | TC-010 | 待人工 | 用户实机复现步骤 1「活跃按钮压暗如禁用」与步骤 5「卡片邮箱空白」；无头测试 `test_nativeSwitcherKeepsActiveSegmentEnabled`、`maps_O_auth_usage_email_from_active_native_account` 通过 | 交用户实机确认高亮清晰、邮箱跟随切换 |
| RUN-004 | TC-017 | 待人工 | 用户实机报「Signing in a new account failed: Command failed (1): Login failed: Socket is closed」；根因实证：CLI 2.1.226 登录已改为交互式粘贴 code 流程（stdin=/dev/null、stdin 关闭、真 PTY 三种形态实测均为 `redirect_uri=platform.claude.com` + `Paste code here if prompted >`），无终端子进程读已关闭 stdin 必失败，CCSwitcher 同款实现在此 CLI 版本同样失效；修复为 PTY 会话 + 应用内粘贴 code + 隐私窗口打开授权链接 | 交用户按重写后的 TC-017 实测（需第二个可登录账号） |
| RUN-003 | （套件基建） | 已修复 | 全量轮暴露环境泄漏：上游 `StatusMenuSwitcherRefreshTests` 未隔离原生账号集，开发机存在真实 managed-claude-accounts.json（≥2 账号）时切换器被渲染进合并菜单、行骨架变化致 `merged_provider_switch_updates_live_tab_rows_in_place` 失败——套件 init 固定空账号集后 15/15 过，与本轮功能修复无关 | 无 |

## 7. 遗留问题

- 上游测试 `GeminiStatusProbeAPITests.refreshes_expired_token_with_fnm_bundle_layout_when_fnm_keeps_stdout_open` 在全量并行跑时偶发失败（fnm-child.pid 时序），隔离运行必过 — 接受理由：上游既有 flaky，与本功能无关，AGENTS.md 亦注明 macOS CI 脆弱；关联：RUN-001 前置的自动化套件轮次（第 4 轮偶发、第 5 轮通过）。
