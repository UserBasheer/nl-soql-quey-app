import {
  CSV_BOM,
  toCsvCell,
  buildCsv,
  buildCsvFileName,
  toCsvDataUri
} from "../csvUtils";

describe("csvUtils", () => {
  describe("toCsvCell", () => {
    it("renders null and undefined as an empty string", () => {
      expect(toCsvCell(null)).toBe("");
      expect(toCsvCell(undefined)).toBe("");
    });

    it("renders falsy-but-present primitives as their string form, not empty", () => {
      expect(toCsvCell(0)).toBe("0");
      expect(toCsvCell(false)).toBe("false");
    });

    it("leaves a plain string with no special characters unquoted", () => {
      expect(toCsvCell("Acme Corp")).toBe("Acme Corp");
    });

    it("quotes a field containing a comma", () => {
      expect(toCsvCell("Acme, Inc.")).toBe('"Acme, Inc."');
    });

    it("quotes a field containing a newline", () => {
      expect(toCsvCell("line1\nline2")).toBe('"line1\nline2"');
    });

    it("quotes a field containing a carriage return", () => {
      expect(toCsvCell("line1\rline2")).toBe('"line1\rline2"');
    });

    it("quotes a field containing a double quote and doubles the embedded quote", () => {
      expect(toCsvCell('he said "hi"')).toBe('"he said ""hi"""');
    });

    it("stringifies nested objects and then quotes them (embedded double quotes)", () => {
      expect(toCsvCell({ Name: "Acme" })).toBe('"{""Name"":""Acme""}"');
    });

    it.each([
      ["=SUM(A1:A2)", "'=SUM(A1:A2)"],
      ["+1234567890", "'+1234567890"],
      ["-1234567890", "'-1234567890"],
      ["@mention", "'@mention"]
    ])(
      "prefixes formula-injection trigger %s with a single quote",
      (input, expected) => {
        expect(toCsvCell(input)).toBe(expected);
      }
    );

    it("prefixes a leading tab and still leaves the field unquoted (tab is not a MUST_QUOTE char)", () => {
      expect(toCsvCell("\tpayload")).toBe("'\tpayload");
    });

    it("prefixes a leading carriage return AND quotes the result, since \\r also triggers RFC 4180 quoting", () => {
      expect(toCsvCell("\rpayload")).toBe('"\'\rpayload"');
    });

    it("does not prefix a value where the trigger character appears mid-string, not leading", () => {
      expect(toCsvCell("total = 5")).toBe("total = 5");
    });
  });

  describe("buildCsv", () => {
    it("builds a header row from column fieldNames and a data row per input row", () => {
      const columns = [{ fieldName: "Name" }, { fieldName: "Amount" }];
      const rows = [
        { Name: "Acme", Amount: 100 },
        { Name: "Globex", Amount: 250 }
      ];
      const csv = buildCsv(rows, columns);
      expect(csv).toBe(`${CSV_BOM}Name,Amount\r\nAcme,100\r\nGlobex,250`);
    });

    it("prepends the UTF-8 BOM to the output", () => {
      const csv = buildCsv([], [{ fieldName: "Name" }]);
      expect(csv.startsWith(CSV_BOM)).toBe(true);
    });

    it("excludes columns with no fieldName (e.g. the row-action column) from the header", () => {
      const columns = [
        { fieldName: "Name" },
        { type: "action" },
        { fieldName: null }
      ];
      const csv = buildCsv([{ Name: "Acme" }], columns);
      expect(csv).toBe(`${CSV_BOM}Name\r\nAcme`);
    });

    it("tolerates a null/undefined entry within the columns array", () => {
      const columns = [{ fieldName: "Name" }, null, undefined];
      const csv = buildCsv([{ Name: "Acme" }], columns);
      expect(csv).toBe(`${CSV_BOM}Name\r\nAcme`);
    });

    it("tolerates a null/undefined entry within the rows array by rendering an empty row", () => {
      const columns = [{ fieldName: "Name" }];
      const csv = buildCsv([null, { Name: "Acme" }, undefined], columns);
      expect(csv).toBe(`${CSV_BOM}Name\r\n\r\nAcme\r\n`);
    });

    it("renders null/undefined cell values as empty strings", () => {
      const columns = [{ fieldName: "Name" }, { fieldName: "Amount" }];
      const rows = [
        { Name: "Acme", Amount: null },
        { Name: null, Amount: 5 }
      ];
      const csv = buildCsv(rows, columns);
      expect(csv).toBe(`${CSV_BOM}Name,Amount\r\nAcme,\r\n,5`);
    });

    it("returns just the BOM when there are no usable columns", () => {
      expect(buildCsv([{ Name: "Acme" }], [])).toBe(CSV_BOM);
      expect(buildCsv([{ Name: "Acme" }], null)).toBe(CSV_BOM);
    });

    it("treats a null/undefined rows argument as zero data rows", () => {
      const csv = buildCsv(null, [{ fieldName: "Name" }]);
      expect(csv).toBe(`${CSV_BOM}Name`);
    });

    it("escapes and injection-guards values within full rows, not just single cells", () => {
      const columns = [{ fieldName: "Formula" }, { fieldName: "Note" }];
      const rows = [{ Formula: "=1+1", Note: 'say "hi", ok' }];
      const csv = buildCsv(rows, columns);
      expect(csv).toBe(`${CSV_BOM}Formula,Note\r\n'=1+1,"say ""hi"", ok"`);
    });
  });

  describe("buildCsvFileName", () => {
    it("formats a given date as soql-results-YYYYMMDD-HHmmss.csv with zero-padding", () => {
      const when = new Date(2026, 8, 10, 5, 6, 7); // Sept 10 2026, 05:06:07 local time
      expect(buildCsvFileName(when)).toBe("soql-results-20260910-050607.csv");
    });

    it("zero-pads single-digit month/day/hour/minute/second components", () => {
      const when = new Date(2026, 0, 1, 0, 0, 0); // Jan 1 2026, 00:00:00 local time
      expect(buildCsvFileName(when)).toBe("soql-results-20260101-000000.csv");
    });

    it("defaults to the current date/time when no argument is given", () => {
      expect(buildCsvFileName()).toMatch(/^soql-results-\d{8}-\d{6}\.csv$/);
    });
  });

  describe("toCsvDataUri", () => {
    it("builds a percent-encoded text/csv data URI", () => {
      const csv = `${CSV_BOM}Name,Amount\r\nAcme, Inc.,100`;
      expect(toCsvDataUri(csv)).toBe(
        `data:text/csv;charset=utf-8,${encodeURIComponent(csv)}`
      );
    });
  });
});
