# 迁移 / 部署到新主机（manbo 之类的第二台机）

目标目录：`~/github-project/research-radar`（`systemd/*.service` 里的路径写死为 `%h/github-project/research-radar`，换目录要同步改）。

## 0) 依赖
```bash
sudo pacman -S --needed git curl python rsync util-linux libnotify wl-clipboard
# OpenCode（≥2）：见官方安装方式；装完要登录一次，凭据不进 git：
opencode auth login      # 选 DeepSeek，用你自己的 key
```
可选（TUI/Emacs 增强）：`qdbus`（KDE 下把浏览器置顶）、`wl-copy`（复制链接）、`emacs`。

## 1) 拿到代码+数据（一条脚本）
打包端（旧机）：
```bash
tar czf radar-migrate.tar.gz research-radar
sudo tailscale file cp radar-migrate.tar.gz radar-manbo-setup.sh manbo:   # 脚本随包一起发
```
新机（manbo）：
```bash
mkdir -p ~/github-project && cd ~/github-project
sudo tailscale file get .        # 收下上面两个文件（get 通常要 root）
bash radar-manbo-setup.sh        # 取包→解包→修属主→依赖检查→建 radar 软链
```
`radar-manbo-setup.sh` 与仓库里的 `bin/radar-setup-host` 是同一个脚本。它也能在仓库里直接跑（做依赖检查/软链/可选装单元）：
```bash
research-radar/bin/radar-setup-host [--dir DIR] [--tar FILE] [--no-get] [--install-units] [--force]
```

## 2) 定时任务（用 generate_on 指定唯一主生成机）
在 `config.toml` 的 `[general]` 里设 `generate_on = "ColdFlsh"`（填主生成机的短主机名，取 `uname -n`）。
之后**只有该主机名的那台**会真正生成日报；其它机器 `radar run` 会先 `pull`、再直接退出（只同步、不生成）。
所以现在**可以两台都装 timer**：
```bash
cd ~/github-project/research-radar
bin/radar-setup-host --install-units    # 或直接 bin/radar-install-units
```
> `generate_on` 留空时退回旧行为：不限制主机，此时**只在一台开 timer**，否则同一天各生成一份会冲突。

## 3) 用 git 拉取代码 + 数据（替代 tar 打包）
代码仓（公开）与数据仓（私有）分开，`data/` 是被外层 `.gitignore` 忽略的嵌套仓，要单独 clone：
```bash
cd ~/github-project
git clone git@github.com:<你>/research-radar.git
cd research-radar
cp config.example.toml config.toml     # 再按需改（generate_on 等）
cp profile.example.md profile.md
git clone git@github.com:<你>/research-radar-data.git data
bin/radar --help
```

## 4) Emacs 侧（可选）
- 仓库里的 `emacs/radar.el` 是本体；
- 新机上建 `~/.emacs.d/lisp/init-radar.el` 把 `<repo>/emacs` 加进 `load-path` 并 `(require 'radar)`，绑定入口（如 `C-c R`）；
- `C` 细聊用 agent-shell（`opencode acp`）。**opencode 的 session 库是本机私有的**（`~/.local/share/opencode/opencode.db`），不随本次迁移走：
  - 本机生成过当天日报 → `radar-chat` 续那个 session；
  - 否则走兜底：新会话 + 预制 prompt（带上日报路径）。

## 5) 跨机同步（已启用）
`data/` 是独立私有 git 仓，`bin/radar` 每次 `run` 会：
- 开头 `git pull --rebase --autostash`（并自动 abort 残留的 rebase 冲突）；
- 成功后 `git push`，**只提交白名单路径**（`digest/ review/ state/{seen,curriculum,linux,feedback,runs}.jsonl state/refresh.json state/sessions .gitignore`），
  不会把 `state/raw/`、PDF、临时文件等私人/大文件一股脑提交。

首次给 data 配 remote：
```bash
cd data
git remote add origin git@github.com:<你>/research-radar-data.git
git branch -M main && git push -u origin main
```
> 数据仓**务必私有**（含你的日报与画像队列）；PDF 与 `state/raw/` 已被 `.gitignore` 排除、不参与同步。
> 认证用 SSH（或 `gh auth login`），**不要在无人值守里用密码**，否则 systemd 跑时 `git pull/push` 会卡住。

## 6) 已验证的健壮性（新机同样适用）
- 漏几天没开机：只生成当天，不回溯（`--date` 回填会抓「当前」数据贴上旧日期，别用来补日）；
- `state/sessions/<日期>.id` 记了 `主机名`，别的主机不会去续不存在的 session；
- 跨机拿不到 session 时：本机固定兜底 session `ses-radar-local-<日期>` + 预制 prompt。
