import { createElement } from "lwc";
import SoqlWhisperer from "c/soqlWhisperer";
import getObjects from "@salesforce/apex/SoqlWhispererController.getObjects";
import runQuery from "@salesforce/apex/SoqlWhispererController.runQuery";

// Dedicated file: @salesforce/customPermission/Export_Query_Results is imported as a
// static default binding, resolved once when this module graph is first loaded. To test
// both "permission granted" and "permission denied" we need two separate test files, each
// with its own module registry, rather than one file trying to flip the value mid-run.
jest.mock(
  "@salesforce/customPermission/Export_Query_Results",
  () => ({ default: true }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/SoqlWhispererController.getObjects",
  () => ({
    default:
      require("@salesforce/wire-service-jest-util").createApexTestWireAdapter(
        jest.fn()
      )
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/SoqlWhispererController.runQuery",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

// generateQuery/refineQuery/validateQuery/getHistory/clearHistory/saveQuery/
// getSavedQueries/deleteSavedQuery are not exercised by these tests. @lwc/jest-transformer
// gives every un-mocked "@salesforce/apex/*" default import a safe fallback (a function
// resolving to undefined), so no explicit jest.mock is required for them here.

function flushPromises() {
  return Promise.resolve();
}

function findButtonByLabel(root, label) {
  return Array.from(root.querySelectorAll("lightning-button")).find(
    (btn) => btn.label === label
  );
}

describe("c-soql-whisperer export button (Export_Query_Results granted)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("does not render Export CSV before any query has been run (no results yet)", async () => {
    const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
    document.body.appendChild(element);
    getObjects.emit([]);
    await flushPromises();

    expect(findButtonByLabel(element.shadowRoot, "Export CSV")).toBeUndefined();
  });

  it("renders Export CSV once results exist and the custom permission is granted", async () => {
    runQuery.mockResolvedValue([{ Id: "001000000000001", Name: "Acme" }]);

    const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
    document.body.appendChild(element);
    getObjects.emit([]);
    await flushPromises();

    const runButton = findButtonByLabel(element.shadowRoot, "Run Query");
    runButton.click();
    await flushPromises();
    await flushPromises();

    const exportButton = findButtonByLabel(element.shadowRoot, "Export CSV");
    expect(exportButton).not.toBeUndefined();
  });

  it("builds a CSV data URI and triggers a download when Export CSV is clicked", async () => {
    runQuery.mockResolvedValue([{ Id: "001000000000001", Name: "Acme" }]);
    const clickSpy = jest
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(() => {});

    const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
    document.body.appendChild(element);
    getObjects.emit([]);
    await flushPromises();

    findButtonByLabel(element.shadowRoot, "Run Query").click();
    await flushPromises();
    await flushPromises();

    findButtonByLabel(element.shadowRoot, "Export CSV").click();
    await flushPromises();

    expect(clickSpy).toHaveBeenCalledTimes(1);
    const anchor = clickSpy.mock.instances[0];
    expect(anchor.href).toMatch(/^data:text\/csv;charset=utf-8,/);
    expect(anchor.download).toMatch(/^soql-results-\d{8}-\d{6}\.csv$/);

    clickSpy.mockRestore();
  });
});
