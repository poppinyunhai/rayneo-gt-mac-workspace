# v0.8 可回退基线

保存日期：2026-10-10。Git 标签：`v0.8`。

本基线保留原有实现与构建脚本，没有功能修改，也没有重新编译或签名。`Sources/` 和 `build.sh` 已与原发布目录中的源码副本逐项比较，一致。

## 已验证产物

以下三个文件有意纳入 Git；其他构建产物继续忽略。

- `releases/v0.8/RayNeoWorkspace-v0.8-app.zip`：用户实机验证成功的应用。
- `releases/v0.8/RayNeoWorkspace-v0.8-source.zip`：原始源码发布包。
- `releases/v0.8/manifest.json`：发布包大小和 SHA-256。

保存时两个 ZIP 的完整性与 SHA-256 均通过检查。实机验证范围及未验证事项见 `HANDOFF.md`。

## 回退与实验

查看基线：`git show v0.8`。

如需恢复原应用，从基线应用 ZIP 解压到单独目录后使用；源码重新构建会改变临时签名，可能需要重新授权。

如需在另一目录查看完整基线，可执行：

```sh
git worktree add --detach ../RayNeoWorkspace-v0.8-baseline v0.8
```

后续开发先创建新分支。保留原发布 ZIP，不覆盖正在使用的应用，实验构建使用独立路径。

此仓库为本地保存，尚未配置远程。Git 能保留版本历史，但同一磁盘上的仓库不能替代异地备份。
