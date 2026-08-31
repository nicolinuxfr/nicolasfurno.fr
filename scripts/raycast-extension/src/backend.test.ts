import { describe, expect, it } from "vitest";
import { homedir } from "node:os";
import path from "node:path";
import { BackendError, normalizeProjectRoot, parseEnvelope } from "./backend";

describe("parseEnvelope", () => {
  it("retourne les données d'un succès", () => {
    expect(
      parseEnvelope<{ value: number }>('{"ok":true,"data":{"value":42}}'),
    ).toEqual({ value: 42 });
  });

  it("propage une erreur structurée", () => {
    expect(() =>
      parseEnvelope(
        '{"ok":false,"error":{"code":"invalid","message":"Erreur"}}',
      ),
    ).toThrowError(BackendError);
  });

  it("refuse une réponse invalide", () => {
    expect(() => parseEnvelope("bruit")).toThrow("réponse illisible");
  });

  it("permet d’identifier une annulation attendue", () => {
    const error = new BackendError("Recherche annulée.", "cancelled");
    expect(error.code).toBe("cancelled");
  });
});

describe("normalizeProjectRoot", () => {
  it("conserve un chemin absolu", () => {
    expect(normalizeProjectRoot(" /tmp/site ")).toBe("/tmp/site");
  });

  it("développe un chemin commençant par un tilde", () => {
    expect(normalizeProjectRoot("~/Developer/site")).toBe(
      path.join(homedir(), "Developer/site"),
    );
  });

  it("résout une valeur relative depuis le dossier utilisateur", () => {
    expect(normalizeProjectRoot("Developer/perso/nicolasfurno.fr")).toBe(
      path.join(homedir(), "Developer/perso/nicolasfurno.fr"),
    );
  });
});
