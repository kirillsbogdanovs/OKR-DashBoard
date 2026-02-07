import { LightningElement, api } from 'lwc';

export default class NewKeyResultModal extends LightningElement {
  @api objectiveOptions = [];
  @api defaultObjectiveId;

  objectiveId;
  name = '';
  metric = 'Opportunities';
  target = '';

  metricOptions = [
    { label: 'Opportunities', value: 'Opportunities' },
    { label: 'Calls', value: 'Calls' },
    { label: 'Contracts', value: 'Contracts' },
    { label: 'WebLeads', value: 'WebLeads' },
    { label: 'Surveys', value: 'Surveys' },
    { label: 'Reviews', value: 'Reviews' },
    { label: 'GoogleReviews', value: 'GoogleReviews' },
    { label: 'CaseStudies', value: 'CaseStudies' }
  ];

  renderedCallback() {
        if (!this.objectiveId && this.objectiveOptions?.length) {
            this.objectiveId =
                this.defaultObjectiveId || this.objectiveOptions[0].value;
        }
    }

    handleObjectiveChange(e) {
        this.objectiveId = e.detail.value;
    }

    handleNameChange(e) {
        this.name = e.detail.value;
    }

    handleMetricChange(e) {
        this.metric = e.detail.value;
    }

    handleTargetChange(e) {
        this.target = e.detail.value;
    }

    handleSave() {
        if (!this.objectiveId || !this.name || !this.metric || !this.target) {
            this.dispatchEvent(
                new CustomEvent('error', {
                    detail: 'Fill all required fields.'
                })
            );
            return;
        }

        this.dispatchEvent(
            new CustomEvent('save', {
                detail: {
                    Objective__c: this.objectiveId,
                    Name: this.name,
                    Metric__c: this.metric,
                    Target_Value__c: Number(this.target)
                }
            })
        );
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }
}