import { LightningElement, api, track } from 'lwc';
import saveKeyResult from '@salesforce/apex/OKRController.saveKeyResult';
import saveKeyResultTargets from '@salesforce/apex/OKRController.saveKeyResultTargets';

export default class NewKeyResultModal extends LightningElement {
  @api objectiveOptions = [];
  @api defaultObjectiveId;

  @track objectiveId;
  @track name = '';
  @track targetRows = [
    { id: this.newRowId(), objectType: '', target: '' }
  ];

  objectOptions = [
    { label: 'Opportunities', value: 'Opportunity' },
    { label: 'Calls', value: 'Call' },
    { label: 'Contracts', value: 'Contract' },
    { label: 'WebLeads', value: 'WebLead' },
    { label: 'Surveys', value: 'Survey' },
    { label: 'Reviews', value: 'Review' },
    { label: 'GoogleReviews', value: 'GoogleReview' },
    { label: 'CaseStudies', value: 'CaseStudy' }
  ];

  connectedCallback() {
    // Initialize objectiveId from defaultObjectiveId
    this.objectiveId = this.defaultObjectiveId;
  }

  renderedCallback() {
    // Ensure objectiveId is set if it wasn't in connectedCallback
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

  handleObjectTypeChange(e) {
    const id = e.target.dataset.id;
    const val = e.detail.value;

    this.targetRows = this.targetRows.map(r => {
      if (r.id !== id) return r;
      return {
        ...r,
        objectType: val
      };
    });
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
        console.log('💾 ========== SAVE STARTED ==========');
        
        // Last-chance default for objectiveId
        if (!this.objectiveId) {
            if (this.defaultObjectiveId) {
                console.log('💾 Using defaultObjectiveId');
                this.objectiveId = this.defaultObjectiveId;
            } else if (this.objectiveOptions && this.objectiveOptions.length > 0) {
                console.log('💾 Using first option from objectiveOptions');
                this.objectiveId = this.objectiveOptions[0].value;
            }
        }

        console.log('💾 Final objectiveId:', this.objectiveId);

        // Validation
        if (!this.objectiveId) {
            throw new Error('Objective is required. Please select an objective.');
        }
        
        if (!this.name || !this.name.trim()) {
            throw new Error('Key Result Name is required.');
        }

        // Build cleaned targets
        const cleanedTargets = [];
        const seen = new Set();

        console.log('💾 Raw targetRows:', JSON.stringify(this.targetRows));

        for (const r of this.targetRows) {
            const objectType = (r.objectType || '').trim();
            if (!objectType) {
                throw new Error('Each target must have Object Type.');
            }

            const targetNum = Number(r.target);
            if (!Number.isFinite(targetNum) || targetNum < 0) {
                throw new Error('Each target must have a valid Target number.');
            }

            if (seen.has(objectType)) {
                throw new Error(`Duplicate Object Type: ${objectType}. Use one row per type.`);
            }
            seen.add(objectType);

            cleanedTargets.push({
                objectType,
                target: Math.trunc(targetNum)
            });
        }

        if (!cleanedTargets.length) {
            throw new Error('Add at least one target.');
        }

        console.log('💾 Cleaned targets:', JSON.stringify(cleanedTargets));

        // Step 1: create KR
        const krPayload = {
            sobjectType: 'Key_Result__c',
            Objective__c: this.objectiveId,
            Name: this.name.trim()
        };

        console.log('💾 Calling saveKeyResult with:', JSON.stringify(krPayload));

        const savedKr = await saveKeyResult({ kr: krPayload });

        console.log('✅ savedKr:', JSON.stringify(savedKr));
        console.log('✅ savedKr.Id:', savedKr.Id);

        // Step 2: save multiple targets
        console.log('💾 About to call saveKeyResultTargets...');
        console.log('💾 keyResultId:', savedKr.Id);
        console.log('💾 targets:', JSON.stringify(cleanedTargets));
        
        await saveKeyResultTargets({
          keyResultId: savedKr.Id,
          targets: JSON.stringify(cleanedTargets)  // ← Changed to pass as JSON string
      });

        console.log('✅ saveKeyResultTargets completed successfully');

        // Notify parent
        this.dispatchEvent(
            new CustomEvent('save', {
                detail: { keyResultId: savedKr.Id }
            })
        );
        
        console.log('💾 ========== SAVE COMPLETED ==========');
        
    } catch (err) {
        console.error('❌ ========== SAVE FAILED ==========');
        console.error('❌ Full error:', err);
        console.error('❌ Error message:', err?.message);
        console.error('❌ Error body:', err?.body);
        console.error('❌ Error body message:', err?.body?.message);
        console.error('❌ Error stack:', err?.stack);
        
        this.dispatchEvent(
            new CustomEvent('error', {
                detail: { 
                    message: err?.body?.message || err?.message || 'Failed to save Key Result' 
                }
            })
        );
    }
}

  handleCancel() {
    this.dispatchEvent(new CustomEvent('cancel'));
  }
}