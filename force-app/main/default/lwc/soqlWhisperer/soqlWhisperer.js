import { LightningElement, track, wire } from "lwc";
import hasExportPermission from "@salesforce/customPermission/Export_Query_Results";
import getObjects from "@salesforce/apex/SoqlWhispererController.getObjects";
import generateQuery from "@salesforce/apex/SoqlWhispererController.generateQuery";
import refineQuery from "@salesforce/apex/SoqlWhispererController.refineQuery";
import validateQuery from "@salesforce/apex/SoqlWhispererController.validateQuery";
import runQuery from "@salesforce/apex/SoqlWhispererController.runQuery";
import getHistory from "@salesforce/apex/SoqlWhispererController.getHistory";
import clearHistory from "@salesforce/apex/SoqlWhispererController.clearHistory";
import saveQuery from "@salesforce/apex/SoqlWhispererController.saveQuery";
import getSavedQueries from "@salesforce/apex/SoqlWhispererController.getSavedQueries";
import deleteSavedQuery from "@salesforce/apex/SoqlWhispererController.deleteSavedQuery";
import { buildCsv, buildCsvFileName, toCsvDataUri } from "./csvUtils";

// Objects we prefer to preselect on first load, in priority order, when present in the
// permission-scoped list. Preserves the pre-Phase-3 default grounding behavior.
const PREFERRED_DEFAULTS = [
  "Account",
  "Contact",
  "Case",
  "Opportunity",
  "Lead"
];
// How many objects to preselect by default when none of the preferred ones are present.
const DEFAULT_FALLBACK_COUNT = 5;

// History paging. The server clamps to 200 regardless of what we ask for; these constants
// keep the client from asking for something the server would only reject.
const HISTORY_PAGE_SIZE = 25;
const HISTORY_MAX_LIMIT = 200;
// How much SOQL to show in the history table before eliding.
const HISTORY_SOQL_PREVIEW_LENGTH = 120;

const HISTORY_COLUMNS = [
  { label: "Status", fieldName: "Status__c", type: "text", initialWidth: 90 },
  {
    label: "Rows",
    fieldName: "Row_Count__c",
    type: "number",
    initialWidth: 80
  },
  {
    label: "Run at",
    fieldName: "CreatedDate",
    type: "date",
    initialWidth: 170,
    typeAttributes: {
      year: "numeric",
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    }
  },
  { label: "SOQL", fieldName: "soqlPreview", type: "text", wrapText: true },
  {
    type: "action",
    typeAttributes: {
      rowActions: [{ label: "Load into editor", name: "load" }]
    }
  }
];

const THEME = {
  error: "slds-box slds-box_xx-small slds-m-top_x-small slds-theme_error",
  success: "slds-box slds-box_xx-small slds-m-top_x-small slds-theme_success",
  warning: "slds-box slds-box_xx-small slds-m-top_x-small slds-theme_warning"
};

export default class SoqlWhisperer extends LightningElement {
  @track naturalLanguage = "";
  @track soql = "";
  @track assumption = "";
  @track validationMessage = "";
  @track validationClass = "";
  @track resultRows = [];
  @track resultColumns = [];
  @track isBusy = false;

  // Phase 3: permission-scoped object grounding. `objectOptions` is sourced from
  // SchemaService.listObjects() via getObjects(); `objectScope` is the user's selection
  // and is passed unchanged (List<String> of API names) to generate/refine.
  @track objectOptions = [];
  @track objectScope = [];
  @track objectsReady = false;
  @track objectsError = false;

  // Phase 4: saved queries.
  @track savedQueries = [];
  @track savedQueryOptions = [];
  @track selectedSavedQueryId = "";
  @track isNamingSave = false;
  @track saveName = "";
  @track toolbarMessage = "";
  @track toolbarClass = "";

  // Phase 4: history. Loaded lazily — never on component init.
  @track historyRows = [];
  @track historyColumns = HISTORY_COLUMNS;
  @track historyLimit = HISTORY_PAGE_SIZE;
  @track historyLoaded = false;
  @track historyBusy = false;
  @track isConfirmingClear = false;

