import { LightningElement, api } from 'lwc';

export default class NewObjectiveModal extends LightningElement {
    @api userOptions = [];
    @api selectedUserId;
    @api year;

    yearOptions = [
        { label: '2023', value: '2023' },
        { label: '2024', value: '2024' },
        { label: '2025', value: '2025' }
    ];

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

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }
}