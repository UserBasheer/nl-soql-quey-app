import { createElement } from "lwc";
import SoqlWhisperer from "c/soqlWhisperer";
import getObjects from "@salesforce/apex/SoqlWhispererController.getObjects";
import runQuery from "@salesforce/apex/SoqlWhispererController.runQuery";

// See soqlWhispererExportPermissionGranted.test.js for why this is a separate file: the
// custom permission is a static default import resolved once per module registry.
jest.mock(
  "@salesforce/customPermission/Export_Query_Results",
  () => ({ default: false }),
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

function flushPromises() {
  return Promise.resolve();
}

function findButtonByLabel(root, label) {
  return Array.from(root.querySelectorAll("lightning-button")).find(
    (btn) => btn.label === label
  );
}

describe("c-soql-whisperer export button (Export_Query_Results denied)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("never renders Export CSV, even with results on screen, when the custom permission is absent", async () => {
    runQuery.mockResolvedValue([{ Id: "001000000000001", Name: "Acme" }]);

    const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
    document.body.appendChild(element);
    getObjects.emit([]);
    await flushPromises();

    const runButton = findButtonByLabel(element.shadowRoot, "Run Query");
    runButton.click();
    await flushPromises();
    await flushPromises();

    // Sanity check: results really did land (datatable rendered), so the absence of the
    // export button below is proven to be permission-gating, not a lack of results.
    expect(
      element.shadowRoot.querySelector("lightning-datatable")
    ).not.toBeNull();
    expect(findButtonByLabel(element.shadowRoot, "Export CSV")).toBeUndefined();
  });
});
