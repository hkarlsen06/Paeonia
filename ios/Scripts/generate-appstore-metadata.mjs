#!/usr/bin/env bun

import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const OPENAI_RESPONSES_API_URL = "https://api.openai.com/v1/responses";
const OPENAI_MODEL = process.env.OPENAI_MODEL?.trim() || "gpt-5.4";
const OPENAI_REASONING_EFFORT = "low";

const XCODE_PROJECT_PATH = path.join(__dirname, "../Paeonia.xcodeproj/project.pbxproj");
const METADATA_SOURCE_PATH = path.join(__dirname, "appstore-metadata-source.json");
const METADATA_OUTPUT_PATH = path.join(__dirname, "../fastlane/metadata");

const args = process.argv.slice(2);
const validateOnly = args.includes("--validate-only");
const sourceOnly = args.includes("--source-only");
const forceRegenerate = args.includes("--force");

const SOURCE_LOCALES = ["en", "nb"];
const PRIMARY_LOCALE = "en";

const ASC_FOLDER_MAP = {
  en: "en-US",
  "en-GB": "en-GB",
  nb: "no",
  nn: "no",
  de: "de-DE",
  fr: "fr-FR",
  es: "es-ES",
  "es-MX": "es-MX",
  it: "it",
  nl: "nl-NL",
  "pt-BR": "pt-BR",
  sv: "sv",
  da: "da",
  fi: "fi",
  pl: "pl",
  ru: "ru",
  uk: "uk",
  tr: "tr",
  el: "el",
  ro: "ro",
  ja: "ja",
  ko: "ko",
  "zh-Hans": "zh-Hans",
  "zh-Hant": "zh-Hant",
  th: "th",
  vi: "vi",
  ca: "ca",
  cs: "cs",
  hr: "hr",
  hu: "hu",
  id: "id",
  he: "he",
  hi: "hi",
  sk: "sk",
  ar: "ar-SA",
  Base: null
};

const LANGUAGE_NAMES = {
  de: "German",
  fr: "French",
  es: "Spanish (Spain)",
  "es-MX": "Spanish (Mexico)",
  "en-GB": "British English",
  it: "Italian",
  nl: "Dutch",
  "pt-BR": "Brazilian Portuguese",
  nn: "Norwegian Nynorsk",
  sv: "Swedish",
  da: "Danish",
  fi: "Finnish",
  pl: "Polish",
  ru: "Russian",
  uk: "Ukrainian",
  tr: "Turkish",
  el: "Greek",
  ro: "Romanian",
  ja: "Japanese",
  ko: "Korean",
  "zh-Hans": "Simplified Chinese",
  "zh-Hant": "Traditional Chinese",
  th: "Thai",
  vi: "Vietnamese",
  ca: "Catalan",
  cs: "Czech",
  hr: "Croatian",
  hu: "Hungarian",
  id: "Indonesian",
  he: "Hebrew",
  hi: "Hindi",
  sk: "Slovak",
  ar: "Arabic"
};

const FIELD_LIMITS = {
  name: 30,
  subtitle: 30,
  promotional_text: 170,
  description: 4000,
  keywords: 100,
  release_notes: 4000
};

const FIELDS = ["name", "subtitle", "promotional_text", "description", "keywords", "release_notes"];
const STABLE_FIELDS = ["subtitle", "promotional_text"];
const RELEASE_FIELDS = ["description", "keywords", "release_notes"];
const TRANSLATED_FIELDS = [...STABLE_FIELDS, ...RELEASE_FIELDS];
const CONCURRENCY = 6;

async function loadEnvFile(filePath) {
  try {
    const content = await fs.readFile(filePath, "utf-8");
    for (const line of content.split(/\r?\n/)) {
      const match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
      if (!match || process.env[match[1]]) continue;

      let value = match[2].trim();
      if (
        (value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))
      ) {
        value = value.slice(1, -1);
      }
      process.env[match[1]] = value;
    }
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
}

