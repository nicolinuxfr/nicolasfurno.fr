import { availableParallelism } from "node:os";
import { readdir, rename, stat, unlink } from "node:fs/promises";
import { spawn } from "node:child_process";
import path from "node:path";

const outputDirectory = path.resolve(process.argv[2] ?? "public");
const jpegtran = process.env.JPEGTRAN_BIN ?? "jpegtran";
const concurrency = Math.min(availableParallelism(), 8);

async function findJpegs(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(entries.map(async (entry) => {
    const entryPath = path.join(directory, entry.name);

    if (entry.isDirectory()) {
      return findJpegs(entryPath);
    }

    return /\.jpe?g$/i.test(entry.name) ? [entryPath] : [];
  }));

  return files.flat();
}

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ["ignore", "ignore", "pipe"] });
    let stderr = "";

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve("");
      } else if (code === 2) {
        resolve(stderr.trim());
      } else {
        reject(new Error(`${command} exited with code ${code}: ${stderr.trim()}`));
      }
    });
  });
}

async function optimize(file, index) {
  const temporaryFile = `${file}.jpegtran-${process.pid}-${index}`;
  const before = await stat(file);

  try {
    const warning = await run(jpegtran, [
      "-copy", "all",
      "-optimize",
      "-progressive",
      "-outfile", temporaryFile,
      file,
    ]);

    if (warning) {
      await unlink(temporaryFile).catch(() => {});
      console.warn(`Skipped ${path.relative(outputDirectory, file)}: ${warning}`);
      return { savedBytes: 0, skippedFiles: 1 };
    }

    const after = await stat(temporaryFile);
    if (after.size >= before.size) {
      await unlink(temporaryFile);
      return { savedBytes: 0, skippedFiles: 0 };
    }

    await rename(temporaryFile, file);
    return { savedBytes: before.size - after.size, skippedFiles: 0 };
  } catch (error) {
    await unlink(temporaryFile).catch(() => {});
    throw error;
  }
}

const files = await findJpegs(outputDirectory);
let nextIndex = 0;
let savedBytes = 0;
let skippedFiles = 0;

async function worker() {
  while (nextIndex < files.length) {
    const index = nextIndex++;
    const result = await optimize(files[index], index);
    savedBytes += result.savedBytes;
    skippedFiles += result.skippedFiles;
  }
}

const workers = await Promise.allSettled(Array.from({ length: concurrency }, worker));
const failedWorker = workers.find((result) => result.status === "rejected");

if (failedWorker) {
  throw failedWorker.reason;
}

const savedKilobytes = new Intl.NumberFormat("en", {
  maximumFractionDigits: 1,
}).format(savedBytes / 1000);

const skippedSummary = skippedFiles === 0 ? "" : `; skipped ${skippedFiles} invalid JPEG file(s)`;
console.log(`Optimized ${files.length - skippedFiles} JPEG files without quality loss; saved ${savedKilobytes} kB${skippedSummary}.`);
