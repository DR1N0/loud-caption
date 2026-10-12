package app.loudcaption.loud_caption

import java.io.BufferedInputStream
import java.io.File
import java.io.InputStream
import java.util.zip.ZipInputStream

/** Installs a bundled Vosk archive into app-private storage atomically. */
class ModelInstaller(
    private val modelRoot: File,
    private val maxExtractedBytes: Long = MAX_EXTRACTED_BYTES,
) {
    init {
        require(maxExtractedBytes > 0L) { "Extraction limit must be positive" }
    }

    /**
     * Returns a complete local model directory for [language].
     *
     * The archive supplier is deliberately evaluated only if a valid installed
     * model is not already available.
     */
    @Synchronized
    fun ensureInstalled(language: String, archive: () -> InputStream): File {
        val id = modelId(language)
        synchronized(INSTALLATION_LOCK) {
            return ensureInstalledLocked(id, archive)
        }
    }

    private fun ensureInstalledLocked(id: String, archive: () -> InputStream): File {
        val destination = File(modelRoot, id)
        if (isComplete(destination)) {
            return destination
        }

        check(modelRoot.mkdirs() || modelRoot.isDirectory) {
            "Cannot create model directory: $modelRoot"
        }
        val staging = File(modelRoot, "$id.installing")
        if (staging.exists()) {
            check(staging.deleteRecursively()) { "Cannot clear interrupted install: $staging" }
        }
        check(staging.mkdirs()) { "Cannot create staging directory: $staging" }

        try {
            extractArchive(id, staging, archive)
            check(File(staging, "am/final.mdl").isFile) { "Model archive lacks am/final.mdl" }
            check(File(staging, "conf/model.conf").isFile) { "Model archive lacks conf/model.conf" }
            check(File(staging, READY_MARKER).createNewFile()) { "Cannot mark model ready" }

            if (destination.exists()) {
                check(destination.deleteRecursively()) {
                    "Cannot replace incomplete model: $destination"
                }
            }
            check(staging.renameTo(destination)) { "Cannot finish model installation" }
            return destination
        } finally {
            // This directory is app-owned and must never survive a failed install.
            staging.deleteRecursively()
        }
    }

    private fun extractArchive(id: String, staging: File, archive: () -> InputStream) {
        var entryCount = 0
        var extractedBytes = 0L
        val stagingPath = staging.canonicalPath + File.separator

        ZipInputStream(BufferedInputStream(archive())).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                entryCount += 1
                require(entryCount <= MAX_ENTRIES) { "Archive contains too many entries" }
                require(entry.name.startsWith("$id/") && !entry.name.contains('\\')) {
                    "Unexpected archive entry: ${entry.name}"
                }

                val relativePath = entry.name.removePrefix("$id/")
                if (relativePath.isNotEmpty()) {
                    val target = File(staging, relativePath)
                    require(target.canonicalPath.startsWith(stagingPath)) {
                        "Archive entry escapes staging directory: ${entry.name}"
                    }
                    if (entry.isDirectory) {
                        check(target.mkdirs() || target.isDirectory) {
                            "Cannot create archive directory: $relativePath"
                        }
                    } else {
                        val parent = target.parentFile!!
                        check(parent.mkdirs() || parent.isDirectory) {
                            "Cannot create archive directory: ${parent.path}"
                        }
                        target.outputStream().use { output ->
                            val buffer = ByteArray(BUFFER_SIZE)
                            while (true) {
                                val read = zip.read(buffer)
                                if (read < 0) break
                                require(read.toLong() <= maxExtractedBytes - extractedBytes) {
                                    "Archive exceeds extraction limit"
                                }
                                output.write(buffer, 0, read)
                                extractedBytes += read
                            }
                        }
                    }
                }
                zip.closeEntry()
            }
        }
    }

    private fun isComplete(directory: File): Boolean =
        File(directory, READY_MARKER).isFile &&
            File(directory, "am/final.mdl").isFile &&
            File(directory, "conf/model.conf").isFile

    private fun modelId(language: String): String = when (language) {
        "en" -> "vosk-model-small-en-us-0.15"
        "zh" -> "vosk-model-small-cn-0.22"
        else -> throw IllegalArgumentException("Unsupported language: $language")
    }

    private companion object {
        const val READY_MARKER = ".ready"
        const val MAX_ENTRIES = 4_000
        const val MAX_EXTRACTED_BYTES = 512L * 1024 * 1024
        const val BUFFER_SIZE = 8_192
        val INSTALLATION_LOCK = Any()
    }
}
