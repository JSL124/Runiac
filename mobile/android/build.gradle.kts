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
subprojects {
    project.evaluationDependsOn(":app")
}
subprojects {
    val mapboxCompileSdkBridgeProjects =
        setOf("mapbox_maps_flutter", "flutter_plugin_android_lifecycle")

    plugins.withId("com.android.library") {
        if (project.name in mapboxCompileSdkBridgeProjects) {
            extensions.configure<com.android.build.api.variant.LibraryAndroidComponentsExtension>(
                "androidComponents",
            ) {
                finalizeDsl { extension ->
                    // M4-C2 bridge: Mapbox 2.25.0 resolves alongside an Android
                    // lifecycle plugin that requires API 36, while the Mapbox
                    // plugin project currently declares a lower compile SDK.
                    extension.compileSdk = 36
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
