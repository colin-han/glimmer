plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 从 .env.local 读取 WORKTREE 变量
val worktreeRaw: String = {
    val envFile = file("${project.projectDir}/../../.env.local")
    if (envFile.exists()) {
        val lines = envFile.readLines()
        val line = lines.find { it.startsWith("WORKTREE=") }
        line?.substringAfter("WORKTREE=")?.trim()?.removeSurrounding("\"") ?: ""
    } else ""
}()

// 规范化为合法 Android 包名段：非字母开头加 "w" 前缀，非字母数字替换为 "x"
val worktreeSafe: String = if (worktreeRaw.isEmpty()) ""
    else {
        val safe = worktreeRaw.map { if (it.isLetterOrDigit()) it else 'x' }.joinToString("")
        if (safe.first().isLetter()) safe else "w$safe"
    }

android {
    namespace = "info.colinhan.glimmer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "env"

    productFlavors {
        create("prod") {
            dimension = "env"
            applicationId = "info.colinhan.glimmer"
            manifestPlaceholders["appName"] = "Glimmer"
        }
        create("dev") {
            dimension = "env"
            applicationId = if (worktreeSafe.isNotEmpty())
                "info.colinhan.glimmer.dev.$worktreeSafe"
            else
                "info.colinhan.glimmer.dev"
            manifestPlaceholders["appName"] = if (worktreeRaw.isNotEmpty())
                "Glimmer Dev$worktreeRaw"
            else
                "Glimmer Dev"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // ⚠️ 切勿设 isDebuggable = true！
            // Flutter gradle plugin 用 isDebuggable（而非 buildType 名字）判定编译模式：
            // release 一旦 debuggable，会被当 debug 编译——产出 kernel_blob（JIT）而非
            // libapp.so（AOT），与 release 的预编译运行时不匹配，启动必崩：
            // "Precompiled runtime requires a precompiled snapshot"（flutter #54126）。
            // prod 数据备份改用 adb backup（manifest allowBackup=true），不靠 run-as。
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
