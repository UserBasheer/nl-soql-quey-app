import { LightningElement, track, wire } from 'lwc';
import getObjects from '@salesforce/apex/SoqlWhispererController.getObjects';
import generateQuery from '@salesforce/apex/SoqlWhispererController.generateQuery';
import refineQuery from '@salesforce/apex/SoqlWhispererController.refineQuery';
import validateQuery from '@salesforce/apex/SoqlWhispererController.validateQuery';
import runQuery from '@salesforce/apex/SoqlWhispererController.runQuery';

// Objects we prefer to preselect on first load, in priority order, when present in the
// permission-scoped list. Preserves the pre-Phase-3 default grounding behavior.
const PREFERRED_DEFAULTS = ['Account', 'Contact', 'Case', 'Opportunity', 'Lead'];
// How many objects to preselect by default when none of the preferred ones are present.
const DEFAULT_FALLBACK_COUNT = 5;

export default class SoqlWhisperer extends LightningElement {
    @track naturalLanguage = '';
    @track soql = '';
    @track assumption = '';
    @track validationMessage = '';
    @track validationClass = '';
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

    @wire(getObjects)
    wiredObjects({ data, error }) {
        if (data) {
            this.objectOptions = data.map((o) => ({ label: o.label, value: o.apiName }));
            this.objectScope = this.computeDefaultSelection(this.objectOptions);
            this.objectsReady = true;
            this.objectsError = false;
            if (this.objectOptions.length === 0) {
                this.validationMessage =
                    '✗ No queryable objects are accessible to you. Ask an admin for object access.';
                this.validationClass =
                    'slds-box slds-box_xx-small slds-m-top_x-small slds-theme_warning';
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
        return this.objectsReady && !this.objectsError && this.objectOptions.length > 0;
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

    handleNlChange(e) { this.naturalLanguage = e.target.value; }
    handleSoqlChange(e) { this.soql = e.target.value; }

    handleClear() {
        this.naturalLanguage = '';
        this.soql = '';
        this.assumption = '';
        this.validationMessage = '';
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

    async handleValidate() { await this.runValidation(); }

    async runValidation() {
        const errors = await validateQuery({ soql: this.soql });
        if (errors && errors.length) {
            this.validationMessage = '✗ ' + errors.join(' ');
            this.validationClass = 'slds-box slds-box_xx-small slds-m-top_x-small slds-theme_error';
        } else {
            this.validationMessage = '✓ Valid — read-only and well-formed.';
            this.validationClass = 'slds-box slds-box_xx-small slds-m-top_x-small slds-theme_success';
        }
    }

    async handleRun() {
        this.isBusy = true;
        try {
            const rows = await runQuery({ soql: this.soql });
            this.buildColumns(rows);
            this.resultRows = rows;
        } catch (err) {
            this.showError(err);
        } finally {
            this.isBusy = false;
        }
    }

    buildColumns(rows) {
        if (!rows || !rows.length) { this.resultColumns = []; return; }
        this.resultColumns = Object.keys(rows[0])
            .filter((k) => k !== 'attributes')
            .map((k) => ({ label: k, fieldName: k, type: 'text' }));
    }

    showError(err) {
        const msg = err && err.body && err.body.message ? err.body.message : 'Unexpected error.';
        this.validationMessage = '✗ ' + msg;
        this.validationClass = 'slds-box slds-box_xx-small slds-m-top_x-small slds-theme_error';
    }
}
