# Atlas Profile Toolkit

一个面向 macOS 用户的 ChatGPT Atlas 环境保全工具。

如果你经常需要切换到新的 Atlas 账号，但又不想每次都从零重新配置书签、扩展程序、浏览历史、第三方网站登录状态，这个项目就是为这个场景写的。

## 适用人群

这个项目主要适合下面这类用户：

- 经常切换到新的 ChatGPT Atlas 账号
- 希望保留浏览器环境，而不是每次重装扩展、重登网站
- 使用的是 macOS 上的 ChatGPT Atlas
- 能接受“尽量保留大部分环境”，而不是承诺 100% 完美复制所有状态

如果你只是偶尔换一次账号，手动重新登录并不麻烦，那这个工具未必值得引入。

## 这个项目解决什么问题

每次切换到新的 Atlas 账号时，常见痛点通常是：

- 书签没了
- 扩展程序没了
- 浏览历史没了
- YouTube、B站、小红书、闲鱼之类网站要重新登录
- 浏览器偏好设置和使用习惯丢了

这个工具的目标不是“克隆旧账号”，而是把你的 Atlas 浏览器环境做成一个可复用模板，然后在新账号上重新接入这份模板。

## 用户故事

### 用户故事 1：每个月都换一个新的 Atlas 账号

你平时一直在用 Atlas 工作，慢慢积累了很多：

- 常用书签
- 扩展程序
- 浏览记录
- 一些已经登录好的第三方网站

到了下个月，你需要登录一个全新的 Atlas 账号。  
你不想再从头装一遍环境，于是你先把当前环境刷新成模板，然后在新账号登录完成后，把模板注入到当前新 profile 里。

结果是：

- 你当前的新 Atlas 账号保持不变
- 旧环境里的大部分书签、扩展、历史和第三方网站状态回来

### 用户故事 2：新账号登录成功了，但环境是空的

Atlas 有时会为新账号创建一个全新的 `user-*` profile。  
这时你会看到“账号已经登录了，但书签、扩展和历史都不见了”。

这种情况下，关闭 Atlas，运行一次 `inject-active`，再重新打开即可。  
它的目标就是把模板注入到这个新 profile，同时尽量保住你刚刚登录好的 Atlas 账号状态。

### 用户故事 3：模板也需要持续更新

模板不是一劳永逸的。

随着时间推移：

- 你会新增书签
- 你会调整扩展
- 你会积累新的浏览历史
- 某些第三方网站登录态会变化

所以在下一次切换账号之前，最好先运行一次 `refresh-master`，把当前最新环境刷新进模板。

## 它的工作方式

这个工具把 Atlas 当成一套类似 Chromium 的 profile 目录来处理。

核心思路是：

1. 从当前活跃 profile 提取一份“模板环境”
2. 把 Atlas / OpenAI 自己的登录态从模板里清掉
3. 在需要的时候，把模板重新注入到新的 active profile
4. 注入时尽量保住当前这个新 Atlas 账号的登录态

换句话说，它保的是“浏览器环境”，不是“旧 Atlas 账号本身”。

## 能保留什么

通常会尽量保留这些内容：

- 浏览历史
- 书签
- 扩展程序
- 浏览器偏好设置
- 很多第三方网站的 Cookie 和本地存储

## 不会保留什么

模板里会主动清掉这些 Atlas / OpenAI 相关状态：

- `chatgpt.com`
- `openai.com`
- `auth.openai.com`
- 相关的 OpenAI / Auth0 / Sentinel Cookie 和本地存储痕迹

这是故意的。  
如果不清掉，模板可能会把旧 Atlas 账号一起带回来，反而和“切换到新账号”这个目标冲突。

## 快速上手

### 1. 克隆仓库

```bash
git clone https://github.com/fargoboxs-web/atlas-profile-toolkit.git
cd atlas-profile-toolkit
```

### 2. 查看 Atlas 当前 profile

```bash
./scripts/atlas-profile-toolkit.sh list
```

### 3. 先把当前环境保存成模板

```bash
./scripts/atlas-profile-toolkit.sh refresh-master
```

### 4. 在切换到下一个 Atlas 账号前预热 staging

```bash
./scripts/atlas-profile-toolkit.sh prepare-switch
```

### 5. 新账号登录后，如果环境是空的，就把模板注入当前 active profile

```bash
./scripts/atlas-profile-toolkit.sh inject-active
```

## 推荐工作流