async function readProjectLocales() {
  const content = await fs.readFile(XCODE_PROJECT_PATH, "utf-8");
  const match = content.match(/knownRegions\s*=\s*\(\s*([\s\S]*?)\s*\);/);

  if (!match) {
    throw new Error("Could not find knownRegions in project.pbxproj");
  }

  return match[1]
    .split(",")
    .map((region) => region.trim().replace(/"/g, ""))
    .filter((region) => region.length > 0 && region !== "Base");
}

function validateMetadata(metadata, locale, fields = FIELDS) {
  const errors = [];

  for (const field of fields) {
    const value = metadata[field];
    const limit = FIELD_LIMITS[field];

    if (value === undefined || value === null || value === "") {
      errors.push(`[${locale}] Missing required field: ${field}`);
      continue;
    }

    if (value.length > limit) {
      errors.push(`[${locale}] ${field} exceeds limit: ${value.length}/${limit} characters`);
    }
  }

  return errors;
}

async function readExistingFields(folderName, fields) {
  const localeDir = path.join(METADATA_OUTPUT_PATH, folderName);
  const existing = {};

  for (const field of fields) {
    try {
      existing[field] = (await fs.readFile(path.join(localeDir, `${field}.txt`), "utf-8")).trim();
    } catch {
      // Missing fields are generated below.
    }
  }

  return existing;
}

async function writeMetadataFiles(folderName, metadata) {
  const localeDir = path.join(METADATA_OUTPUT_PATH, folderName);
  await fs.mkdir(localeDir, { recursive: true });

  for (const field of FIELDS) {
    if (!(field in metadata)) continue;
    await fs.writeFile(path.join(localeDir, `${field}.txt`), `${metadata[field]}\n`, "utf-8");
  }
}

async function withRetry(fn, maxRetries = 3) {
  let lastError;

  for (let attempt = 0; attempt < maxRetries; attempt += 1) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      const retryable = error.status === 429 || error.status >= 500;
      if (!retryable || attempt === maxRetries - 1) break;

      const delayMs = 1000 * 2 ** attempt + Math.random() * 500;
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }

  throw lastError;
}

function extractParsedResponse(response) {
  if (response?.output_parsed && typeof response.output_parsed === "object") {
    return response.output_parsed;
  }

  for (const item of Array.isArray(response?.output) ? response.output : []) {
    for (const block of Array.isArray(item?.content) ? item.content : []) {
      if (block?.parsed && typeof block.parsed === "object") {
        return block.parsed;
      }
    }
  }

  if (typeof response?.output_text === "string") {
    return JSON.parse(response.output_text);
  }

  throw new Error("OpenAI response did not include parsed JSON");
}

async function translateMetadata(sourceMetadata, norwegianMetadata, targetLocale, languageName, fields) {
  const apiKey = process.env.OPENAI_API_KEY?.trim();
  if (!apiKey) {
    throw new Error("OPENAI_API_KEY is not set in .env.local at the repository root");
  }

  const sourceFields = Object.fromEntries(fields.map((field) => [field, sourceMetadata[field]]));
  const referenceFields = Object.fromEntries(fields.map((field) => [field, norwegianMetadata[field]]));
  const limitRules = fields
    .filter((field) => ["subtitle", "promotional_text", "keywords"].includes(field))
    .map((field) => `${field} (${FIELD_LIMITS[field]})`);
  const limitText = limitRules.length > 0 ? `\n4. Respect character limits: ${limitRules.join(", ")}` : "";

  const instructions = 'You are a professional App Store metadata translator for a private couples app called "Paeonia". Return only valid JSON.';
  const prompt = `Translate the following App Store metadata to ${languageName}.

CRITICAL RULES:
1. Preserve line breaks and bullet formatting
2. Keep keywords comma-separated without spaces after commas
3. Use natural, simple language for ordinary people${limitText}
5. Do not add claims that are not present in the source

Source metadata (English):
${JSON.stringify(sourceFields, null, 2)}

Reference translation (Norwegian Bokmal):
${JSON.stringify(referenceFields, null, 2)}

Return only a valid JSON object with these exact keys: ${fields.join(", ")}.`;

  const schema = {
    type: "object",
    additionalProperties: false,
    properties: Object.fromEntries(fields.map((field) => [field, { type: "string" }])),
    required: fields
  };

  const response = await withRetry(async () => {
    const result = await fetch(OPENAI_RESPONSES_API_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model: OPENAI_MODEL,
        store: false,
        max_output_tokens: 2200,
        reasoning: { effort: OPENAI_REASONING_EFFORT },
        instructions,
        input: [{ role: "user", content: [{ type: "input_text", text: prompt }] }],
        text: {
          format: {
            type: "json_schema",
            name: `metadata_${targetLocale.replace(/[^a-z0-9_]/gi, "_")}`,
            strict: true,
            schema
          }
        }
      })
    });

    const json = await result.json().catch(() => null);
    if (!result.ok) {
      const message = json?.error?.message || result.statusText || "OpenAI Responses API request failed";
      const error = new Error(`OpenAI Responses API (${result.status}): ${message}`);
      error.status = result.status;
      throw error;
    }

    return json;
  });

  return extractParsedResponse(response);
}

