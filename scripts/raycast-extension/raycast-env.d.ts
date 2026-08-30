/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {
  /** Projet Hugo - Chemin absolu du dépôt Hugo */
  "projectRoot": string
}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `new-article` command */
  export type NewArticle = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `new-article` command */
  export type NewArticle = {}
}

