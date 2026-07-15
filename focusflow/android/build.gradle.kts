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
    // ─── AGP 8.x namespace compatibility shim ──────────────────────────
    // Older Flutter plugins published before AGP 8.0 (e.g.
    // `sqlite3_flutter_libs` 0.5.5) lack a `namespace` declaration in
    // their module-level `build.gradle`. AGP 8.x requires every
    // android-library subproject to declare a namespace, otherwise Gradle
    // configuration fails with:
    //   "Namespace not specified. Specify a namespace in the module's
    //   build file: .../build.gradle."
    //
    // Inject a synthetic namespace (`flutter.plugins.<plugin-slug>` —
    // reverse-DNS style, no clash with actual package declarations)
    // ONLY for android-library plugins that lack one. Production
    // plugins with explicit namespaces are not touched.
    //
    // Defensive note: the `if (namespace == null)` check uses Kotlin
    // structural equality against the AGP 8.x nullable `String?` property.
    // A plugin that sets `namespace = ""` (empty string, theoretical
    // edge case) would be treated as "already set" and skipped — but
    // AGP 8.x rejects empty namespaces earlier in configuration, so
    // this path is unreachable in practice.
    //
    // R8 INTERACTION: the synthetic namespace classes (e.g.
    // `flutter.plugins.sqlite3_flutter_libs.R`) are NOT referenced by
    // any cross-class code in the current plugin set, so the
    // real-package keep rules in `app/proguard-rules.pro`
    // (e.g. `-keep class com.simolus3.sqlite3_flutter_libs.** { *; }`)
    // are what actually preserve the runtime classes. If a future
    // plugin falls through the shim and R8 strips its classes, add a
    // `-keep class flutter.plugins.<slug>.** { *; }` rule to
    // `app/proguard-rules.pro`.
    afterEvaluate {
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                if (namespace == null) {
                    namespace = "flutter.plugins.${project.name.replace("-", ".")}"
                }
            }
        }
    }
}

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
