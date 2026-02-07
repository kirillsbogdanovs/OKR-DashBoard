import { LightningElement, track, wire } from 'lwc';
import getObjectivesWithKeyResults from '@salesforce/apex/OKRController.getObjectivesWithKeyResults';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveObjective from '@salesforce/apex/OKRController.saveObjective';
import USER_ID from '@salesforce/user/Id';
import createRelatedRecord from '@salesforce/apex/OKRController.createRelatedRecord';
import getActiveUsers from '@salesforce/apex/OKRController.getActiveUsers';
import saveKeyResult from '@salesforce/apex/OKRController.saveKeyResult'; // ✅ import current user ID

export default class OkrDashboard extends LightningElement {
    userId = USER_ID;
    @track selectedYear = String(new Date().getFullYear());
    @track selectedObjectiveId;
    @track showRelatedModal = false;
    @track modalObjectApi;
    @track modalFields = [];
    @track selectedKeyResultId = null;
    @track showCreateModal = false;
    @track createObjectApi;
    @track createFields = [];
    @track createTitle = 'New Record';
    @track objectivesWithKeyResults;
    @track showKeyResultModal = false;
    @track keyResultObjectiveId;
    @track selectedUserId = USER_ID;
    @track userOptions = [];
    @track selectedUserName = '';
    @track showModal = false;
    wiredObjectives;


    // Year options for combobox
    get yearOptions() {
        return [
            { label: '2023', value: '2023' },
            { label: '2024', value: '2024' },
            { label: '2025', value: '2025' }
        ];
    }
    
    get effectiveOwnerId() {
        return this.selectedUserId || this.userId;
    }

   @wire(getActiveUsers)
    wiredUsers({ data, error }) {
        console.log('USERS WIRE data:', data);
        console.log('USERS WIRE error:', error);

    if (data) {
        this.userOptions = data; // already [{label,value}]
        // optional default to first user
        if (!this.selectedUserId && this.userOptions.length) {
            this.selectedUserId = this.userOptions[0].value;
        }
    } else if (error) {
        this.userOptions = [];
    }
}

     // Wire to Apex method
    @wire(getObjectivesWithKeyResults, { ownerId: '$selectedUserId', year: '$selectedYearInt' })
    wiredGetObjectives(result) {
        this.wiredObjectives = result;
        console.log('WIRE RESULT:', JSON.stringify(result));

        if (result.data) {
            this.objectivesWithKeyResults = result.data;
            console.log('Loaded objectives:', JSON.stringify(this.objectivesWithKeyResults));
        } else if (result.error) {
            console.error('getObjectivesWithKeyResults error', result.error);
            this.objectivesWithKeyResults = [];
        }
    }

    // 🧩 Group objectives by category (based on their wrapper.objective.Category__c)
    get groupedObjectives() {
    if (!this.objectivesWithKeyResults || this.objectivesWithKeyResults.length === 0){
        return [];
    }

    const grouped = {};

    this.objectivesWithKeyResults.forEach(wrapper => {
        const cat = wrapper.objective.Category__c || 'Other';

        if (!grouped[cat]) {
            grouped[cat] = { 
                category: cat, 
                objectives: [] 
            };
        }
        grouped[cat].objectives.push(wrapper);
    });

    return Object.values(grouped);
}

    // Options for objective selection combobox
    //get objectiveOptions() {
    //if (!this.objectivesWithKeyResults || this.objectivesWithKeyResults.length === 0) {
     //   return [];
    //}
    //return this.objectivesWithKeyResults.map(wrapper => ({
    //    label: wrapper.objective.Name,
    //    value: wrapper.objective.Id
    //}));
//}

     // 📆 Handle year change
    handleYearChange(event) {
        this.selectedYear = event.detail.value;
        if (this.wiredObjectives) {
            refreshApex(this.wiredObjectives);
        }
    }

    handleUserChange(event) {
        this.selectedUserId = event.detail.value;
    }

    // ➕ Handle new objective creation
    // async handleNewObjective() {
        //const result = await NewObjectiveModal.open({
            //size: 'medium',
            //description: 'Create a new objective',
           // isEdit: false
        //});

