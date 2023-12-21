package com.eso_encore.releaser

import com.twmacinta.util.MD5
import java.nio.charset.Charset
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.util.ArrayList
import java.util.Arrays
import org.apache.commons.io.FileUtils
import org.apache.commons.io.IOUtils
import java.util.List

class Releaser {

	def static void main(String[] args) {
		val original = Paths.get("C:/Users/Admin/eclipse-workspace/launcher/package/installationDirectory")
		val modified = Paths.get("E:/ESO Alpha/installationDirectory")
		val patches = Paths.get("patches")
		val patchIgnore = Files.readAllLines(Paths.get("patchIgnore"))

		ensurePatchesDirectoryEmpty(patches)
		ensureVersionChanged(original, modified)

		generatePatches(
			original,
			modified,
			patches,
			patchIgnore
		)
		compressPatches(
			patches,
			original
		)
	}

	def static ensurePatchesDirectoryEmpty(Path patches) {
		if (!Files.exists(patches) || Files.list(patches).count() == 0) {
			patches.toFile.mkdirs
		} else {
			throw new RuntimeException('''Patches folder not empty: «patches»''')
		}
	}

	def static ensureVersionChanged(Path original, Path modified) {
		val versionOriginal = Files.readAllLines(original.resolve("version")).join()
		val versionModified = Files.readAllLines(modified.resolve("version")).join()
		if (versionOriginal == versionModified) {
			throw new RuntimeException("Version was not changed: " + versionOriginal)
		} else {
			println('''Generating patches for «versionOriginal»->«versionModified»''')
		}
	}

	def static generatePatches(Path original, Path modified, Path patchDirectory, List<String> patchIgnore) {
		Files.walk(original).skip(1).filter[Files.isRegularFile(it)].forEach [ originalFile |
			val relativePath = original.relativize(originalFile)
			if (shouldIgnore(relativePath, patchIgnore)) {
				println("ignoring " + relativePath)
			} else {
				val modifiedFile = modified.resolve(relativePath)
				if (!Files.exists(modifiedFile)) { // deleted file
					println("Deleted " + relativePath)
					val patchFile = patchDirectory.resolve(relativePath + ".deleted")
					patchFile.toFile => [
						parentFile.mkdirs()
						createNewFile()
					]
				} else {
					val originalHash = MD5.getHash(originalFile.toFile)
					val modifiedHash = MD5.getHash(modifiedFile.toFile)
					if (!Arrays.equals(originalHash, modifiedHash)) { // changed file
						println("Changed " + relativePath)
						generatePatch(originalFile, modifiedFile, patchDirectory.resolve(relativePath + ".patch"))
					}
				}
			}
		]
		println("Looking for new files")
		Files.walk(modified).skip(1).filter[Files.isRegularFile(it)].forEach [ modifiedFile |
			val relativePath = modified.relativize(modifiedFile)
			if (shouldIgnore(relativePath, patchIgnore)) {
				println("ignoring " + relativePath)
			} else {
				val originalFile = original.resolve(relativePath)
				if (!Files.exists(originalFile)) { // new file
					println("new file " + modifiedFile)
					val patchFile = patchDirectory.resolve(relativePath)
					patchFile.parent.toFile.mkdirs()
					FileUtils.copyFile(modifiedFile.toFile, patchFile.toFile)
				}
			}
		]
		println()
		println("Compressing")
		val commandList = new ArrayList(Arrays.asList(
			"C:/Program Files/7-Zip/7z.exe",
			"a",
			"-t7z",
			"archive.7z"
		))
		Files.list(patchDirectory).forEach[commandList.add(it.toAbsolutePath.toString)]
		val builder = new ProcessBuilder(commandList)
		builder.redirectErrorStream(true)
		println(builder.command.join(" "))
		val process = builder.start()
		println(IOUtils.readLines(process.inputStream, Charset.defaultCharset()).join("\n"))
	}
	
	def static compressPatches(Path patchDirectory, Path original) {
		println("Compressing")
		val versionOriginal = Files.readAllLines(original.resolve("version")).join()
		val commandList = new ArrayList(Arrays.asList(
			"C:/Program Files/7-Zip/7z.exe",
			"a",
			"-t7z",
			versionOriginal+".7z"
		))
		Files.list(patchDirectory).forEach[commandList.add(it.toAbsolutePath.toString)]
		val builder = new ProcessBuilder(commandList)
		builder.redirectErrorStream(true)
		println(builder.command.join(" "))
		val process = builder.start()
		println(IOUtils.readLines(process.inputStream, Charset.defaultCharset()).join("\n"))
	}

	def static generatePatch(Path original, Path modified, Path patchFile) {
		patchFile.parent.toFile.mkdirs
		val builder = new ProcessBuilder(
			"lib\\hdiffz.exe",
			"-m-6",
			"-SD",
			"-c-zstd-21-24",
			"-d",
			original.toAbsolutePath.toString(),
			modified.toAbsolutePath.toString(),
			patchFile.toAbsolutePath.toString()
		)
		builder.redirectErrorStream(true)
		val process = builder.start()
		val output = IOUtils.readLines(process.inputStream, Charset.defaultCharset()).join("\n")
		if (process.exitValue != 0) {
			println(output)
			throw new RuntimeException("exit value " + process.exitValue)
		}
	}

	def static shouldIgnore(Path path, List<String> patchIgnore) {
		val pathAsString = path.toString()
		return patchIgnore.filter [
			pathAsString.startsWith(it)
		].size > 0
	}

}
