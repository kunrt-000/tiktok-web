# iOS 版打包说明（未签名 IPA）

这是 TikTok 网页壳的 iOS 版源码，功能和安卓版一致：

- 打开加载主页 `tiktok.com`
- 个人主页（Profile）右上角显示 **Shop / Merchant** 两个入口
- Shop → `https://a2.dsfer168.cc`，Merchant → `https://a3.dsfer168.cc`
- 进入商城/商家页后，左上角显示返回键
- 网址加密存放，运行时还原

## 目录结构

```
ios/
├── project.yml                  # XcodeGen 工程配置
├── TikTokWeb/
│   ├── AppDelegate.swift        # 入口
│   ├── ViewController.swift     # WebView + 入口按钮 + 返回键 + 加密还原
│   └── Info.plist               # 权限、ATS 等配置
└── README.md
```

仓库根目录还有 `.github/workflows/build-ios.yml`，用于云端打包。

## 云端打包（GitHub Actions）

1. 把整个项目推送到 GitHub 仓库（包含 `ios/` 和 `.github/workflows/`）。
2. 在 GitHub 仓库页面点 **Actions** → 左侧 **Build iOS IPA** → **Run workflow**。
3. 等构建跑完，进入这次运行，在 **Artifacts** 里下载 `TikTokWeb-unsigned-ipa`。

> 也可直接推送代码到 `main`/`master` 分支，会自动触发构建。

## 重要限制（务必看）

- 你现在**没有 Apple 开发者账号**，所以这个 IPA 是**未签名**的。
- 未签名 IPA **无法安装到普通 iPhone**（只能用于越狱设备或后续签名）。
- 要让 IPA 能装到正常 iPhone，需要：
  1. 注册 Apple 开发者账号（付费，约 99 美元/年）；
  2. 在苹果后台创建 App ID 和证书（p12 + mobileprovision）；
  3. 把证书配置到 GitHub Actions 的 Secrets 里，并把 `build-ios.yml` 里的签名参数改为真实证书。

## 本地打包（有 Mac 时）

在 Mac 上执行：

```bash
brew install xcodegen
cd ios
xcodegen generate
open TikTokWeb.xcodeproj   # 用 Xcode 打开，选真机，直接 Run 即可
```

## 修改入口地址

入口地址在 `TikTokWeb/ViewController.swift` 顶部以加密数组形式存放。
如需更换地址，用与安卓一致的加密算法重新生成 `*_ENC` / `*_SEED` 后替换即可。
