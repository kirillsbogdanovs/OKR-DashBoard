import { LightningElement, api } from 'lwc';

export default class ObjectiveCard extends LightningElement {
    @api objectiveWrapper; // ✅ accept wrapper

    // Convenience getter to access Objective__c directly
    get objective() {
        return this.objectiveWrapper?.objective || {};
    }

    // Convenience getter to access Key Results directly
    get keyResults() {
        return this.objectiveWrapper?.keyResults || [];
    }

    get completionPercent() {
        return this.objectiveWrapper?.ObjectiveCompletionPercent || 0;
    }

    get opportunityCount() {
        return this.objectiveWrapper?.OpportunityCount || 0;
    }

    get callCount() {
        return this.objectiveWrapper?.CallCount || 0;
    }

    get contractCount() {
        return this.objectiveWrapper?.ContractCount || 0;
    }

    get leadCount() {
    return this.objectiveWrapper?.LeadCount || 0;
    }

    get surveyCount() {
        return this.objectiveWrapper?.SurveyCount || 0;
    }

    get reviewCount() {
        return this.objectiveWrapper?.ReviewCount || 0;
    }

    get googleReviewCount() {
        return this.objectiveWrapper?.GoogleReviewCount || 0;
    }
    
    get caseStudyCount() {
        return this.objectiveWrapper?.CaseStudyCount || 0;
    }

    get keyResultTotalCount() {
        return this.objectiveWrapper?.KeyResultTotalCount || 0;
    }

    get keyResultCompletedCount() {
        return this.objectiveWrapper?.KeyResultCompletedCount || 0;
    }

    get objectiveCompletionPercent() {
        return this.objectiveWrapper?.ObjectiveCompletionPercent || 0;
    }

    get hasLines() {
        return (this.objectiveWrapper?.lines || []).length > 0;
    }

    handleClick() {
        this.dispatchEvent(new CustomEvent('select', {
            detail: this.objective.Id
        }));
    }
    handleAddKeyResult() {
        const objectiveId = this.objectiveWrapper?.objective?.Id;
        this.dispatchEvent(new CustomEvent('addkeyresult', {
            detail: { objectiveId },
            bubbles: true,
            composed: true
        }));
    }
    handleSelect() {
    this.dispatchEvent(
        new CustomEvent('select', {
        detail: { objectiveId: this.objective.Id },
        bubbles: true,
        composed: true
    }));
}


}
