# 本地稳定签名

本机原有代码签名证书已过期。本轮创建了 **RayNeo Workspace Local Development** 专用自签名证书，固定开发版身份 `local.rayneo.workspace.dev`。

该证书仅用于本地开发，不能替代 Developer ID 或公证。没有安装付费账号、申请公开发布或修改原 v0.8 的签名。

## 已完成配置

- 专用钥匙串：项目 `.signing-config/signing.keychain-db`。
- `.signing-identity` 固定叶证书 SHA-1。
- 用户钥匙串搜索列表新增专用钥匙串，保留原有条目，默认钥匙串未改变。
- 自签证书的用户信任限制为 codeSign，不授予 SSL 信任。
- 指定签名要求：固定 bundle identifier 与叶证书指纹，不使用随编译变化的 cdhash 作为身份要求。
- 私有钥匙串、密码及本地配置均在 `.gitignore` 中，未纳入 Git；目录权限 0700，口令/钥匙串权限 0600。
- 临时 PEM 私钥和 PKCS12 在导入后删除，私钥留在专用钥匙串。

在同一证书下两次构建的 designated requirement 已比较一致；签名严格验证通过，临时副本的 Info.plist 篡改被检测。真实 TCC 更新后是否仍保留授权，需在实机验收中确认，不能仅凭签名测试保证。

## 其他机器或迁移目录

创建新的本地身份：

```sh
python3 scripts/setup-local-signing.py
bash build.sh
```

这会建立专用钥匙串并配置用户 codeSign 信任，可能触发 macOS 的确认界面。已有本地配置时复用证书，不主动轮换。移动项目后运行此脚本更新钥匙串搜索路径。

若使用已有有效证书：

```sh
security find-identity -v -p codesigning
bash scripts/configure-signing.sh CERTIFICATE_SHA1
bash build.sh
```

脚本只接受 40 位证书指纹，不按可能重复的显示名称选择。外部签名身份可通过 SIGNING_IDENTITY 指纹覆盖；项目专用钥匙串只在使用它自己的身份时参与构建。

没有配置稳定身份时构建会停止，不默默使用 ad hoc。明确做临时 QA 构建：

```sh
SIGNING_IDENTITY=- BUILD_DIR=build/qa bash build.sh
```

## 使用注意

从前一轮 ad hoc 开发版改为新证书属于一次身份变化，可能需要重新授权开发版的屏幕录制/辅助功能。之后坚持使用同一证书。原 v0.8 身份不受本轮变更影响。

保留专用钥匙串及其口令的安全备份；只克隆 Git 不能恢复被忽略的签名私钥。不要把私钥/密码加入仓库或上传到交接文档。换证书或丢失私钥会改变身份，需要重新验收授权行为。