  connectedCallback() {
    // Saved queries populate a toolbar combobox that is visible immediately, so they are
    // fetched up front. History is NOT — see handleHistoryToggle.
    this.loadSavedQueries();
  }

  @wire(getObjects)
  wiredObjects({ data, error }) {
    if (data) {
      this.objectOptions = data.map((o) => ({
        label: o.label,
        value: o.apiName
      }));
      this.objectScope = this.computeDefaultSelection(this.objectOptions);
      this.objectsReady = true;
      this.objectsError = false;
      if (this.objectOptions.length === 0) {
        this.validationMessage =
          "✗ No queryable objects are accessible to you. Ask an admin for object access.";
        this.validationClass = THEME.warning;
      }
    } else if (error) {
      this.objectOptions = [];
      this.objectScope = [];
      this.objectsReady = true;
      this.objectsError = true;
      this.showError(error);
    }
  }

  // Preselect preferred objects if present; otherwise the first few alphabetically
  // (the list arrives label-sorted from SchemaService). Never returns more than available.
  computeDefaultSelection(options) {
    const available = new Set(options.map((o) => o.value));
    const preferred = PREFERRED_DEFAULTS.filter((api) => available.has(api));
    if (preferred.length > 0) {
      return preferred;
    }
    return options.slice(0, DEFAULT_FALLBACK_COUNT).map((o) => o.value);
  }

  handleObjectScopeChange(e) {
    this.objectScope = e.detail.value;
  }

  get hasObjectOptions() {
    return (
      this.objectsReady && !this.objectsError && this.objectOptions.length > 0
    );
  }

  get hasScope() {
    return this.objectScope && this.objectScope.length > 0;
  }

  get actionsDisabled() {
    return this.isBusy || !this.hasScope;
  }

  get hasResults() {
    return this.resultRows && this.resultRows.length > 0;
  }

  handleNlChange(e) {
    this.naturalLanguage = e.target.value;
  }
  handleSoqlChange(e) {
    this.soql = e.target.value;
  }

  handleClear() {
    this.naturalLanguage = "";
    this.soql = "";
    this.assumption = "";
    this.validationMessage = "";
    this.resultRows = [];
    this.resultColumns = [];
  }

  async handleGenerate() {
    if (!this.naturalLanguage || !this.hasScope) return;
    this.isBusy = true;
    try {
      this.soql = await generateQuery({
        naturalLanguage: this.naturalLanguage,
        objectScope: this.objectScope
      });
      await this.runValidation();
    } catch (err) {
      this.showError(err);
    } finally {
      this.isBusy = false;
    }
  }

  async handleRefine() {
    if (!this.naturalLanguage || !this.soql || !this.hasScope) return;
    this.isBusy = true;
    try {
      this.soql = await refineQuery({
        instruction: this.naturalLanguage,
        existingQuery: this.soql,
        objectScope: this.objectScope
      });
      await this.runValidation();
    } catch (err) {
      this.showError(err);
    } finally {
      this.isBusy = false;
    }
  }

  async handleValidate() {
    await this.runValidation();
  }

  async runValidation() {
    const errors = await validateQuery({ soql: this.soql });
    if (errors && errors.length) {
      this.validationMessage = "✗ " + errors.join(" ");
      this.validationClass = THEME.error;
    } else {
      this.validationMessage = "✓ Valid — read-only and well-formed.";
      this.validationClass = THEME.success;
    }
  }

  async handleRun() {
    this.isBusy = true;
    try {
      // Natural language + object scope travel with the run so the server can record
      // them in history; the query itself is unchanged.
      const rows = await runQuery({
        soql: this.soql,
        naturalLanguage: this.naturalLanguage,
        objectScope: this.objectScope
      });
      this.buildColumns(rows);
      this.resultRows = rows;
    } catch (err) {
      this.showError(err);
    } finally {
      this.isBusy = false;
      // Only refresh history if the user has already opened the panel — otherwise this
      // would reintroduce the round-trip the lazy load exists to avoid.
      if (this.historyLoaded) {
        this.loadHistory();
      }
    }
  }