        //if (result && result.success) {
            //saveObjective({ obj: result.fields })
                //.then(() => {
                   // this.showToast('Success', 'Objective created!', 'success');
                  //  return refreshApex(this.wiredObjectives);
               // })
                //.catch(error => {
               //     this.showToast('Error', error.body.message, 'error');
              //  });
       // }
   // }

    handleNewObjective() {
        // Just open the child modal component
        this.showModal = true;
    }

    // Save new objective
    handleSaveObjective(event) {
         const fields = event.detail;

         fields.OwnerId = this.effectiveOwnerId;
         fields.User__c  = this.effectiveOwnerId;
         fields.Year__c  = parseInt(fields.Year__c ?? this.selectedYear, 10);

        saveObjective({obj: fields})
            .then(() => {
                this.showModal = false;
                this.showToast('Success', 'Objective created!', 'success');
                return this.wiredObjectives ? refreshApex(this.wiredObjectives) : null;
            })
            .catch(error => {
            this.showToast('Error', error.body?.message || 'Error saving objective', 'error');
        });
    }

    // Handle save from new objective modal
    handleSave(event) {
        this.handleSaveObjective(event);
    }

    computeCompletion(kr) {
    if (!kr.Target_Value__c || kr.Target_Value__c === 0) return 0;
    const value = (kr.Current_Value__c / kr.Target_Value__c) * 100;
    return Math.min(Math.round(value), 100);
    }

    // Style progress bar depending on completion
    progressVariant(kr) {
        return kr.Current_Value__c >= kr.Target_Value__c ? 'success' : 'base';
    }

    // Style completed key results (green text)
    krClass(kr) {
        return kr.Current_Value__c >= kr.Target_Value__c
            ? 'completed-kr'
            : 'incomplete-kr';
    }
    // Cancel modal
    handleCancelKeyResult() {
        this.showKeyResultModal = false;
    }

    // Show toast message
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
    handleMenuSelect(event) {
    const action = event.detail.value;

    switch (action) {
        case 'newObjective':
            this.handleNewObjective();
            break;

        case 'newKeyResult':
            this.keyResultObjectiveId = this.selectedObjectiveId;
            this.showKeyResultModal = true;
            break;

        case 'newReview':
            this.prepareKeyResultAndOpenModal(
                'Review__c',
                'New Review',
                ['Name', 'Description__c']
            );
            break;

        case 'newSurvey':
            this.prepareKeyResultAndOpenModal(
                'Survey__c',
                'New Survey',
                ['Name', 'Questions__c']
            );
            break;

        case 'newCaseStudy':
            this.prepareKeyResultAndOpenModal(
                'Case_Study__c',
                'New Case Study',
                ['Name', 'Industry__c']
            );
            break;
            
        case 'newGoogleReview':
            this.prepareKeyResultAndOpenModal(
                'Google_Review__c',
                'New Google Review',
                ['Name', 'Rating__c', 'Comment__c']
            );
            break;
            
        default:
            this.showToast('Error', 'Unknown menu action', 'error');
        }
    }

    prepareKeyResultAndOpenModal(objectApiName, title, fields) {
    const krId = this.getDefaultKeyResultId();

    if (!krId) {
        this.showToast(
            'Warning',
            'There are no Key Results yet for this user/year. Please create a Key Result first.',
            'warning'
        );
        return;
    }

    // store chosen KR so the modal can use it in the hidden Key_Result__c field
    this.selectedKeyResultId = krId;

    // reuse your existing method
    this.openCreateModal(objectApiName, title, fields);
    }
    openRelatedModal(objectApiName, fields) {
        this.modalObjectApi = objectApiName;
        this.modalFields = fields;
        this.showRelatedModal = true;
    }
    openCreateModal(objectApiName, title, fields) {
        this.createObjectApi = objectApiName;
        this.createTitle = title;
        this.createFields = fields;
        this.showCreateModal = true;
    }
    closeCreateModal() {
        this.showCreateModal = false;
    }
    handleCreateSuccess() {
        this.showToast('Success', `${this.createTitle} created!`, 'success');
        this.showCreateModal = false;
        // refresh your OKR data if the counts/related summaries should update
        if (this.wiredObjectives) {
            return refreshApex(this.wiredObjectives);
        }
    }
    handleKeyResultCancel() {
        this.showKeyResultModal = false;
    }

