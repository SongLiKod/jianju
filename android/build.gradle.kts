allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// 统一固定 NDK 版本为本机已安装版本，避免 Gradle 触发在线下载 NDK 28.2
// （必须在 evaluationDependsOn 之前注册，否则 :app 已求值导致 afterEvaluate 报错）
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            try {
                val method = ext.javaClass.methods.firstOrNull { it.name == "setNdkVersion" }
                method?.invoke(ext, "26.3.11579264")
            } catch (_: Exception) {
                // 忽略不支持设置的子项目
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
