import { LightningElement, track, wire } from 'lwc';
import getObjectivesWithKeyResults from '@salesforce/apex/OKRController.getObjectivesWithKeyResults';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveObjective from '@salesforce/apex/OKRController.saveObjective';
import USER_ID from '@salesforce/user/Id';
import createRelatedRecord from '@salesforce/apex/OKRController.createRelatedRecord';
import getActiveUsers from '@salesforce/apex/OKRController.getActiveUsers';
import saveKeyResult from '@salesforce/apex/OKRController.saveKeyResult';
import createEventLink from '@salesforce/apex/OKRController.createEventLink'; // ✅ import current user ID

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

    // Wire to get active users for the user filter dropdown
   @wire(getActiveUsers)
    wiredUsers({ data, error }) {
        console.log('USERS WIRE data:', data);
        console.log('USERS WIRE error:', error);

    if (data) {
        this.userOptions = data;
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

    // Group objectives by category (based on their wrapper.objective.Category__c)
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

     // Handle year change
    handleYearChange(event) {
        this.selectedYear = event.detail.value;
        if (this.wiredObjectives) {
            refreshApex(this.wiredObjectives);
        }
    }

    // Handle user change
    handleUserChange(event) {
        this.selectedUserId = event.detail.value;
    }

    // Open modal to create new objective
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

    // Handle click on OKR Menu buttons
    handleMenuSelect(event) {
    const action = event.detail.value;

    switch (action) {
        case 'newObjective':
            this.handleNewObjective();
            break;

        case 'newKeyResult':
            // Make sure we have a valid objective ID
            if (!this.selectedObjectiveId && this.objectiveOptions && this.objectiveOptions.length > 0) {
                this.keyResultObjectiveId = this.objectiveOptions[0].value;
            } else {
                this.keyResultObjectiveId = this.selectedObjectiveId;
            }

            if (!this.keyResultObjectiveId) {
                this.showToast('Warning', 'No Objectives available. Create an Objective first.', 'warning');
                break;
            }

            console.log('Opening modal with objectiveId:', this.keyResultObjectiveId);
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

    // Prepare data and open modal for creating related record (Review, Survey, etc.)
    prepareKeyResultAndOpenModal(objectApiName, title, fields) {
    const krId = this.getDefaultKeyResultId(objectApiName);

    if (!krId) {
        this.showToast(
            'Warning',
            'There are no Key Results yet for this user/year. Please create a Key Result first.',
            'warning'
        );
        return;
    }

    const ObjectTypeList = {
        'Survey__c': {count: 'surveyCount', target: 'surveyTarget'},
        'Review__c': {count: 'reviewCount', target: 'reviewTarget'},
        'Case_Study__c': {count: 'caseStudyCount', target: 'caseStudyTarget'},
        'Google_Review__c': {count: 'googleReviewCount', target: 'googleReviewTarget'}
    };

    const objmapping = ObjectTypeList[objectApiName];
    if (objmapping) {
        for (const wrapper of (this.objectivesWithKeyResults || [])) {
            for (const krWrapper of (wrapper.keyResults || [])){
                if (krWrapper.keyResult.Id === krId) {
                    console.log('objectApiName:', objectApiName);
                    console.log('krId selected:', krId);
                    console.log('selectedObjectiveId:', this.selectedObjectiveId);
                    const currentcount = krWrapper[objmapping.count] || 0;
                    const targetcount = krWrapper[objmapping.target] || 0;
                    if (targetcount > 0 && currentcount >= targetcount) {
                        console.log('Found KR:', krWrapper.keyResult.Name);
                        console.log('currentcount:', currentcount, 'targetcount:', targetcount);
                        this.showToast('Warning', `Maximum target for ${title} has been reached!`, 'warning');
                        return;
                    }
                }
            }
        }
    }

    // store chosen KR so the modal can use it in the hidden Key_Result__c field
    this.selectedKeyResultId = krId;

    // reuse your existing method
    this.openCreateModal(objectApiName, title, fields);
    }
    // Open generic create modal for related records (Reviews, Surveys, etc.)
    openRelatedModal(objectApiName, fields) {
        this.modalObjectApi = objectApiName;
        this.modalFields = fields;
        this.showRelatedModal = true;
    }
    // Open generic create modal for related records (Reviews, Surveys, etc.)
    openCreateModal(objectApiName, title, fields) {
        this.createObjectApi = objectApiName;
        this.createTitle = title;
        this.createFields = fields;
        this.showCreateModal = true;
    }
    // Close modals
    closeCreateModal() {
        this.showCreateModal = false;
    }
    // Close modals when new record is created successfully
    handleCreateSuccess() {
        this.showToast('Success', `${this.createTitle} created!`, 'success');
        this.showCreateModal = false;
        // refresh your OKR data if the counts/related summaries should update
        if (this.wiredObjectives) {
            return refreshApex(this.wiredObjectives);
        }
    }

    // Cancel related record modal without creating
    handleKeyResultCancel() {
        this.showKeyResultModal = false;
    }

    // Handle errors from the create record modal
    handleCreateError(event) {
        const msg = event?.detail?.message || 'Failed to create record.';
        this.showToast('Error', msg, 'error');
    }

    // Handle successful creation of related record (Review, Survey, etc.)
    handleRecordCreated() {
        this.showToast('Success', 'Record created successfully!', 'success');
        this.showRelatedModal = false;
        // Optionally refresh the list
        return refreshApex(this.wiredObjectives);
    }

    // Handle click on a Key Result to select it (for creating related records)
    handleKeyResultSelect(event) {
        this.selectedKeyResultId = event.currentTarget.dataset.id;
        this.showToast('Info', 'Key Result selected!', 'info');
    }

    // Handle click on button under a Key Result
    handleAddKeyResult(event) {
    // objective id comes from objectiveCard
        this.keyResultObjectiveId = event.detail;
        this.showKeyResultModal = true;
    }

    // Handle successful creation of a Key Result
    handleKeyResultSuccess() {
        this.showToast('Success', 'Key Result created!', 'success');
        this.showKeyResultModal = false;
        return this.wiredObjectives ? refreshApex(this.wiredObjectives) : null;
    }

    // If no KR is found for the selected objective, take the first KR that it can find under that objective
    getDefaultKeyResultId(objectApiName) {
    // No data loaded yet
    if (!this.objectivesWithKeyResults || this.objectivesWithKeyResults.length === 0) {
        return null;
    }

    const objectTypeList = {
        'Survey__c': 'surveyTarget',
        'Review__c': 'reviewTarget',
        'Case_Study__c': 'caseStudyTarget',
        'Google_Review__c': 'googleReviewTarget'
    };

    const targetField = objectTypeList[objectApiName];

    // 1) Prefer the Objective selected in the combobox, if any
    let candidateObj = this.selectedObjectiveId 
    ? this.objectivesWithKeyResults.find(w => w.objective.Id === this.selectedObjectiveId
    ) : null;

    // 2) Otherwise, pick the first objective that has at least one key result
    if (!candidateObj) {
        candidateObj = this.objectivesWithKeyResults.find(w => w.keyResults?.length > 0);
    }

    if (!candidateObj) return null;

    // If we know the object type, prefer a KR that has a target for it
    if (targetField) {
        const krWithTarget = candidateObj.keyResults.find(kr => (kr[targetField] || 0) > 0);
        if (krWithTarget) return krWithTarget.keyResult.Id;
    }

    // We just take the FIRST key result under that objective
        return candidateObj.keyResults[0]?.keyResult?.Id ?? null;
    }

    // ======================
    // Getters for UI display
    // ======================

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

    // Handle successful creation of a Key Result and refresh the data to show it in the list
    handleSaveKeyResult(event) {
        
        console.log('Key Result saved, refreshing data...');
        
        this.showKeyResultModal = false;
        
        if (this.wiredObjectives) {
            refreshApex(this.wiredObjectives)
                .then(() => {
                    this.showToast('Success', 'Key Result created!', 'success');
                })
                .catch(err => {
                    console.error('Error refreshing objectives:', err);
                    this.showToast('Warning', 'Key Result created but data refresh failed. Please reload the page.', 'warning');
                });
        } else {
            this.showToast('Success', 'Key Result created!', 'success');
        }
    }
    
    // Handle click on adding Key Result with button from objectiveCard, open the modal and pass the selected objective id
    handleAddKeyResult(event) {
        // When launched from objectiveCard context, we have a concrete objective id

        // Guard if somehow missing
        this.showKeyResultModal = false;
    
        if (this.wiredObjectives) {
            refreshApex(this.wiredObjectives)
                .then(() => {
                    this.showToast('Success', 'Key Result created!', 'success');
                })
                .catch(err => {
                    console.error('Error refreshing objectives:', err);
                    this.showToast('Warning', 'Key Result created but data refresh failed. Please reload the page.', 'warning');
                });
        } else {
            this.showToast('Success', 'Key Result created!', 'success');
        }
    }

    // Getters to build options for comboboxes based on loaded data
    get objectiveOptions() {
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

    // Build options for the "Select Key Result" dropdown in the related record creation modal
    get keyResultOptions() {
        const options = [];
        if (this.objectivesWithKeyResults) {
            this.objectivesWithKeyResults.forEach(w =>{
                    (w?.keyResults?? []).forEach(kr => {
                        options.push({
                            label: kr?.keyResult?.Name,
                            value: kr?.keyResult?.Id
                        });
                    });
            });
        }
        return options;
    }

    // Handle change in the "Select Key Result" dropdown in the related record creation modal
    handleKeyResultChange(e){
        this.selectedKeyResultId = e.detail.value;
    }

    // Handle successful creation of related record (Review, Survey, etc.) and refresh the data to show it in the list
    handleCreateSuccess(event){
        const recordId = event.detail.id;
        const objectTypeMap = {
            'Survey__c': 'Survey',
            'Review__c': 'Review',
            'Case_Study__c': 'CaseStudy',
            'Google_Review__c': 'GoogleReview'
        };
        const objectType = objectTypeMap[this.createObjectApi];

        createEventLink({
            keyResultId: this.selectedKeyResultId,
            recordId: recordId,
            objectType: objectType
         })
        .then(() => {
            this.showToast('Success', `${this.createTitle} created!`, 'success');
            this.showCreateModal = false;
            if (this.wiredObjectives) {
                refreshApex(this.wiredObjectives).then(() => {
                    console.log('Data refreshed');
                    console.log('Current data:', JSON.stringify(this.objectivesWithKeyResults));
                });
            }
        })
        .catch(err => {
            console.log('Full error:', JSON.stringify(err));
            this.showToast('Error', err.body?.message || 'Error creating link', 'error');
        });
    }

    // Cancel related record modal without creating
    handleCancel() {
        this.showModal = false;
    }
}
