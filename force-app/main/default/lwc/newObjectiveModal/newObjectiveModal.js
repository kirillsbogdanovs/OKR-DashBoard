import { LightningElement, api } from 'lwc';

// This component is responsible for creating a new Objective.
export default class NewObjectiveModal extends LightningElement {
    @api userOptions = [];
    @api selectedUserId;
    @api year;

    yearOptions = [
        { label: '2023', value: '2023' },
        { label: '2024', value: '2024' },
        { label: '2025', value: '2025' }
    ];

    // Handle changes to the name field
     handleSave() {
        try {
            const nameEl = this.template.querySelector('[data-id="name"]');
            const descEl = this.template.querySelector('[data-id="desc"]');
            const userEl = this.template.querySelector('[data-id="user"]');
            const yearEl = this.template.querySelector('[data-id="year"]');

            if (!nameEl || !userEl || !yearEl) {
                throw new Error('Modal fields not found in template.');
            }

            const fields = {
                Name: nameEl.value,
                Description__c: descEl ? descEl.value : null,
                Year__c: parseInt(yearEl.value, 10),
                User__c: userEl.value
            };

            this.dispatchEvent(new CustomEvent('save', { detail: fields }));
        } catch (e) {
            console.error('newObjectiveModal handleSave error:', e);
            throw e;
        }
    }

    // Closes the fields without saving
    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }
}