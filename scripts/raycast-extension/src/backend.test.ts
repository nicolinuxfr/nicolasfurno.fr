import { describe, expect, it } from "vitest";
import { BackendError, parseEnvelope } from "./backend";

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
