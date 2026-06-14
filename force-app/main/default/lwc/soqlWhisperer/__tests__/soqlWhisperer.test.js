import { createElement } from "lwc";
import SoqlWhisperer from "c/soqlWhisperer";
import getObjects from "@salesforce/apex/SoqlWhispererController.getObjects";
import generateQuery from "@salesforce/apex/SoqlWhispererController.generateQuery";
import refineQuery from "@salesforce/apex/SoqlWhispererController.refineQuery";

// Manual virtual mocks for the Apex methods used by c/soqlWhisperer.
// getObjects is wired (cacheable=true) -> mocked as an Apex test wire adapter so tests can
// `emit`/`error` data through it. generateQuery/refineQuery are called imperatively -> plain
// jest.fn()s so tests can assert on call arguments and control resolved values.
// `createApexTestWireAdapter` is required lazily inside the factory because jest.mock()
// factories cannot reference out-of-scope imported variables.
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
  "@salesforce/apex/SoqlWhispererController.generateQuery",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/SoqlWhispererController.refineQuery",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/SoqlWhispererController.validateQuery",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/SoqlWhispererController.runQuery",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const ALL_OBJECT_OPTIONS = [
  { apiName: "Account", label: "Account" },
  { apiName: "Case", label: "Case" },
  { apiName: "Contact", label: "Contact" },
  { apiName: "Lead", label: "Lead" },
  { apiName: "Opportunity", label: "Opportunity" }
];

const NON_PREFERRED_OPTIONS = [
  { apiName: "Asset", label: "Asset" },
  { apiName: "Building__c", label: "Building" },
  { apiName: "Campaign", label: "Campaign" },
  { apiName: "Contract", label: "Contract" },
  { apiName: "Document", label: "Document" },
  { apiName: "Event", label: "Event" }
];

function flushPromises() {
  return Promise.resolve();
}

describe("c-soql-whisperer", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("populates the dual-listbox options from the getObjects wire data", async () => {
    const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
    document.body.appendChild(element);

    getObjects.emit(ALL_OBJECT_OPTIONS);
    await flushPromises();

    const dualListbox = element.shadowRoot.querySelector(
      "lightning-dual-listbox"
    );
    expect(dualListbox).not.toBeNull();
    expect(dualListbox.options).toEqual(
      ALL_OBJECT_OPTIONS.map((o) => ({ label: o.label, value: o.apiName }))
    );
  });

  it("preselects the preferred default objects (Account, Contact, Case, Opportunity, Lead) when present", async () => {
    const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
    document.body.appendChild(element);

    getObjects.emit(ALL_OBJECT_OPTIONS);
    await flushPromises();

    const dualListbox = element.shadowRoot.querySelector(
      "lightning-dual-listbox"
    );
    expect(dualListbox.value).toEqual([
      "Account",
      "Contact",
      "Case",
      "Opportunity",
      "Lead"
    ]);
  });

  it("falls back to the first five label-sorted objects when no preferred defaults are present", async () => {
    const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
    document.body.appendChild(element);

    getObjects.emit(NON_PREFERRED_OPTIONS);
    await flushPromises();

    const dualListbox = element.shadowRoot.querySelector(
      "lightning-dual-listbox"
    );
    expect(dualListbox.value).toEqual([
      "Asset",
      "Building__c",
      "Campaign",
      "Contract",
      "Document"
    ]);
  });

  it("shows an empty-state warning and renders no picker when getObjects returns an empty list", async () => {
    const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
    document.body.appendChild(element);

    getObjects.emit([]);
    await flushPromises();

    const dualListbox = element.shadowRoot.querySelector(
      "lightning-dual-listbox"
    );
    expect(dualListbox).toBeNull();

    const warningBox = element.shadowRoot.querySelector(".slds-theme_warning");
    expect(warningBox).not.toBeNull();
    expect(warningBox.textContent).toContain(
      "No queryable objects are accessible to you"
    );
  });

  it("handles a getObjects wire error by clearing options/scope and showing an error message", async () => {
    const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
    document.body.appendChild(element);

    getObjects.error();
    await flushPromises();

    const dualListbox = element.shadowRoot.querySelector(
      "lightning-dual-listbox"
    );
    expect(dualListbox).toBeNull();

    const errorBox = element.shadowRoot.querySelector(".slds-theme_error");
    expect(errorBox).not.toBeNull();
  });

  it("passes the user-selected objectScope (not the full option set) to generateQuery", async () => {
    generateQuery.mockResolvedValue("SELECT Id FROM Account");
    refineQuery.mockResolvedValue("SELECT Id, Name FROM Account");

    const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
    document.body.appendChild(element);

    getObjects.emit(ALL_OBJECT_OPTIONS);
    await flushPromises();

    const dualListbox = element.shadowRoot.querySelector(
      "lightning-dual-listbox"
    );

    // User narrows the multi-select down to a single object.
    dualListbox.dispatchEvent(
      new CustomEvent("change", { detail: { value: ["Contact"] } })
    );
    await flushPromises();

    const textarea = Array.from(
      element.shadowRoot.querySelectorAll("lightning-textarea")
    ).find((ta) => ta.name === "nl");
    // handleNlChange reads e.target.value, so the stub's value property must be set
    // before the change event is dispatched.
    textarea.value = "Show me contacts created this week";
    textarea.dispatchEvent(new CustomEvent("change"));
    await flushPromises();

    const generateButton = Array.from(
      element.shadowRoot.querySelectorAll("lightning-button")
    ).find((btn) => btn.label === "Generate SOQL");
    generateButton.click();
    await flushPromises();
    await flushPromises();

    expect(generateQuery).toHaveBeenCalledWith(
      expect.objectContaining({ objectScope: ["Contact"] })
    );
  });

  it("passes the user-selected objectScope to refineQuery when refining an existing query", async () => {
    generateQuery.mockResolvedValue("SELECT Id FROM Account");
    refineQuery.mockResolvedValue("SELECT Id, Name FROM Account");

    const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
    document.body.appendChild(element);

    getObjects.emit(ALL_OBJECT_OPTIONS);
    await flushPromises();

    const dualListbox = element.shadowRoot.querySelector(
      "lightning-dual-listbox"
    );
    dualListbox.dispatchEvent(
      new CustomEvent("change", {
        detail: { value: ["Account", "Opportunity"] }
      })
    );
    await flushPromises();

    const textareas = Array.from(
      element.shadowRoot.querySelectorAll("lightning-textarea")
    );
    const textarea = textareas.find((ta) => ta.name === "nl");
    // handleNlChange/handleSoqlChange read e.target.value, so the stub's value
    // property must be set before the change event is dispatched.
    textarea.value = "Only show open opportunities";
    textarea.dispatchEvent(new CustomEvent("change"));
    await flushPromises();

    const soqlTextarea = textareas.find((ta) => ta.name === "soql");
    soqlTextarea.value = "SELECT Id FROM Opportunity";
    soqlTextarea.dispatchEvent(new CustomEvent("change"));
    await flushPromises();

    const refineButton = Array.from(
      element.shadowRoot.querySelectorAll("lightning-button")
    ).find((btn) => btn.label === "Refine");
    refineButton.click();
    await flushPromises();
    await flushPromises();

    expect(refineQuery).toHaveBeenCalledWith(
      expect.objectContaining({ objectScope: ["Account", "Opportunity"] })
    );
  });
});
