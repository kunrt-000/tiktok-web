# =====================================================================
# 把 app/ 里的网页外壳工程编译成可安装的 APK
# 用法：在 PowerShell 里执行  .\build.ps1
# =====================================================================
# 用 Continue 而非 Stop：PowerShell 5.1 会把原生命令（keytool/apksigner）写到 stderr 的
# 进度信息当成致命错误而中断。这里改为逐条用 $LASTEXITCODE 判断，出错时再 throw。
$ErrorActionPreference = 'Continue'

# ---------- 可调整的路径 / 参数 ----------
$JAVA_HOME_   = 'C:\Users\wg\android-env\jdk'
$SDK          = 'C:\Users\wg\AppData\Local\Android\Sdk'
$BUILD_TOOLS  = Join-Path $SDK 'build-tools\34.0.0'
$ANDROID_JAR  = Join-Path $SDK 'platforms\android-34\android.jar'
$MIN_SDK      = 24          # Android 7.0 及以上
$TARGET_SDK   = 34

$PROJECT      = $PSScriptRoot
$APP_DIR      = Join-Path $PROJECT 'app'
$OUT_DIR      = Join-Path $PROJECT 'build'
$KEYSTORE     = Join-Path $PROJECT 'keystore\release.keystore'
$KS_ALIAS     = 'tiktokweb'
$KS_PASS      = 'tiktok123'
$APK_NAME     = 'TikTok-web.apk'
# ----------------------------------------

# 让子工具（d8 / apksigner / keytool）能找到 java
$env:JAVA_HOME = $JAVA_HOME_
$env:PATH = (Join-Path $JAVA_HOME_ 'bin') + ';' + $BUILD_TOOLS + ';' + $env:PATH
$env:ANDROID_HOME = $SDK

$AAPT2      = Join-Path $BUILD_TOOLS 'aapt2.exe'
$D8         = Join-Path $BUILD_TOOLS 'd8.bat'
$ZIPALIGN   = Join-Path $BUILD_TOOLS 'zipalign.exe'
$APKSIGNER  = Join-Path $BUILD_TOOLS 'apksigner.bat'
$KEYTOOL    = Join-Path $JAVA_HOME_ 'bin\keytool.exe'

function Step($text) { Write-Host "`n===== $text =====" -ForegroundColor Cyan }

# 每次全量重建，避免上一次的残留文件混进来
if (Test-Path $OUT_DIR) { Remove-Item $OUT_DIR -Recurse -Force }
$resZip    = Join-Path $OUT_DIR 'res.zip'
$genDir    = Join-Path $OUT_DIR 'gen'
$classDir  = Join-Path $OUT_DIR 'classes'
$dexDir    = Join-Path $OUT_DIR 'dex'
$baseApk   = Join-Path $OUT_DIR 'base.apk'
$unsigned  = Join-Path $OUT_DIR 'unsigned.apk'
$aligned   = Join-Path $OUT_DIR 'aligned.apk'
$finalApk  = Join-Path $OUT_DIR $APK_NAME
New-Item -ItemType Directory -Force -Path $genDir, $classDir, $dexDir | Out-Null

# 1) 编译资源（布局、字符串、图标）成中间产物
Step '1/7 编译资源 (aapt2 compile)'
& $AAPT2 compile --dir (Join-Path $APP_DIR 'res') -o $resZip
if ($LASTEXITCODE -ne 0) { throw 'aapt2 compile 失败' }

# 2) 链接资源 + 清单，生成只含资源的 APK 骨架，同时生成 R.java
Step '2/7 链接资源 (aapt2 link)'
& $AAPT2 link -o $baseApk `
    -I $ANDROID_JAR `
    --manifest (Join-Path $APP_DIR 'AndroidManifest.xml') `
    --java $genDir `
    --min-sdk-version $MIN_SDK `
    --target-sdk-version $TARGET_SDK `
    $resZip
if ($LASTEXITCODE -ne 0) { throw 'aapt2 link 失败' }

# 3) 编译 Java 源码（源码 + aapt2 生成的 R.java）
Step '3/7 编译 Java (javac)'
$javaFiles = @(Get-ChildItem -Path $APP_DIR, $genDir -Recurse -Filter *.java | ForEach-Object FullName)
& (Join-Path $JAVA_HOME_ 'bin\javac.exe') `
    -encoding UTF-8 -source 8 -target 8 -nowarn `
    -bootclasspath $ANDROID_JAR `
    -d $classDir @javaFiles
if ($LASTEXITCODE -ne 0) { throw 'javac 失败' }

# 4) 把 .class 转成安卓能执行的 dex 格式
Step '4/7 转换 dex (d8)'
$classFiles = @(Get-ChildItem -Path $classDir -Recurse -Filter *.class | ForEach-Object FullName)
& $D8 --release --min-api $MIN_SDK --lib $ANDROID_JAR --output $dexDir @classFiles
if ($LASTEXITCODE -ne 0) { throw 'd8 失败' }

# 5) 把 classes.dex 塞进 APK 骨架
Step '5/7 打包 dex 进 APK'
Copy-Item $baseApk $unsigned -Force
$dexFile = Join-Path $dexDir 'classes.dex'
$pyScript = @"
import zipfile
with zipfile.ZipFile(r'$unsigned', 'a', zipfile.ZIP_DEFLATED) as z:
    z.write(r'$dexFile', 'classes.dex')
print('classes.dex 已写入')
"@
$pyScript | python -
if ($LASTEXITCODE -ne 0) { throw '写入 classes.dex 失败' }

# 6) 对齐（安卓要求的字节对齐，否则安装可能失败或运行变慢）
Step '6/7 对齐 (zipalign)'
& $ZIPALIGN -f -p 4 $unsigned $aligned
if ($LASTEXITCODE -ne 0) { throw 'zipalign 失败' }

# 7) 签名（首次运行会自动生成签名证书，之后复用，保证能覆盖安装升级）
Step '7/7 签名 (apksigner)'
if (-not (Test-Path $KEYSTORE)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $KEYSTORE) | Out-Null
    Write-Host '未找到签名证书，正在生成 keystore\release.keystore'
    & $KEYTOOL -genkeypair -v -keystore $KEYSTORE -alias $KS_ALIAS `
        -keyalg RSA -keysize 2048 -validity 10950 `
        -storepass $KS_PASS -keypass $KS_PASS `
        -dname 'CN=TikTok Web, O=Dev, C=CN'
    if ($LASTEXITCODE -ne 0) { throw 'keytool 生成证书失败' }
}
& $APKSIGNER sign `
    --ks $KEYSTORE --ks-key-alias $KS_ALIAS `
    --ks-pass "pass:$KS_PASS" --key-pass "pass:$KS_PASS" `
    --out $finalApk $aligned
if ($LASTEXITCODE -ne 0) { throw 'apksigner 签名失败' }

Write-Host "`n编译完成：$finalApk" -ForegroundColor Green
Get-Item $finalApk | Select-Object FullName, Length
