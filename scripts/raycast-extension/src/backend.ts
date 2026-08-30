import { execFile } from "node:child_process";
import { access } from "node:fs/promises";
import { constants } from "node:fs";
import path from "node:path";

export type Envelope<T> =
  | { ok: true; data: T }
  | { ok: false; error: { code: string; message: string } };

export class BackendError extends Error {
  constructor(
    message: string,
    public readonly code = "backend_error",
  ) {
    super(message);
  }
}

export function parseEnvelope<T>(stdout: string): T {
  let envelope: Envelope<T>;
  try {
    envelope = JSON.parse(stdout) as Envelope<T>;
  } catch {
    throw new BackendError(
      "Le backend a retourné une réponse illisible.",
      "invalid_response",
    );
  }
  if (!envelope.ok)
    throw new BackendError(envelope.error.message, envelope.error.code);
  return envelope.data;
}

export async function validateRoot(root: string): Promise<void> {
  if (!path.isAbsolute(root))
    throw new BackendError(
      "Le chemin du projet doit être absolu.",
      "invalid_root",
    );
  await access(path.join(root, "hugo.toml"), constants.R_OK).catch(() => {
    throw new BackendError(
      "Le dossier choisi ne contient pas hugo.toml.",
      "invalid_root",
    );
  });
  await access(
    path.join(root, "scripts", "article-cli.sh"),
    constants.X_OK,
  ).catch(() => {
    throw new BackendError(
      "Le backend scripts/article-cli.sh est absent ou non exécutable.",
      "invalid_root",
    );
  });
}

export async function runBackend<T>(
  root: string,
  operation: string,
  request: object = {},
  signal?: AbortSignal,
): Promise<T> {
  await validateRoot(root);
  const executable = path.join(root, "scripts", "article-cli.sh");
  const executablePath = [
    "/opt/homebrew/bin",
    "/usr/local/bin",
    process.env.PATH,
  ]
    .filter(Boolean)
    .join(":");
  return new Promise<T>((resolve, reject) => {
    const child = execFile(
      "/bin/zsh",
      [executable, operation],
      {
        cwd: root,
        env: { ...process.env, ARTICLE_ROOT: root, PATH: executablePath },
        maxBuffer: 10 * 1024 * 1024,
      },
      (error, stdout) => {
        if (signal?.aborted)
          return reject(new BackendError("Recherche annulée.", "cancelled"));
        try {
          resolve(parseEnvelope<T>(stdout));
        } catch (parseError) {
          reject(parseError instanceof Error ? parseError : error);
        }
      },
    );
    child.stdin?.end(JSON.stringify(request));
    const abort = () => child.kill("SIGTERM");
    signal?.addEventListener("abort", abort, { once: true });
    child.once("close", () => signal?.removeEventListener("abort", abort));
  });
}