function translationFields(existingFields) {
  const missingFields = TRANSLATED_FIELDS.filter((field) => !(field in existingFields));
  if (!forceRegenerate) return missingFields;

  return [...RELEASE_FIELDS, ...STABLE_FIELDS.filter((field) => !(field in existingFields))];
}

async function processLocale(locale, folderName, metadata) {
  const languageName = LANGUAGE_NAMES[locale];
  if (!languageName) {
    return { locale, status: "error", error: `Unknown language: ${locale}` };
  }

  const existingFields = await readExistingFields(folderName, TRANSLATED_FIELDS);
  const fieldsToTranslate = translationFields(existingFields);

  if (fieldsToTranslate.length === 0) {
    return { locale, status: "exists" };
  }

  const translated = await translateMetadata(
    metadata[PRIMARY_LOCALE],
    metadata.nb,
    locale,
    languageName,
    fieldsToTranslate
  );
  const nextMetadata = {
    ...existingFields,
    ...translated,
    name: metadata[PRIMARY_LOCALE].name
  };

  const errors = validateMetadata(nextMetadata, locale);
  if (errors.length > 0) {
    throw new Error(errors.join("\n"));
  }

  await writeMetadataFiles(folderName, nextMetadata);
  return { locale, status: "translated" };
}

async function runConcurrent(items, worker, concurrency) {
  const results = [];
  let index = 0;

  async function runWorker() {
    while (index < items.length) {
      const item = items[index];
      index += 1;
      results.push(await worker(item));
    }
  }

  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, runWorker));
  return results;
}

async function main() {
  await loadEnvFile(path.join(__dirname, "../../.env.local"));

  console.log("App Store Metadata Generator");
  console.log("============================\n");

  const projectLocales = await readProjectLocales();
  console.log(`Found Xcode locales: ${projectLocales.join(", ")}\n`);

  const sourceData = JSON.parse(await fs.readFile(METADATA_SOURCE_PATH, "utf-8"));
  const { metadata } = sourceData;
  const validationErrors = [];

  for (const locale of SOURCE_LOCALES) {
    if (!metadata[locale]) {
      validationErrors.push(`Missing source metadata for locale: ${locale}`);
      continue;
    }
    validationErrors.push(...validateMetadata(metadata[locale], locale));
  }

  if (validationErrors.length > 0) {
    console.error("Validation errors:");
    validationErrors.forEach((error) => console.error(`  - ${error}`));
    process.exit(1);
  }

  if (validateOnly) {
    console.log("Source metadata validation passed.");
    return;
  }

  console.log("Writing source locale metadata...");
  for (const locale of SOURCE_LOCALES) {
    const folderName = ASC_FOLDER_MAP[locale];
    if (!folderName) continue;

    await writeMetadataFiles(folderName, metadata[locale]);
    console.log(`  ${folderName}`);
  }

  if (sourceOnly) {
    console.log("\nSource-only metadata generation complete.");
    return;
  }

  const sourceFolders = new Set(SOURCE_LOCALES.map((locale) => ASC_FOLDER_MAP[locale]).filter(Boolean));
  const localesToTranslate = projectLocales.filter((locale) => {
    const folderName = ASC_FOLDER_MAP[locale];
    return (
      !SOURCE_LOCALES.includes(locale) &&
      Boolean(folderName) &&
      !sourceFolders.has(folderName)
    );
  });

  if (localesToTranslate.length === 0) {
    console.log("\nNo additional App Store locales to translate.");
    return;
  }

  if (!process.env.OPENAI_API_KEY?.trim()) {
    console.log("\nOPENAI_API_KEY is not set, so additional locale translation was skipped.");
    return;
  }

  console.log(`\nTranslating ${localesToTranslate.length} additional locales...`);
  const results = await runConcurrent(
    localesToTranslate,
    async (locale) => processLocale(locale, ASC_FOLDER_MAP[locale], metadata),
    CONCURRENCY
  );

  const errors = results.filter((result) => result.status === "error");
  for (const result of results) {
    console.log(`  ${result.locale}: ${result.status}`);
  }

  if (errors.length > 0) {
    console.error("\nTranslation errors:");
    errors.forEach((result) => console.error(`  - ${result.locale}: ${result.error}`));
    process.exit(1);
  }

  console.log("\nMetadata generation complete.");
}

main().catch((error) => {
  console.error("Fatal error:", error.message);
  process.exit(1);
});
