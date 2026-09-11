import { createElement } from "lwc";
import SoqlWhisperer from "c/soqlWhisperer";
import getObjects from "@salesforce/apex/SoqlWhispererController.getObjects";
import generateQuery from "@salesforce/apex/SoqlWhispererController.generateQuery";
import refineQuery from "@salesforce/apex/SoqlWhispererController.refineQuery";
import getHistory from "@salesforce/apex/SoqlWhispererController.getHistory";
import clearHistory from "@salesforce/apex/SoqlWhispererController.clearHistory";
import saveQuery from "@salesforce/apex/SoqlWhispererController.saveQuery";
import getSavedQueries from "@salesforce/apex/SoqlWhispererController.getSavedQueries";
import deleteSavedQuery from "@salesforce/apex/SoqlWhispererController.deleteSavedQuery";

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

// Phase 4: saved queries + history passthroughs. getObjects/generateQuery/refineQuery/
// validateQuery/runQuery above were already explicit mocks in this file before Phase 4;
// these are new imports added to the component by Phase 4 and get the same treatment so
// tests below can assert on call arguments and control resolved values.
jest.mock(
  "@salesforce/apex/SoqlWhispererController.getHistory",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/SoqlWhispererController.clearHistory",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/SoqlWhispererController.saveQuery",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/SoqlWhispererController.getSavedQueries",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/SoqlWhispererController.deleteSavedQuery",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

// Export_Query_Results is not exercised by any test in this file — see the dedicated
// soqlWhispererExportPermissionGranted/Denied test files for permission-gating coverage,
// which each need their own module registry since the import is a static default binding.

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

// lightning-stubs don't reflect JS properties (e.g. `name`) as real DOM attributes, so
// attribute selectors like `lightning-combobox[name="x"]` silently fail. Query by tag and
// filter on the property instead, matching the `.find((ta) => ta.name === ...)` convention
// already used for lightning-textarea above.
function findByTagAndName(root, tag, name) {
  return Array.from(root.querySelectorAll(tag)).find((el) => el.name === name);
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

  // --- Phase 4: saved queries toolbar ------------------------------------------------------

  describe("saved queries", () => {
    const SAVED_QUERIES = [
      {
        Id: "a01000000000001",
        Name: "My Accounts",
        SOQL__c: "SELECT Id, Name FROM Account",
        Natural_Language__c: "list accounts",
        Object_Scope__c: "Account,Contact"
      }
    ];

    it("loads saved queries on init and populates the combobox options", async () => {
      getSavedQueries.mockResolvedValue(SAVED_QUERIES);

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      // One tick for the imperative Apex promise to resolve, a second for the reactive
      // re-render it triggers.
      await flushPromises();
      await flushPromises();

      expect(getSavedQueries).toHaveBeenCalledTimes(1);
      const combobox = findByTagAndName(
        element.shadowRoot,
        "lightning-combobox",
        "savedQueries"
      );
      expect(combobox.options).toEqual([
        { label: "My Accounts", value: "a01000000000001" }
      ]);
    });

    it("selecting a saved query repopulates soql, naturalLanguage and objectScope", async () => {
      getSavedQueries.mockResolvedValue(SAVED_QUERIES);

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      // Populate objectOptions so applyQueryContext's "still-visible objects" filter has
      // Account/Contact available to keep.
      getObjects.emit(ALL_OBJECT_OPTIONS);
      await flushPromises();

      const combobox = findByTagAndName(
        element.shadowRoot,
        "lightning-combobox",
        "savedQueries"
      );
      combobox.dispatchEvent(
        new CustomEvent("change", { detail: { value: "a01000000000001" } })
      );
      await flushPromises();

      const soqlTextarea = Array.from(
        element.shadowRoot.querySelectorAll("lightning-textarea")
      ).find((ta) => ta.name === "soql");
      const nlTextarea = Array.from(
        element.shadowRoot.querySelectorAll("lightning-textarea")
      ).find((ta) => ta.name === "nl");
      const dualListbox = element.shadowRoot.querySelector(
        "lightning-dual-listbox"
      );

      expect(soqlTextarea.value).toBe("SELECT Id, Name FROM Account");
      expect(nlTextarea.value).toBe("list accounts");
      expect(dualListbox.value).toEqual(["Account", "Contact"]);
    });

    it('reveals the inline name field on "Save current" and saves with the current context, then refreshes the list', async () => {
      getSavedQueries.mockResolvedValue([]);
      saveQuery.mockResolvedValue({
        Id: "a01000000000002",
        Name: "New Save"
      });

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      getObjects.emit(ALL_OBJECT_OPTIONS);
      await flushPromises();

      const soqlTextarea = Array.from(
        element.shadowRoot.querySelectorAll("lightning-textarea")
      ).find((ta) => ta.name === "soql");
      soqlTextarea.value = "SELECT Id FROM Account";
      soqlTextarea.dispatchEvent(new CustomEvent("change"));
      await flushPromises();

      // No inline name field until "Save current" is clicked. (findByTagAndName uses
      // Array.find, which returns undefined rather than null when nothing matches.)
      expect(
        findByTagAndName(element.shadowRoot, "lightning-input", "saveName")
      ).toBeUndefined();

      const saveCurrentButton = Array.from(
        element.shadowRoot.querySelectorAll("lightning-button")
      ).find((btn) => btn.label === "Save current");
      saveCurrentButton.click();
      await flushPromises();

      const nameInput = findByTagAndName(
        element.shadowRoot,
        "lightning-input",
        "saveName"
      );
      expect(nameInput).not.toBeNull();
      nameInput.value = "New Save";
      nameInput.dispatchEvent(new CustomEvent("change"));
      await flushPromises();

      getSavedQueries.mockResolvedValue([
        {
          Id: "a01000000000002",
          Name: "New Save",
          SOQL__c: "SELECT Id FROM Account"
        }
      ]);
      const confirmSaveButton = Array.from(
        element.shadowRoot.querySelectorAll("lightning-button")
      ).find((btn) => btn.label === "Save");
      confirmSaveButton.click();
      await flushPromises();
      await flushPromises();

      expect(saveQuery).toHaveBeenCalledWith(
        expect.objectContaining({
          name: "New Save",
          soql: "SELECT Id FROM Account"
        })
      );
      // Save must refresh the saved-queries list (initial load + post-save reload).
      expect(getSavedQueries).toHaveBeenCalledTimes(2);
    });

    it("deletes the selected saved query and refreshes the list", async () => {
      getSavedQueries.mockResolvedValue(SAVED_QUERIES);
      deleteSavedQuery.mockResolvedValue(undefined);

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      await flushPromises();

      const combobox = findByTagAndName(
        element.shadowRoot,
        "lightning-combobox",
        "savedQueries"
      );
      combobox.dispatchEvent(
        new CustomEvent("change", { detail: { value: "a01000000000001" } })
      );
      await flushPromises();

      getSavedQueries.mockResolvedValue([]);
      const deleteButton = Array.from(
        element.shadowRoot.querySelectorAll("lightning-button")
      ).find((btn) => btn.label === "Delete");
      deleteButton.click();
      await flushPromises();
      await flushPromises();

      expect(deleteSavedQuery).toHaveBeenCalledWith({
        recordId: "a01000000000001"
      });
      expect(getSavedQueries).toHaveBeenCalledTimes(2);
    });

    it("shows a toolbar error and clears the list when getSavedQueries fails on load", async () => {
      getSavedQueries.mockRejectedValue({ body: { message: "No access" } });

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      await flushPromises();
      await flushPromises();

      const combobox = findByTagAndName(
        element.shadowRoot,
        "lightning-combobox",
        "savedQueries"
      );
      expect(combobox.options).toEqual([]);
      expect(element.shadowRoot.textContent).toContain("No access");
    });

    it('shows an inline error instead of opening the name field when "Save current" is clicked with no SOQL', async () => {
      getSavedQueries.mockResolvedValue([]);

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      await flushPromises();

      const saveCurrentButton = Array.from(
        element.shadowRoot.querySelectorAll("lightning-button")
      ).find((btn) => btn.label === "Save current");
      saveCurrentButton.click();
      await flushPromises();

      expect(
        findByTagAndName(element.shadowRoot, "lightning-input", "saveName")
      ).toBeUndefined();
      expect(element.shadowRoot.textContent).toContain(
        "There is no SOQL to save"
      );
    });

    it('pre-fills the inline name field with the selected saved query\'s name when "Save current" is used to overwrite it', async () => {
      getSavedQueries.mockResolvedValue(SAVED_QUERIES);

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      await flushPromises();

      const combobox = findByTagAndName(
        element.shadowRoot,
        "lightning-combobox",
        "savedQueries"
      );
      combobox.dispatchEvent(
        new CustomEvent("change", { detail: { value: "a01000000000001" } })
      );
      await flushPromises();

      const saveCurrentButton = Array.from(
        element.shadowRoot.querySelectorAll("lightning-button")
      ).find((btn) => btn.label === "Save current");
      saveCurrentButton.click();
      await flushPromises();

      const nameInput = findByTagAndName(
        element.shadowRoot,
        "lightning-input",
        "saveName"
      );
      expect(nameInput.value).toBe("My Accounts");
    });

    it('"Cancel" on the inline save form hides it and clears the pending name', async () => {
      getSavedQueries.mockResolvedValue([]);

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      await flushPromises();

      const soqlTextarea = Array.from(
        element.shadowRoot.querySelectorAll("lightning-textarea")
      ).find((ta) => ta.name === "soql");
      soqlTextarea.value = "SELECT Id FROM Account";
      soqlTextarea.dispatchEvent(new CustomEvent("change"));
      await flushPromises();

      Array.from(element.shadowRoot.querySelectorAll("lightning-button"))
        .find((btn) => btn.label === "Save current")
        .click();
      await flushPromises();
      expect(
        findByTagAndName(element.shadowRoot, "lightning-input", "saveName")
      ).not.toBeUndefined();

      Array.from(element.shadowRoot.querySelectorAll("lightning-button"))
        .find((btn) => btn.label === "Cancel")
        .click();
      await flushPromises();

      expect(
        findByTagAndName(element.shadowRoot, "lightning-input", "saveName")
      ).toBeUndefined();
      expect(saveQuery).not.toHaveBeenCalled();
    });

    it("shows a toolbar error when saveQuery fails, without crashing the component", async () => {
      getSavedQueries.mockResolvedValue([]);
      saveQuery.mockRejectedValue({ body: { message: "Duplicate name" } });

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      await flushPromises();

      const soqlTextarea = Array.from(
        element.shadowRoot.querySelectorAll("lightning-textarea")
      ).find((ta) => ta.name === "soql");
      soqlTextarea.value = "SELECT Id FROM Account";
      soqlTextarea.dispatchEvent(new CustomEvent("change"));
      await flushPromises();

      Array.from(element.shadowRoot.querySelectorAll("lightning-button"))
        .find((btn) => btn.label === "Save current")
        .click();
      await flushPromises();

      const nameInput = findByTagAndName(
        element.shadowRoot,
        "lightning-input",
        "saveName"
      );
      nameInput.value = "Broken Save";
      nameInput.dispatchEvent(new CustomEvent("change"));
      await flushPromises();

      Array.from(element.shadowRoot.querySelectorAll("lightning-button"))
        .find((btn) => btn.label === "Save")
        .click();
      await flushPromises();
      await flushPromises();

      expect(element.shadowRoot.textContent).toContain("Duplicate name");
    });

    it("shows a toolbar error when deleteSavedQuery fails", async () => {
      getSavedQueries.mockResolvedValue(SAVED_QUERIES);
      deleteSavedQuery.mockRejectedValue({
        body: { message: "Cannot delete" }
      });

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      await flushPromises();

      const combobox = findByTagAndName(
        element.shadowRoot,
        "lightning-combobox",
        "savedQueries"
      );
      combobox.dispatchEvent(
        new CustomEvent("change", { detail: { value: "a01000000000001" } })
      );
      await flushPromises();

      Array.from(element.shadowRoot.querySelectorAll("lightning-button"))
        .find((btn) => btn.label === "Delete")
        .click();
      await flushPromises();
      await flushPromises();

      expect(element.shadowRoot.textContent).toContain("Cannot delete");
    });
  });

  // --- Phase 4: query history accordion ----------------------------------------------------

  describe("query history", () => {
    it("issues no Apex call to getHistory before the history section is expanded", async () => {
      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      await flushPromises();

      expect(getHistory).not.toHaveBeenCalled();

      // The datatable/empty-state should not render yet either, since history hasn't loaded.
      // (No results datatable exists in this scenario either, since no query was run.)
      expect(
        element.shadowRoot.querySelector("lightning-datatable")
      ).toBeNull();
    });

    it("loads history rows only after the accordion section is first expanded", async () => {
      getHistory.mockResolvedValue([
        {
          Id: "h01000000000001",
          Status__c: "Success",
          Row_Count__c: 3,
          CreatedDate: "2026-09-10T00:00:00.000Z",
          SOQL__c: "SELECT Id FROM Account"
        }
      ]);

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      await flushPromises();

      const accordion = element.shadowRoot.querySelector("lightning-accordion");
      accordion.dispatchEvent(
        new CustomEvent("sectiontoggle", {
          detail: { openSections: ["history"] }
        })
      );
      await flushPromises();
      await flushPromises();

      expect(getHistory).toHaveBeenCalledTimes(1);
      expect(getHistory).toHaveBeenCalledWith({ limitSize: 25 });

      const historyTable = element.shadowRoot.querySelector(
        "lightning-datatable"
      );
      expect(historyTable).not.toBeNull();
      expect(historyTable.data).toHaveLength(1);

      // Re-toggling should not issue a second call: the load is lazy on FIRST expand only,
      // subsequent state changes are driven by Refresh/Show more, not by re-toggling.
      accordion.dispatchEvent(
        new CustomEvent("sectiontoggle", { detail: { openSections: [] } })
      );
      await flushPromises();
      expect(getHistory).toHaveBeenCalledTimes(1);
    });

    it('restores soql, naturalLanguage and objectScope from a history row\'s "Load into editor" action', async () => {
      getHistory.mockResolvedValue([
        {
          Id: "h01000000000001",
          Status__c: "Success",
          Row_Count__c: 1,
          CreatedDate: "2026-09-10T00:00:00.000Z",
          SOQL__c: "SELECT Id FROM Contact",
          Natural_Language__c: "list contacts",
          Object_Scope__c: "Contact"
        }
      ]);

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      getObjects.emit(ALL_OBJECT_OPTIONS);
      await flushPromises();

      const accordion = element.shadowRoot.querySelector("lightning-accordion");
      accordion.dispatchEvent(
        new CustomEvent("sectiontoggle", {
          detail: { openSections: ["history"] }
        })
      );
      await flushPromises();
      await flushPromises();

      const historyTable = element.shadowRoot.querySelector(
        "lightning-datatable"
      );
      historyTable.dispatchEvent(
        new CustomEvent("rowaction", {
          detail: {
            action: { name: "load" },
            row: {
              SOQL__c: "SELECT Id FROM Contact",
              Natural_Language__c: "list contacts",
              Object_Scope__c: "Contact"
            }
          }
        })
      );
      await flushPromises();

      const soqlTextarea = Array.from(
        element.shadowRoot.querySelectorAll("lightning-textarea")
      ).find((ta) => ta.name === "soql");
      const nlTextarea = Array.from(
        element.shadowRoot.querySelectorAll("lightning-textarea")
      ).find((ta) => ta.name === "nl");
      const dualListbox = element.shadowRoot.querySelector(
        "lightning-dual-listbox"
      );

      expect(soqlTextarea.value).toBe("SELECT Id FROM Contact");
      expect(nlTextarea.value).toBe("list contacts");
      expect(dualListbox.value).toEqual(["Contact"]);
    });

    it('requires a confirm step before "Clear my history" calls clearHistory', async () => {
      getHistory.mockResolvedValue([]);
      clearHistory.mockResolvedValue(2);

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      await flushPromises();

      const accordion = element.shadowRoot.querySelector("lightning-accordion");
      accordion.dispatchEvent(
        new CustomEvent("sectiontoggle", {
          detail: { openSections: ["history"] }
        })
      );
      await flushPromises();
      await flushPromises();

      const findButton = (label) =>
        Array.from(
          element.shadowRoot.querySelectorAll("lightning-button")
        ).find((btn) => btn.label === label);

      findButton("Clear my history").click();
      await flushPromises();

      // Clicking once only reveals the destructive confirm button; clearHistory must not
      // be called yet.
      expect(clearHistory).not.toHaveBeenCalled();
      const confirmButton = findButton("Yes, delete all my history");
      expect(confirmButton).not.toBeUndefined();

      confirmButton.click();
      await flushPromises();
      await flushPromises();

      expect(clearHistory).toHaveBeenCalledTimes(1);
    });

    it("shows a toolbar error and marks history loaded (not stuck spinning) when getHistory fails", async () => {
      getHistory.mockRejectedValue({ body: { message: "No history access" } });

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      await flushPromises();

      const accordion = element.shadowRoot.querySelector("lightning-accordion");
      accordion.dispatchEvent(
        new CustomEvent("sectiontoggle", {
          detail: { openSections: ["history"] }
        })
      );
      await flushPromises();
      await flushPromises();

      expect(element.shadowRoot.textContent).toContain("No history access");
      expect(element.shadowRoot.querySelector("lightning-spinner")).toBeNull();
    });

    it('"Refresh" re-issues getHistory with the current page size', async () => {
      getHistory.mockResolvedValue([]);

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      await flushPromises();

      const accordion = element.shadowRoot.querySelector("lightning-accordion");
      accordion.dispatchEvent(
        new CustomEvent("sectiontoggle", {
          detail: { openSections: ["history"] }
        })
      );
      await flushPromises();
      await flushPromises();
      expect(getHistory).toHaveBeenCalledTimes(1);

      Array.from(element.shadowRoot.querySelectorAll("lightning-button"))
        .find((btn) => btn.label === "Refresh")
        .click();
      await flushPromises();
      await flushPromises();

      expect(getHistory).toHaveBeenCalledTimes(2);
      expect(getHistory).toHaveBeenLastCalledWith({ limitSize: 25 });
    });

    it('"Show more" doubles the requested page size, capped at the server-side ceiling of 200', async () => {
      // 25 rows returned so historyRows.length (25) >= historyLimit (25), which is what
      // makes "Show more" appear per canShowMoreHistory.
      getHistory.mockResolvedValue(
        Array.from({ length: 25 }, (_, i) => ({
          Id: `h0100000000${i}`,
          Status__c: "Success",
          Row_Count__c: 1,
          CreatedDate: "2026-09-10T00:00:00.000Z",
          SOQL__c: "SELECT Id FROM Account"
        }))
      );

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      await flushPromises();

      const accordion = element.shadowRoot.querySelector("lightning-accordion");
      accordion.dispatchEvent(
        new CustomEvent("sectiontoggle", {
          detail: { openSections: ["history"] }
        })
      );
      await flushPromises();
      await flushPromises();

      const showMoreButton = Array.from(
        element.shadowRoot.querySelectorAll("lightning-button")
      ).find((btn) => btn.label === "Show more");
      expect(showMoreButton).not.toBeUndefined();

      showMoreButton.click();
      await flushPromises();
      await flushPromises();

      expect(getHistory).toHaveBeenLastCalledWith({ limitSize: 50 });
    });

    it('"Cancel" on the clear-history confirm step hides it without calling clearHistory', async () => {
      getHistory.mockResolvedValue([]);

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      await flushPromises();

      const accordion = element.shadowRoot.querySelector("lightning-accordion");
      accordion.dispatchEvent(
        new CustomEvent("sectiontoggle", {
          detail: { openSections: ["history"] }
        })
      );
      await flushPromises();
      await flushPromises();

      const findButton = (label) =>
        Array.from(
          element.shadowRoot.querySelectorAll("lightning-button")
        ).find((btn) => btn.label === label);

      findButton("Clear my history").click();
      await flushPromises();
      expect(findButton("Yes, delete all my history")).not.toBeUndefined();

      findButton("Cancel").click();
      await flushPromises();

      expect(findButton("Yes, delete all my history")).toBeUndefined();
      expect(findButton("Clear my history")).not.toBeUndefined();
      expect(clearHistory).not.toHaveBeenCalled();
    });

    it("shows a toolbar error when clearHistory fails", async () => {
      getHistory.mockResolvedValue([]);
      clearHistory.mockRejectedValue({ body: { message: "Cannot clear" } });

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      await flushPromises();

      const accordion = element.shadowRoot.querySelector("lightning-accordion");
      accordion.dispatchEvent(
        new CustomEvent("sectiontoggle", {
          detail: { openSections: ["history"] }
        })
      );
      await flushPromises();
      await flushPromises();

      const findButton = (label) =>
        Array.from(
          element.shadowRoot.querySelectorAll("lightning-button")
        ).find((btn) => btn.label === label);

      findButton("Clear my history").click();
      await flushPromises();
      findButton("Yes, delete all my history").click();
      await flushPromises();
      await flushPromises();

      expect(element.shadowRoot.textContent).toContain("Cannot clear");
    });

    it("refreshes history after a run only if the history section was already expanded", async () => {
      getHistory.mockResolvedValue([]);

      const element = createElement("c-soql-whisperer", { is: SoqlWhisperer });
      document.body.appendChild(element);
      getObjects.emit(ALL_OBJECT_OPTIONS);
      await flushPromises();

      // Run a query BEFORE the history section has ever been expanded: no history refresh
      // should be triggered (this is the round-trip the lazy load exists to avoid).
      const runQueryButton = Array.from(
        element.shadowRoot.querySelectorAll("lightning-button")
      ).find((btn) => btn.label === "Run Query");
      runQueryButton.click();
      await flushPromises();
      await flushPromises();
      expect(getHistory).not.toHaveBeenCalled();

      // Now expand history (first load) and run again: this time a refresh is expected.
      const accordion = element.shadowRoot.querySelector("lightning-accordion");
      accordion.dispatchEvent(
        new CustomEvent("sectiontoggle", {
          detail: { openSections: ["history"] }
        })
      );
      await flushPromises();
      await flushPromises();
      expect(getHistory).toHaveBeenCalledTimes(1);

      runQueryButton.click();
      await flushPromises();
      await flushPromises();
      expect(getHistory).toHaveBeenCalledTimes(2);
    });
  });
});
