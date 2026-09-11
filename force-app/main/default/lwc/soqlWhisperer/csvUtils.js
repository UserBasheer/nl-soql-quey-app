/**
 * Pure CSV helpers for the soqlWhisperer result export.
 *
 * Everything here is DOM-free and side-effect-free so it can be unit tested directly.
 * The export is built entirely from rows already in the browser's memory — no Apex call,
 * no new query, no callout, no ContentVersion. The CSV never leaves the user's machine.
 */

/** UTF-8 byte order mark. Without it Excel mis-renders non-ASCII characters. */
export const CSV_BOM = "\uFEFF";

/** RFC 4180 uses CRLF as the record separator. */
const RECORD_SEPARATOR = "\r\n";

/**
 * Leading characters Excel / Google Sheets treat as the start of a formula. A cell beginning
 * with one of these is prefixed with a single quote so an exported value such as
 * `=HYPERLINK("http://evil","click")` is rendered as text instead of executed.
 */
const FORMULA_TRIGGERS = ["=", "+", "-", "@", "\t", "\r"];

/** Characters that force a field to be quoted under RFC 4180. */
const MUST_QUOTE = /["\n\r,]/;

/**
 * Render one value as a CSV field.
 * - null / undefined -> empty string
 * - objects (nested relationship records) -> JSON.stringify. This mirrors the datatable's
 *   existing flat-column limitation rather than changing query behaviour.
 * - formula-injection defense, then RFC 4180 quoting/escaping.
 */
export function toCsvCell(value) {
  let text;
  if (value === null || value === undefined) {
    text = "";
  } else if (typeof value === "object") {
    text = JSON.stringify(value);
  } else {
    text = String(value);
  }

  // Injection defense runs BEFORE quoting so the guard quote ends up inside the quoted
  // field, where the spreadsheet still sees it as the first character of the value.
  if (text.length > 0 && FORMULA_TRIGGERS.indexOf(text.charAt(0)) !== -1) {
    text = `'${text}`;
  }

  if (MUST_QUOTE.test(text)) {
    text = `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

/**
 * Build the full CSV document for the current result set.
 *
 * @param {Array<object>} rows    result rows, exactly as held by the datatable
 * @param {Array<object>} columns datatable column defs; `fieldName` drives both the header
 *                                row and the per-row lookup, so the export always matches
 *                                what is on screen (`attributes` is already excluded there)
 * @returns {string} BOM-prefixed, CRLF-delimited CSV
 */
export function buildCsv(rows, columns) {
  const fields = (columns || [])
    .map((column) => (column ? column.fieldName : null))
    .filter((fieldName) => !!fieldName);

  if (fields.length === 0) {
    return CSV_BOM;
  }

  const lines = [fields.map(toCsvCell).join(",")];
  (rows || []).forEach((row) => {
    lines.push(
      fields.map((fieldName) => toCsvCell(row ? row[fieldName] : "")).join(",")
    );
  });
  return CSV_BOM + lines.join(RECORD_SEPARATOR);
}

/** `soql-results-YYYYMMDD-HHmmss.csv`, in the user's local time. */
export function buildCsvFileName(when) {
  const stamp = when instanceof Date ? when : new Date();
  const pad = (value) => String(value).padStart(2, "0");
  const date = `${stamp.getFullYear()}${pad(stamp.getMonth() + 1)}${pad(stamp.getDate())}`;
  const time = `${pad(stamp.getHours())}${pad(stamp.getMinutes())}${pad(stamp.getSeconds())}`;
  return `soql-results-${date}-${time}.csv`;
}

/**
 * Data URI for the CSV. A `data:` URI is used rather than `URL.createObjectURL` because blob
 * URLs are unreliable under Lightning Locker / LWS. Trade-off: data URIs are size-capped by
 * the browser (low hundreds of MB in practice), which is far beyond any result set the
 * datatable can realistically hold.
 */
export function toCsvDataUri(csv) {
  return `data:text/csv;charset=utf-8,${encodeURIComponent(csv)}`;
}
