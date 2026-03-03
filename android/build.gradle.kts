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

// AGP 8+ requires every Android module to declare namespace.
// Some older Flutter plugins (for example flutter_windowmanager 0.2.0) still
// only declare package in AndroidManifest.xml, so we provide a compatibility
// fallback from the root build script.
subprojects {
    plugins.withId("com.android.library") {
        val androidExtension = extensions.findByName("android") ?: return@withId
        val namespace = runCatching {
            androidExtension.javaClass.getMethod("getNamespace").invoke(androidExtension) as? String
        }.getOrNull()

        if (namespace.isNullOrBlank()) {
            val manifestFile = file("src/main/AndroidManifest.xml")
            val manifestPackage = if (manifestFile.exists()) {
                Regex("""package\s*=\s*"([^"]+)"""")
                    .find(manifestFile.readText())
                    ?.groupValues
                    ?.get(1)
            } else {
                null
            }

            if (!manifestPackage.isNullOrBlank()) {
                runCatching {
                    androidExtension.javaClass
                        .getMethod("setNamespace", String::class.java)
                        .invoke(androidExtension, manifestPackage)
                }
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