### 场景 A：你还没切账号

在旧账号还正常可用、环境是最新的时候：

```bash
./scripts/atlas-profile-toolkit.sh refresh-master
./scripts/atlas-profile-toolkit.sh prepare-switch
```

然后再去登录新的 Atlas 账号。

### 场景 B：你已经登录了新账号，但环境是空的

关闭 Atlas，然后运行：

```bash
./scripts/atlas-profile-toolkit.sh inject-active
```

再重新打开 Atlas。

目标状态是：

- 当前 Atlas 新账号仍然保持登录
- 模板里的历史、书签、扩展、设置被注入进来
- 第三方网站状态尽量跟着回来

### 场景 C：你想只做“粗暴恢复”

如果你明确不在乎 Atlas 账号状态，只想把当前 active profile 整体替换成模板，可以用：

```bash
./scripts/atlas-profile-toolkit.sh restore-active
```

但通常这意味着你之后要重新登录 Atlas，不是首选。

## 命令说明

在仓库根目录运行：

```bash
./scripts/atlas-profile-toolkit.sh <command>
```

可用命令如下：

- `list`
  列出这台机器上的 Atlas profiles，并标记当前 active profile。

- `refresh-master [name]`
  从某个 profile 刷新模板，并把模板中的 Atlas/OpenAI 登录态清掉。  
  不传 `name` 时，默认使用当前 active profile。

- `capture-master [name]`
  `refresh-master` 的兼容别名。

- `prepare-switch`
  把模板写入 `login-staging*` 和 `Default`，用于下次切换账号前预热环境。

- `inject-active`
  把模板注入当前 active profile，同时尽量保留当前新 Atlas 账号的登录态。

- `restore-active`
  直接用模板替换当前 active profile。更粗暴，也更容易导致你需要重新登录 Atlas。

- `open`
  打开 Atlas。

## 默认路径

脚本默认面向下面这组 macOS 路径：

- app: `/Applications/ChatGPT Atlas.app`
- Atlas root: `~/Library/Application Support/com.openai.atlas`
- host profiles: `~/Library/Application Support/com.openai.atlas/browser-data/host`

如果你的路径不同，可以通过环境变量覆盖这些路径。

## 备份机制

每次发生覆盖类操作时，脚本都会自动创建时间戳备份。

备份目录默认在：

```bash
~/.atlas-profile-kit/backups
```

模板目录默认在：

```bash
~/.atlas-profile-kit/master-profile
```

## 安全与风险边界

这类工具本质上是在处理浏览器 profile 数据，所以有几个现实边界必须提前说清楚：

- 它不是 Atlas 官方提供的同步方案
- 它无法保证所有站点的登录态都永久可复活
- 某些网站会因为风控、Cookie 过期、设备识别而要求重新登录
- 如果 Atlas 未来更改内部 profile 布局，脚本可能需要调整

换句话说，这个工具追求的是：

`尽量保住 80% 到 95% 的浏览器环境，显著减少重复劳动`

而不是承诺：

`100% 无损、永久、跨一切版本和网站地复制所有状态`

## 常见问题

### 1. 它会保留历史记录吗？

会。模板里默认会保留历史记录。

### 2. 它会保留书签和扩展程序吗？

会，这是核心目标之一。

### 3. 它会保留 YouTube、B站、小红书、闲鱼这些网站的登录态吗？

会尽量保留，但不能保证全部永久有效。  
有些网站风控更严格，仍然可能要求重新登录。

### 4. 它会保留旧的 Atlas 账号吗？

不会。模板会主动清理 Atlas / OpenAI 自己的登录态，避免把旧账号一起带回来。

### 5. 为什么我切账号后看到的是一个新的空 profile？

因为 Atlas 有时会为不同账号创建新的 `user-*` profile。  
这不是你的旧数据丢了，而是 Atlas 切到了另一套 profile。

### 6. 什么时候应该运行 `refresh-master`？

下一次准备切账号之前。  
尤其是当你最近新增了书签、扩展、历史，或者重新登录了很多第三方网站时。

## 测试

运行集成测试：

```bash
bash ./tests/test_atlas_profile_toolkit.sh
```

## Roadmap

当前已经支持：

- 模板刷新
- 切号前 staging 预热
- 新 active profile 模板注入
- 自动备份

后续可能继续补：

- 更细粒度的状态检查命令
- 更清晰的诊断输出
- 更完善的路径自动探测
- 更适合普通用户的安装方式
