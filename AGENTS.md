# AGENTS.md — AI 协作守则

本文件面向所有在本仓库内工作的 AI 助手（Copilot CLI、Cursor、Claude、ChatGPT 等）。
**人类开发者优先级 > AI 自我判断。** 请在每一次涉及仓库状态变更的操作前，
明确征得开发者的同意。

---

## 1. Git 操作必须先获得明确授权

AI **禁止** 在未获明确授权的情况下执行任何会修改仓库状态或与远端交互的 git 命令。

### 受限命令（必须先经开发者同意）

- `git add`
- `git commit`、`git commit --amend`
- `git push`、`git push --force`
- `git pull`、`git fetch`（涉及远端交互）
- `git rebase`、`git merge`、`git cherry-pick`
- `git reset`（任何形式）、`git checkout` 跨分支
- `git stash pop` / `drop`
- `git tag`、`git branch -d/-D`
- `git clean`
- 任何对 `.git/` 目录的直接写入

### 允许的只读操作（无需授权）

- `git status`、`git diff`、`git log`、`git show`、`git blame`
- `git branch`（仅列出）、`git remote -v`
- 通过 `git ls-files`、`git cat-file` 等做查询

### 授权流程

1. AI **先汇报**：要做什么 git 操作、改了哪些文件、为什么
2. AI **询问**：通过 `ask_user` 或在回复中明确请求确认
3. 开发者**显式同意**（"提交"、"推送"、"go ahead" 等）
4. AI 才执行

仅当**开发者直接说"提交并推送"或同等明确指令时**，可以一次性完成对应操作。
**口头模糊（"收尾一下"、"整理下"）不构成授权。**

---

## 2. 提交信息规范

经授权提交时，遵循以下惯例：

- 标题前缀：`feat / fix / refactor / docs / chore / test`
- 标题简洁、祈使句、不超过 72 字符
- 必要时附正文说明动机与影响范围
- 末尾保留 Co-authored-by 标记 AI 参与：

```
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

（按所用工具替换为对应身份。）

---

## 3. 不要重写历史

未经开发者明确同意，**禁止**：

- `git push --force` / `--force-with-lease`
- `git rebase` 已推送的提交
- `git reset --hard` 已推送的提交
- `git commit --amend` 已推送的提交

---

## 4. 不要替开发者管理远端

- 不要 `git remote add/remove/set-url`
- 不要创建/删除远端分支
- 不要操作 PR、issue、release（除非开发者明确委托）

---

## 5. 文件层面的"等价 git 操作"也算 git 操作

以下行为等同于 git 操作，同样需授权：

- 直接编辑 `.git/` 内容
- 用 shell 删除 / 移动大量受版本控制的文件后立即 `git add -A`
- 生成 `.gitignore` / `.gitattributes` 全仓级规则
- 添加/移除 git submodule、symlink 跨边界引用

---

## 6. 例外

下列情况 AI **可以**直接动手，无需逐次询问：

- 在工作区内创建 / 编辑 / 删除文件以完成开发者交付的需求
- 运行构建、测试、lint、类型检查
- 安装本任务所需的依赖（npm / pip / cargo 等）
- 启动本地开发服务器（前提是开发者要求或与任务一致）

但**结果如果会进 git**，仍然要在提交前停下来询问。

---

## 7. 如何应对"看似已授权"的暧昧情境

不确定就停下来问。宁可多问一次，也不要替开发者按下提交/推送按钮。

> 若开发者说"我看下 diff"——只列 diff，不要顺手 commit。
> 若开发者说"准备好了"——确认是否包含提交/推送语义。
> 若开发者说"清理一下"——确认是 working tree 清理还是 git clean。

---

## 8. 违反守则的后果

任何违反本守则导致的提交/推送，AI 应当：

1. 立即停止后续 git 操作
2. 向开发者汇报已做的全部 git 动作（commit hash、推送目标、影响分支）
3. 等待开发者决定回滚/保留方案
4. 不要自行 `git revert` 或 `reset` 试图"修复"

---

_本守则适用于本仓库（skeleton2d）所有目录及子项目。_
