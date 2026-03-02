import { LightningElement, api, track } from 'lwc';
import saveKeyResult from '@salesforce/apex/OKRController.saveKeyResult';
import saveKeyResultTargets from '@salesforce/apex/OKRController.saveKeyResultTargets';

export default class NewKeyResultModal extends LightningElement {
    @api objectiveOptions = [];
    @api defaultObjectiveId;
    @track objectiveId;
    @track name = '';
    @track targetRows = [
        { id: Date.now() + '_init', objectType: '', target: '' }
    ];

    objectOptions = [
        { label: 'Opportunities', value: 'Opportunity' },
        { label: 'Calls', value: 'Call' },
        { label: 'Contracts', value: 'Contract' },
        { label: 'WebLeads', value: 'WebLead' },
        { label: 'Surveys', value: 'Survey' },
        { label: 'Reviews', value: 'Review' },
        { label: 'GoogleReviews', value: 'GoogleReview' },
        { label: 'CaseStudies', value: 'CaseStudy' },
        { label: 'Events', value: 'Event' }
    ];

    statusOptions = [
        { label: 'Not Started', value: 'Not Started' },
        { label: 'In progress', value: 'In progress' },
        { label: 'Completed', value: 'Completed' },
        { label: 'Abandoned', value: 'Abandoned' }
    ];

    connectedCallback() {
        this.objectiveId = this.defaultObjectiveId;
    }

    renderedCallback() {
        if (!this.objectiveId && this.objectiveOptions && this.objectiveOptions.length > 0) {
            this.objectiveId = this.defaultObjectiveId || this.objectiveOptions[0].value;
        }
    }

    newRowId() {
        return `${Date.now()}_${Math.random().toString(16).slice(2)}`;
    }

    addRow() {
        this.targetRows = [
            ...this.targetRows,
            { id: this.newRowId(), objectType: '', target: '' }
        ];
    }

    handleObjectiveChange(e) {
        this.objectiveId = e.detail.value;
    }

    handleNameChange(e) {
        this.name = e.detail.value;
    }

    handleStatusChange(e) {
        this.status = e.detail.value;
    }

    handleObjectTypeChange(e) {
        const id = e.target.dataset.id;
        const val = e.detail.value;
        this.targetRows = this.targetRows.map(r =>
            r.id !== id ? r : { ...r, objectType: val }
        );
    }

    handleTargetChange(e) {
        const id = e.currentTarget.dataset.id;
        const value = e.target.value;
        this.targetRows = this.targetRows.map(r =>
            r.id === id ? { ...r, target: value } : r
        );
    }

    removeRow(e) {
        const id = e.currentTarget.dataset.id;
        this.targetRows = this.targetRows.filter(r => r.id !== id);
    }

    async handleSave() {
        try {
            // Ensure objectiveId
            if (!this.objectiveId) {
                this.objectiveId = this.defaultObjectiveId ||
                    (this.objectiveOptions?.length ? this.objectiveOptions[0].value : null);
            }

            if (!this.objectiveId) throw new Error('Objective is required.');
            if (!this.name?.trim()) throw new Error('Key Result Name is required.');

            // Validate and build targets
            const objectTypes = [];
            const targetValues = [];
            const seen = new Set();

            for (const r of this.targetRows) {
                const objectType = (r.objectType || '').trim();
                if (!objectType) throw new Error('Each target must have Object Type.');

                const targetNum = Number(r.target);
                if (!Number.isFinite(targetNum) || targetNum < 0) {
                    throw new Error('Each target must have a valid number.');
                }
                if (seen.has(objectType)) {
                    throw new Error(`Duplicate Object Type: ${objectType}`);
                }
                seen.add(objectType);
                objectTypes.push(objectType);
                targetValues.push(Math.trunc(targetNum));
            }

            if (!objectTypes.length) throw new Error('Add at least one target.');

            // Step 1: Save Key Result
            const savedKr = await saveKeyResult({
                kr: {
                    sobjectType: 'Key_Result__c',
                    Objective__c: this.objectiveId,
                    Name: this.name.trim()
                }
            });

            const targetsJson = JSON.stringify(
                objectTypes.map((ot, i) => ({
                    objectType: ot,
                    target: targetValues[i]
                }))
            );

            // Step 2: Save targets using simple arrays
            await saveKeyResultTargets({
                keyResultId: savedKr.Id,
                targetsJson: targetsJson
            });

            //console.log('✅ Targets saved!');

            this.dispatchEvent(new CustomEvent('save', {
                detail: { keyResultId: savedKr.Id }
            }));

        } catch (err) {
            console.error('❌ Error:', err);
            this.dispatchEvent(new CustomEvent('error', {
                detail: {
                    message: err?.body?.message || err?.message || 'Failed to save'
                }
            }));
        }
    }
    connectedCallback() {
        console.log('objectivesWithKeyResults', JSON.stringify(this.objectivesWithKeyResults));
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }
}