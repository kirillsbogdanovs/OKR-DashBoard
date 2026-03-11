import { LightningElement, api } from 'lwc';
import { deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

const ACTIONS = [
    { label: 'View', name: 'view' },
    { label: 'Delete', name: 'delete' }
];

// This component displays related records for a given Key Result and allows users to view or delete them.
export default class RelatedRecordsViewer extends LightningElement {
    @api keyResultId;

    records = [];
    isLoading = true;
    hasError = false;
    wiredRecordsResult;

    columns = [
        { label: 'Type', fieldName: 'recordType', type: 'text' },
        { label: 'Name', fieldName: 'name', type: 'text' },
        { label: 'Date', fieldName: 'recordDate', type: 'date' },
        { label: 'Status', fieldName: 'status', type: 'text' },
        {
            type: 'action',
            typeAttributes: { rowActions: ACTIONS }
        }
    ];

    // Lifecycle hook to fetch records when component is initialized
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'view') {
            console.log('Viewing record', row.recordId);
        } else if (actionName === 'delete') {
            this.deleteRow(row.recordId);
        }
    }

    // Deletes a record and refreshes the list upon success
    async deleteRow(recordId) {
        try {
            await deleteRecord(recordId);
            this.showToast('Success', 'Record deleted', 'success');
            if (this.wiredRecordsResult) {
                await refreshApex(this.wiredRecordsResult);
            }
        } catch (error) {
            this.showToast('Error', error.body?.message || error.message, 'error');
        }
    }

    // Fetches related records for the given Key Result
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}