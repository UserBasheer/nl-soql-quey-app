import { LightningElement, track } from 'lwc';
import generateQuery from '@salesforce/apex/SoqlWhispererController.generateQuery';
import refineQuery from '@salesforce/apex/SoqlWhispererController.refineQuery';
import validateQuery from '@salesforce/apex/SoqlWhispererController.validateQuery';
import runQuery from '@salesforce/apex/SoqlWhispererController.runQuery';

export default class SoqlWhisperer extends LightningElement {
    @track naturalLanguage = '';
    @track soql = '';
    @track assumption = '';
    @track validationMessage = '';
    @track validationClass = '';
    @track resultRows = [];
    @track resultColumns = [];
    @track isBusy = false;

    // Phase 1: scope which objects' schema is sent for grounding.
    // Phase 3 upgrades this to relevance-based retrieval for large orgs.
    objectScope = ['Account', 'Contact', 'Case', 'Opportunity', 'Lead'];

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
        if (!this.naturalLanguage) return;
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
        if (!this.naturalLanguage || !this.soql) return;
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