  buildColumns(rows) {
    if (!rows || !rows.length) {
      this.resultColumns = [];
      return;
    }
    this.resultColumns = Object.keys(rows[0])
      .filter((k) => k !== "attributes")
      .map((k) => ({ label: k, fieldName: k, type: "text" }));
  }

  // --- Export (client-side only: no Apex, no callout, no ContentVersion) ---

  get canExport() {
    return this.hasResults && hasExportPermission === true;
  }

  handleExport() {
    if (!this.canExport) return;
    const csv = buildCsv(this.resultRows, this.resultColumns);
    const link = document.createElement("a");
    link.href = toCsvDataUri(csv);
    link.download = buildCsvFileName(new Date());
    link.target = "_self";
    link.click();
  }

  // --- Saved queries ---

  async loadSavedQueries() {
    try {
      const records = await getSavedQueries();
      this.savedQueries = records || [];
      this.savedQueryOptions = this.savedQueries.map((r) => ({
        label: r.Name,
        value: r.Id
      }));
      if (!this.savedQueries.some((r) => r.Id === this.selectedSavedQueryId)) {
        this.selectedSavedQueryId = "";
      }
    } catch (err) {
      this.savedQueries = [];
      this.savedQueryOptions = [];
      this.showToolbarError(err);
    }
  }

  get hasSavedQueries() {
    return this.savedQueryOptions.length > 0;
  }

  get deleteSavedDisabled() {
    return this.isBusy || !this.selectedSavedQueryId;
  }

  get saveConfirmDisabled() {
    return this.isBusy || !this.saveName || !this.soql;
  }

  handleSavedQueryChange(e) {
    this.selectedSavedQueryId = e.detail.value;
    const record = this.savedQueries.find(
      (r) => r.Id === this.selectedSavedQueryId
    );
    if (!record) return;
    this.applyQueryContext(
      record.SOQL__c,
      record.Natural_Language__c,
      record.Object_Scope__c
    );
    this.showToolbarMessage(`Loaded "${record.Name}".`, THEME.success);
  }

  handleSaveCurrentClick() {
    if (!this.soql) {
      this.showToolbarMessage(
        "✗ There is no SOQL to save. Generate or type a query first.",
        THEME.error
      );
      return;
    }
    const selected = this.savedQueries.find(
      (r) => r.Id === this.selectedSavedQueryId
    );
    this.saveName = selected ? selected.Name : "";
    this.isNamingSave = true;
  }

  handleSaveNameChange(e) {
    this.saveName = e.target.value;
  }

  handleSaveCancel() {
    this.isNamingSave = false;
    this.saveName = "";
  }

  async handleSaveConfirm() {
    if (!this.saveName || !this.soql) return;
    this.isBusy = true;
    try {
      const saved = await saveQuery({
        name: this.saveName,
        soql: this.soql,
        naturalLanguage: this.naturalLanguage,
        objectScope: this.objectScope
      });
      this.isNamingSave = false;
      this.saveName = "";
      await this.loadSavedQueries();
      if (saved && saved.Id) {
        this.selectedSavedQueryId = saved.Id;
      }
      this.showToolbarMessage("✓ Saved.", THEME.success);
    } catch (err) {
      this.showToolbarError(err);
    } finally {
      this.isBusy = false;
    }
  }

  async handleDeleteSaved() {
    if (!this.selectedSavedQueryId) return;
    this.isBusy = true;
    try {
      await deleteSavedQuery({ recordId: this.selectedSavedQueryId });
      this.selectedSavedQueryId = "";
      await this.loadSavedQueries();
      this.showToolbarMessage("✓ Deleted.", THEME.success);
    } catch (err) {
      this.showToolbarError(err);
    } finally {
      this.isBusy = false;
    }
  }

  // --- History ---

