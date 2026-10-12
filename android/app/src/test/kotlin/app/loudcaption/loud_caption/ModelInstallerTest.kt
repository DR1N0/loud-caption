package app.loudcaption.loud_caption

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelInstallerTest {
    @Test
    fun rejectsTraversalAndLeavesNoInstalledMarker() {
        val root = Files.createTempDirectory("vosk-test").toFile()
        val zip = ByteArrayOutputStream().also { bytes ->
            ZipOutputStream(bytes).use {
                it.putNextEntry(ZipEntry("../outside"))
                it.write(1)
                it.closeEntry()
            }
        }.toByteArray()

        assertThrows(IllegalArgumentException::class.java) {
            ModelInstaller(root).ensureInstalled("en") { zip.inputStream() }
        }
        assertNotInstalled(root, "vosk-model-small-en-us-0.15")
    }

    @Test
    fun installsAndReusesEnglishModel() = installsAndReuses(
        language = "en",
        id = "vosk-model-small-en-us-0.15",
    )

    @Test
    fun installsAndReusesChineseModel() = installsAndReuses(
        language = "zh",
        id = "vosk-model-small-cn-0.22",
    )

    @Test
    fun truncatedZipLeavesNoInstalledMarker() {
        val root = Files.createTempDirectory("vosk-test").toFile()
        val id = "vosk-model-small-en-us-0.15"
        val bytes = validZip(id).copyOf(10)

        assertThrows(Exception::class.java) {
            ModelInstaller(root).ensureInstalled("en") { bytes.inputStream() }
        }
        assertNotInstalled(root, id)
    }

    @Test
    fun throwingArchiveLeavesNoInstalledMarker() {
        val root = Files.createTempDirectory("vosk-test").toFile()
        val id = "vosk-model-small-cn-0.22"

        assertThrows(Exception::class.java) {
            ModelInstaller(root).ensureInstalled("zh") {
                object : InputStream() {
                    override fun read(): Int = throw IllegalStateException("stream failed")
                }
            }
        }
        assertNotInstalled(root, id)
    }

    @Test
    fun rejectsArchivesOverTheExtractionLimitBeforeInstallation() {
        val root = Files.createTempDirectory("vosk-test").toFile()
        val id = "vosk-model-small-en-us-0.15"
        val bytes = validZip(
            id = id,
            finalModel = byteArrayOf(1, 2),
            config = byteArrayOf(3),
        )

        assertThrows(IllegalArgumentException::class.java) {
            ModelInstaller(root, maxExtractedBytes = 2).ensureInstalled("en") { bytes.inputStream() }
        }
        assertNotInstalled(root, id)
    }

    @Test
    fun rejectsArchivesWithMoreThanFourThousandEntries() {
        val root = Files.createTempDirectory("vosk-test").toFile()
        val id = "vosk-model-small-en-us-0.15"
        val bytes = zipWithEntries(id, 4_001)

        assertThrows(IllegalArgumentException::class.java) {
            ModelInstaller(root).ensureInstalled("en") { bytes.inputStream() }
        }
        assertNotInstalled(root, id)
    }

    @Test
    fun serializesTwoInstallerInstancesForTheSameRoot() {
        val root = Files.createTempDirectory("vosk-test").toFile()
        val id = "vosk-model-small-en-us-0.15"
        val bytes = validZip(id)
        val firstArchiveOpened = CountDownLatch(1)
        val releaseFirstArchive = CountDownLatch(1)
        val secondInstallAttempted = CountDownLatch(1)
        val secondArchiveUsed = AtomicBoolean(false)
        val firstInstallerThread = AtomicReference<Thread>()
        val secondInstallerThread = AtomicReference<Thread>()
        val executor = Executors.newFixedThreadPool(2)

        try {
            val first = executor.submit<File> {
                firstInstallerThread.set(Thread.currentThread())
                ModelInstaller(root).ensureInstalled("en") {
                    firstArchiveOpened.countDown()
                    check(releaseFirstArchive.await(5, TimeUnit.SECONDS)) {
                        "Timed out waiting to release first archive"
                    }
                    bytes.inputStream()
                }
            }
            assertTrue(firstArchiveOpened.await(5, TimeUnit.SECONDS))

            val second = executor.submit<File> {
                secondInstallerThread.set(Thread.currentThread())
                secondInstallAttempted.countDown()
                ModelInstaller(root).ensureInstalled("en") {
                    secondArchiveUsed.set(true)
                    error("second installer must reuse the completed model")
                }
            }
            assertTrue(secondInstallAttempted.await(5, TimeUnit.SECONDS))
            assertSecondInstallerBlocksOnFirst(
                firstInstallerThread.get(),
                secondInstallerThread.get(),
            )
            assertFalse(secondArchiveUsed.get())
            releaseFirstArchive.countDown()

            val firstInstalled = first.get(5, TimeUnit.SECONDS)
            val secondInstalled = second.get(5, TimeUnit.SECONDS)
            assertEquals(firstInstalled, secondInstalled)
            assertTrue(File(firstInstalled, ".ready").isFile)
            assertFalse(secondArchiveUsed.get())
            assertFalse(File(root, "$id.installing").exists())
        } finally {
            releaseFirstArchive.countDown()
            executor.shutdownNow()
        }
    }

    private fun assertSecondInstallerBlocksOnFirst(
        firstInstallerThread: Thread?,
        secondInstallerThread: Thread?,
    ) {
        checkNotNull(firstInstallerThread) { "First installer thread was not recorded" }
        checkNotNull(secondInstallerThread) { "Second installer thread was not recorded" }
        val deadlineNanos = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (System.nanoTime() < deadlineNanos) {
            // These are distinct ModelInstaller instances; while the first is
            // held in its archive supplier, BLOCKED proves the second is waiting
            // on the process-wide installation lock rather than merely queued.
            if (
                firstInstallerThread.isAlive &&
                    secondInstallerThread.state == Thread.State.BLOCKED
            ) {
                return
            }
            Thread.yield()
        }
        throw AssertionError("Second installer did not block on the first installer lock")
    }

    private fun installsAndReuses(language: String, id: String) {
        val root = Files.createTempDirectory("vosk-test").toFile()
        val bytes = validZip(id)

        val installed = ModelInstaller(root).ensureInstalled(language) { bytes.inputStream() }
        assertTrue(File(installed, ".ready").isFile)
        assertEquals(
            installed,
            ModelInstaller(root).ensureInstalled(language) { error("must use cache") },
        )
    }

    private fun assertNotInstalled(root: File, id: String) {
        assertFalse(File(root, "$id/.ready").exists())
        assertFalse(File(root, "$id.installing").exists())
    }

    private fun validZip(
        id: String,
        finalModel: ByteArray = byteArrayOf(1),
        config: ByteArray = byteArrayOf(1),
    ): ByteArray = ByteArrayOutputStream().also { output ->
        ZipOutputStream(output).use { zip ->
            for ((entry, contents) in listOf(
                "$id/am/final.mdl" to finalModel,
                "$id/conf/model.conf" to config,
            )) {
                zip.putNextEntry(ZipEntry(entry))
                zip.write(contents)
                zip.closeEntry()
            }
        }
    }.toByteArray()

    private fun zipWithEntries(id: String, count: Int): ByteArray = ByteArrayOutputStream().also { output ->
        ZipOutputStream(output).use { zip ->
            repeat(count) { index ->
                zip.putNextEntry(ZipEntry("$id/entries/$index/"))
                zip.closeEntry()
            }
        }
    }.toByteArray()
}
