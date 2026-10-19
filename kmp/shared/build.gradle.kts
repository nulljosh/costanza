plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.kotlinSerialization)
    alias(libs.plugins.androidLibrary)
}

kotlin {
    jvm()
    androidTarget()

    sourceSets {
        commonMain.dependencies {
            implementation(libs.ktor.core)
            implementation(libs.ktor.negotiation)
            implementation(libs.ktor.json)
            implementation(libs.kotlinx.serialization.json)
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
        jvmMain.dependencies { implementation(libs.ktor.cio) }
        androidMain.dependencies { implementation(libs.ktor.okhttp) }
    }
}

android {
    namespace = "com.nulljosh.stanza.shared"
    compileSdk = 36
    defaultConfig { minSdk = 26 }
}