  handleHistoryToggle(e) {
    const open = e && e.detail ? e.detail.openSections : null;
    const isOpen = Array.isArray(open)
      ? open.includes("history")
      : open === "history";
    // Lazy: the first expand is the first Apex call. Component init makes none.
    if (isOpen && !this.historyLoaded) {
      this.loadHistory();
    }
  }

  async loadHistory() {
    this.historyBusy = true;
    try {
      const records = await getHistory({ limitSize: this.historyLimit });
      this.historyRows = (records || []).map((r) => ({
        ...r,
        soqlPreview: this.previewOf(r.SOQL__c)
      }));
      this.historyLoaded = true;
    } catch (err) {
      this.historyRows = [];
      this.historyLoaded = true;
      this.showToolbarError(err);
    } finally {
      this.historyBusy = false;
    }
  }

  previewOf(soql) {
    if (!soql) return "";
    return soql.length > HISTORY_SOQL_PREVIEW_LENGTH
      ? `${soql.substring(0, HISTORY_SOQL_PREVIEW_LENGTH)}…`
      : soql;
  }

  handleHistoryRefresh() {
    this.loadHistory();
  }

  get canShowMoreHistory() {
    return (
      this.historyLimit < HISTORY_MAX_LIMIT &&
      this.historyRows.length >= this.historyLimit
    );
  }

  handleShowMoreHistory() {
    this.historyLimit = Math.min(HISTORY_MAX_LIMIT, this.historyLimit * 2);
    this.loadHistory();
  }

  handleClearHistoryClick() {
    this.isConfirmingClear = true;
  }

  handleClearHistoryCancel() {
    this.isConfirmingClear = false;
  }

  async handleClearHistoryConfirm() {
    this.historyBusy = true;
    try {
      const deleted = await clearHistory();
      this.isConfirmingClear = false;
      this.historyRows = [];
      this.historyLimit = HISTORY_PAGE_SIZE;
      this.showToolbarMessage(
        `✓ Cleared ${deleted} history record(s).`,
        THEME.success
      );
    } catch (err) {
      this.showToolbarError(err);
    } finally {
      this.historyBusy = false;
    }
  }

  handleHistoryRowAction(e) {
    const action = e.detail.action ? e.detail.action.name : null;
    const row = e.detail.row;
    if (action !== "load" || !row) return;
    this.applyQueryContext(
      row.SOQL__c,
      row.Natural_Language__c,
      row.Object_Scope__c
    );
    this.showToolbarMessage("Loaded from history.", THEME.success);
  }

  get hasHistoryRows() {
    return this.historyRows.length > 0;
  }

  get historyIsEmpty() {
    return (
      this.historyLoaded && !this.historyBusy && this.historyRows.length === 0
    );
  }

  // --- Shared helpers ---

  /**
   * Restore a stored query into the editor: SOQL, the originating prompt, and the object
   * scope, so a follow-up Refine is grounded exactly as the original run was.
   */
  applyQueryContext(soql, naturalLanguage, objectScopeCsv) {
    this.soql = soql || "";
    this.naturalLanguage = naturalLanguage || "";
    const stored = (objectScopeCsv || "")
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
    if (stored.length === 0) return;
    // Drop anything the running user can no longer see, otherwise the dual-listbox would
    // hold a value with no matching option.
    const available = new Set(this.objectOptions.map((o) => o.value));
    const usable =
      available.size > 0 ? stored.filter((api) => available.has(api)) : stored;
    if (usable.length > 0) {
      this.objectScope = usable;
    }
  }

  showError(err) {
    this.validationMessage = "✗ " + this.messageOf(err);
    this.validationClass = THEME.error;
  }

  showToolbarError(err) {
    this.showToolbarMessage("✗ " + this.messageOf(err), THEME.error);
  }

  showToolbarMessage(message, themeClass) {
    this.toolbarMessage = message;
    this.toolbarClass = themeClass;
  }

  messageOf(err) {
    return err && err.body && err.body.message
      ? err.body.message
      : "Unexpected error.";
  }
}