    handleCreateError(event) {
        const msg = event?.detail?.message || 'Failed to create record.';
        this.showToast('Error', msg, 'error');
    }

    handleRecordCreated() {
        this.showToast('Success', 'Record created successfully!', 'success');
        this.showRelatedModal = false;
        // Optionally refresh the list
        return refreshApex(this.wiredObjectives);
    }
    handleKeyResultSelect(event) {
        this.selectedKeyResultId = event.currentTarget.dataset.id;
        this.showToast('Info', 'Key Result selected!', 'info');
    }

    handleAddKeyResult(event) {
    // objective id comes from objectiveCard
        this.keyResultObjectiveId = event.detail;
        this.showKeyResultModal = true;
    }
    handleKeyResultSuccess() {
        this.showToast('Success', 'Key Result created!', 'success');
        this.showKeyResultModal = false;
        return this.wiredObjectives ? refreshApex(this.wiredObjectives) : null;
    }

    getDefaultKeyResultId() {
    // No data loaded yet
    if (!this.objectivesWithKeyResults || this.objectivesWithKeyResults.length === 0) {
        return null;
    }

    // 1) Prefer the Objective selected in the combobox, if any
    let candidateObj = null;
    if (this.selectedObjectiveId) {
        candidateObj = this.objectivesWithKeyResults.find(
            w => w.objective.Id === this.selectedObjectiveId
        );
    }

    // 2) Otherwise, pick the first objective that has at least one key result
    if (!candidateObj) {
        candidateObj = this.objectivesWithKeyResults.find(
            w => w.keyResults && w.keyResults.length > 0
        );
    }

    if (!candidateObj || !candidateObj.keyResults || candidateObj.keyResults.length === 0) {
        return null;
    }

    // We just take the FIRST key result under that objective
        return candidateObj.keyResults[0].keyResult.Id;
    }
    
    get selectedUserName() {
    if (!this.userOptions || !this.selectedUserId) {
        return '';
    }
    const match = this.userOptions.find(
        opt => opt.value === this.selectedUserId
    );
        return match ? match.label : '';
    }

    get displayUserName() {
        const opt = (this.userOptions || []).find(o => o.value === this.selectedUserId);
        return opt ? opt.label : '';
    }

    get selectedYearInt() {
        return parseInt(this.selectedYear, 10);
    }

    get hasObjectives() {
        return Array.isArray(this.objectivesWithKeyResults) && this.objectivesWithKeyResults.length > 0;
    }

    get objectivesCount() {
        return this.objectivesWithKeyResults ? this.objectivesWithKeyResults.length : 0;
    }

    handleSaveKeyResult(event) {
    saveKeyResult({ kr: event.detail })
        .then(() => refreshApex(this.wiredObjectives))
        .then(() => {
            this.showKeyResultModal = false;
            this.showToast('Success', 'Key Result created!', 'success');
        })
        .catch(err => {
            // IMPORTANT: show + log
            // eslint-disable-next-line no-console
            console.error('saveKeyResult error:', JSON.stringify(err));
            this.showToast(
                'Error',
                err?.body?.message || err?.message || 'Failed to save Key Result',
                'error'
            );
        });
    }

    // handleSaveObjective(event) {
    // const fields = { ...event.detail };

    // // If you want OwnerId = assigned user too:
    // fields.OwnerId = fields.User__c;

    // saveObjective({ obj: fields })
    //     .then(() => refreshApex(this.wiredObjectives))
    //     .then(() => {
    //         this.showModal = false;
    //         this.showToast('Success', 'Objective created!', 'success');
    //     })
    //     .catch(err => {
    //         this.showToast('Error', err.body?.message || err.message, 'error');
    //     });
    // }
    
    handleAddKeyResult(event) {
        this.selectedObjectiveId = event.detail.objectiveId;
        this.showKeyResultModal = true;
    }
    get objectiveOptions() {
    // if you have groupedObjectives = [{ category, objectives: [ { objective: {...}} ] }]
    const opts = [];
    (this.groupedObjectives || []).forEach(group => {
        (group.objectives || []).forEach(objWrap => {
            const obj = objWrap.objective;
            if (obj?.Id) {
                opts.push({ label: obj.Name, value: obj.Id });
            }
        });
    });

    return opts;
    }

    handleCancel() {
        this.showModal = false;
    }
}
