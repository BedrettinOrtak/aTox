// SPDX-FileCopyrightText: 2019-2025 Robin Lindén <dev@robinlinden.eu>
// SPDX-FileCopyrightText: 2019 aTox contributors
//
// SPDX-License-Identifier: GPL-3.0-only

package ltd.evilcorp.atox

import android.app.Application
import android.util.Log
import androidx.annotation.VisibleForTesting
import java.io.File
import java.io.PrintWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import ltd.evilcorp.atox.di.AppComponent
import ltd.evilcorp.atox.di.DaggerAppComponent

class App : Application() {
    val component: AppComponent by lazy {
        componentOverride ?: DaggerAppComponent.factory().create(applicationContext)
    }

    @VisibleForTesting
    var componentOverride: AppComponent? = null

    override fun onCreate() {
        super.onCreate()
        installCrashLogger()
    }

    /** Persist any uncaught exceptions to <cacheDir>/crash/<timestamp>.txt for easy inspection. */
    private fun installCrashLogger() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val dir = File(cacheDir, "crash").apply { mkdirs() }
                val ts = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
                val file = File(dir, "crash_$ts.txt")
                PrintWriter(file).use { pw ->
                    pw.println("Time: $ts")
                    pw.println("Thread: ${thread.name}")
                    pw.println("Exception: $throwable")
                    pw.println()
                    throwable.printStackTrace(pw)
                }
                Log.e("aTox-crash", "Wrote crash log to ${file.absolutePath}")
            } catch (_: Throwable) {
                // Last-ditch: don't break the default handler chain.
            }
            previous?.uncaughtException(thread, throwable)
        }
    }
}

