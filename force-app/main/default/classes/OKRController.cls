public with sharing class OKRController {
    // Basic Objective methods
    @AuraEnabled(cacheable=true)
    public static List<Objective__c> getObjectives(Id ownerId, Integer year) {
        return [
            SELECT Id, Name, Description__c, Year__c, Category__c, TargetValue__c, Status__c
                FROM Objective__c 
                WHERE OwnerId = :ownerId 
                AND Year__c = :year 
                ORDER BY Order__c];
    }

    @AuraEnabled(cacheable=true)
    public static List<UserOption> getActiveUsers() {
    try {
        List<UserOption> out = new List<UserOption>();
        for (User u : [
            SELECT Id, Name
            FROM User
            WHERE IsActive = true
            ORDER BY Name
            LIMIT 200
        ]) {
            out.add(new UserOption((String)u.Id, u.Name));
        }
        return out;
    } catch (Exception e) {
        User me = [SELECT Id, Name FROM User WHERE Id = :UserInfo.getUserId()];
        return new List<UserOption>{ new UserOption((String)me.Id, me.Name) };
    }
}

public class UserOption {
    @AuraEnabled public String value;
    @AuraEnabled public String label;
    public UserOption(String value, String label) {
        this.value = value;
        this.label = label;
    }
}

    // Basic Key Result methods
    @AuraEnabled(cacheable=true)
    public static List<Key_Result__c> getKeyResults(Id objectiveId) {
        return [SELECT Id, Name, Current_Value__c, Target_Value__c 
                FROM Key_Result__c 
                WHERE Objective__c = :objectiveId 
                ORDER BY Order__c];
    }
    // Handle Objective and Key Result creation

    @AuraEnabled
    public static Key_Result__c saveKeyResult(Key_Result__c kr) {
        // Validate input
        if (kr == null) {
            throw new AuraHandledException('Key Result payload is required');
        }
        if (kr.Objective__c == null) {
            throw new AuraHandledException('Objective__c is required');
        }
        if (String.isBlank(kr.Name)) {
            throw new AuraHandledException('Name is required');
        }

        // Upsert KR in USER_MODE
        Database.UpsertResult krRes;
        try {
            krRes = Database.upsert(kr, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to save Key Result: ' + e.getMessage());
        }

        // Ensure we have an Id after upsert
        if (kr.Id == null) {
            if (krRes != null && krRes.isSuccess()) {
                kr.Id = krRes.getId();
            } else {
                throw new AuraHandledException('Failed to save Key Result (no Id returned).');
            }
        }

        // Persist target in Key_Result_Target__c (new object), not in Key_Result_Event_Link__c
        // IMPORTANT: Align Object_Type__c to org values.
        Map<String,String> metricToPicklist = new Map<String,String>{
            'Opportunities'  => 'Opportunity',
            'Calls'          => 'Call',
            'Contracts'      => 'Contract',
            'WebLeads'       => 'WebLead',
            'Surveys'        => 'Survey',
            'Reviews'        => 'Review',
            'GoogleReviews'  => 'GoogleReview',
            'CaseStudies'    => 'CaseStudy'
        };

        String rawMetric = kr.Metric__c;
        String normalizedMetric = normalizeType(rawMetric);
        String objectTypeForWrite = metricToPicklist.get(normalizedMetric);
        if (String.isBlank(objectTypeForWrite)) {
            objectTypeForWrite = rawMetric;
        }

        if (!String.isBlank(objectTypeForWrite) && kr.Target_Value__c != null) {
            Integer targetInt;
            try {
                targetInt = Integer.valueOf(kr.Target_Value__c);
            } catch (Exception e) {
                throw new AuraHandledException('Invalid target value: ' + String.valueOf(kr.Target_Value__c));
            }

            try {
                // Upsert a single Key_Result_Target__c per (KR, Object_Type__c)
                Key_Result_Target__c existingTarget = null;
                for (Key_Result_Target__c t : [
                    SELECT Id, Key_Result__c, Object_Type__c, Target__c
                    FROM Key_Result_Target__c
                    WHERE Key_Result__c = :kr.Id
                    AND Object_Type__c = :objectTypeForWrite
                    LIMIT 1
                ]) {
                    existingTarget = t;
                }

                if (existingTarget == null) {
                    Key_Result_Target__c tgt = new Key_Result_Target__c(
                        Key_Result__c = kr.Id,
                        Object_Type__c = objectTypeForWrite,
                        Target__c = targetInt
                    );
                    Database.insert(tgt, AccessLevel.USER_MODE);
                } else {
                    existingTarget.Target__c = targetInt;
                    Database.update(existingTarget, AccessLevel.USER_MODE);
                }
            } catch (Exception e) {
                throw new AuraHandledException('Failed to create/update Key Result Target: ' + e.getMessage());
            }
        }

        return kr;
    }

    // For Saving multiple targets for a Key Result
    
    // public class TargetInput {
    //      @AuraEnabled public String objectType;   
    //      @AuraEnabled public Integer target;      
    //      @AuraEnabled public String subType;      
    // }

    // @AuraEnabled
    // public static Key_Result__c saveKeyResultTargets(Id keyResultId, List<TargetInput> targets) {
    //     if (keyResultId == null) throw new AuraHandledException('keyResultId is required');
    //     if (targets == null || targets.isEmpty()) throw new AuraHandledException('targets list is required');


    //     Key_Result__c kr = [
    //         SELECT Id, Name, Metric__c, Target_Value__c
    //         FROM Key_Result__c
    //         WHERE Id = :keyResultId
    //     ];

    //     //Load existing targets
    //     Map<String, Key_Result_Target__c> existingTargets = new Map<String, Key_Result_Target__c>();
    //     for (Key_Result_Target__c t : [
    //         SELECT Id, Key_Result__c, Object_Type__c, Target__c
    //         FROM Key_Result_Target__c
    //         WHERE Key_Result__c = :keyResultId
    //     ]) {
    //         existingTargets.put(t.Object_Type__c, t);
    //     }
        
    //     // Upsert targets
    //     for (TargetInput ti : targets) {
    //         if (String.isBlank(ti.objectType) || ti.target == null) continue;
    //         if (existingTargets.containsKey(ti.objectType)) {
    //             Key_Result_Target__c et = existingTargets.get(ti.objectType);
    //             et.Target__c = ti.target;
    //             update et;
    //         } else {
    //             Key_Result_Target__c newTgt = new Key_Result_Target__c(
    //                 Key_Result__c = keyResultId,
    //                 Object_Type__c = ti.objectType,
    //                 Target__c = ti.target
    //             );
    //             insert newTgt;
    //         }
    //     }
    // }

    // Get counts of related records for a Key Result
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getRelatedRecordsCount(Id keyResultId) {
        Map<String, Integer> counts = new Map<String, Integer>();

    // Calls (Tasks with Type='Call')
    counts.put('Calls',
        [SELECT COUNT() FROM Task WHERE Type = 'Call' AND Key_Result__c = :keyResultId]
    );

    // Events
    counts.put('Events',
        [SELECT COUNT() FROM Event WHERE Key_Result__c = :keyResultId]
    );

    // Opportunities
    counts.put('Opportunities',
        [SELECT COUNT() FROM Opportunity WHERE Key_Result__c = :keyResultId]
    );

    // Contracts
    counts.put('Contracts',
        [SELECT COUNT() FROM Contract WHERE Key_Result__c = :keyResultId]
    );

    // Web Leads only
    counts.put('Leads',
        [SELECT COUNT() FROM Lead WHERE Key_Result__c = :keyResultId AND LeadSource = 'Web']
    );

    // Case Studies
    counts.put('CaseStudies',
        [SELECT COUNT() FROM Case_Study__c WHERE Key_Result__c = :keyResultId]
    );

    // Surveys
    counts.put('Surveys',
        [SELECT COUNT() FROM Survey__c WHERE Key_Result__c = :keyResultId]
    );

    // Reviews
    counts.put('Reviews',
        [SELECT COUNT() FROM Review__c WHERE Key_Result__c = :keyResultId]
    );

    // Google Reviews
    counts.put('Google Reviews',
        [SELECT COUNT() FROM Google_Review__c WHERE Key_Result__c = :keyResultId]
    );

    return counts;
    }

    // Save Objective with default order handling
    @AuraEnabled
    public static Objective__c saveObjective(Objective__c obj) {
    // Set default values if needed
    if (obj.Order__c == null) {
        AggregateResult maxOrder = [
            SELECT MAX(Order__c) 
            FROM Objective__c 
            WHERE OwnerId = :obj.OwnerId AND Year__c = :obj.Year__c
            ];
        obj.Order__c = (maxOrder.get('expr0') != null) ? (Decimal)maxOrder.get('expr0') + 1 : 1;
    }
    upsert obj;
    return obj;
    }

    // Fetch single Objective details
    @AuraEnabled(cacheable=true)
    public static Objective__c getObjective(Id objectiveId) {
    return [SELECT Id, Name, Description__c, Year__c, TargetValue__c 
            FROM Objective__c 
            WHERE Id = :objectiveId];
    }

    // Fetch related records for a Key Result
    // @AuraEnabled(cacheable=true)
    // public static List<RelatedRecordWrapper> getRelatedRecords(Id keyResultId) {
    //     List<Related_Record__c> records = [
    //         SELECT Id, Name__c, Record_Type__c, Date__c, Status__c, ContractType__c
    //         FROM Related_Record__c
    //         WHERE Key_Result__c = :keyResultId
    //         ORDER BY Date__c DESC
    //     ];

    //     List<RelatedRecordWrapper> wrappers = new List<RelatedRecordWrapper>();
    //     for (Related_Record__c record : records) {
    //         wrappers.add(new RelatedRecordWrapper(record));
    //     }
    //     return wrappers;
    // }

    @AuraEnabled
        public static Id createRelatedRecord(String objectApiName, Id keyResultId, Map<String, Object> fields) {
            if (String.isBlank(objectApiName)) {
                throw new AuraHandledException('objectApiName is required');
            }
            if (keyResultId == null) {
                throw new AuraHandledException('keyResultId is required');
            }

            sObject newRecord = Schema.getGlobalDescribe().get(objectApiName).newSObject();

            // Link to Key Result
            newRecord.put('Key_Result__c', keyResultId);

            // Extra fields
            if (fields != null) {
                for (String fieldName : fields.keySet()) {
                    newRecord.put(fieldName, fields.get(fieldName));
                }
            }

            insert newRecord;
            return (Id)newRecord.get('Id');
        }

    // Fetch Objectives with their Key Results
    @AuraEnabled(cacheable=true)
    public static List<ObjectiveWithKeyResults> getObjectivesWithKeyResults(Id ownerId, Integer year) {

    // 1) Objectives
    List<Objective__c> objectives = [
        SELECT Id, Name, Description__c, Year__c, Category__c, Status__c, Order__c, User__c
        FROM Objective__c
        WHERE User__c = :ownerId AND Year__c = :year
        ORDER BY Order__c
    ];
    if (objectives.isEmpty()) return new List<ObjectiveWithKeyResults>();

    Set<Id> objIds = new Set<Id>();
    for (Objective__c o : objectives) objIds.add(o.Id);

    // 2) Key Results -> wrappers
    Map<Id, List<KeyResultWrapper>> krMap = new Map<Id, List<KeyResultWrapper>>();
    Map<Id, KeyResultWrapper> krWrapById = new Map<Id, KeyResultWrapper>();
    Set<Id> krIds = new Set<Id>();

    for (Key_Result__c kr : [
        SELECT Id, Name, Objective__c, Metric__c, Target_Value__c, Order__c
        FROM Key_Result__c
        WHERE Objective__c IN :objIds
        ORDER BY Order__c
    ]) {
        krIds.add(kr.Id);

        if (!krMap.containsKey(kr.Objective__c)) {
            krMap.put(kr.Objective__c, new List<KeyResultWrapper>());
        }

        KeyResultWrapper w = new KeyResultWrapper(kr);
        krMap.get(kr.Objective__c).add(w);
        krWrapById.put(kr.Id, w);
    }

    // 3) Count related records per KR using your junction object
    if (!krIds.isEmpty()) {

    // Canonical keys and friendly labels
    Map<String, String> labelByCanonical = new Map<String, String>{
        'Opportunity'   => 'Opportunities',
        'Call'          => 'Calls',
        'Contract'      => 'Contracts',
        'WebLead'       => 'WebLeads',
        'Survey'        => 'Surveys',
        'Review'        => 'Reviews',
        'GoogleReview'  => 'GoogleReviews',
        'CaseStudy'     => 'CaseStudies'
    };

    // 3a) Progress rows
    List<Key_Result_Event_Link__c> allLinks = [
        SELECT Key_Result__c, Object_Type__c, RecordId__c
        FROM Key_Result_Event_Link__c
        WHERE Key_Result__c IN :krIds
    ];

    for (Key_Result_Event_Link__c link : allLinks) {
        KeyResultWrapper w = krWrapById.get(link.Key_Result__c);
        if (w == null ) continue;

        String canon = link.Object_Type__c; // already canonical in org
        if (String.isBlank(canon)) continue;

        if (!String.isBlank(link.RecordId__c)) {
            if (canon == 'Opportunity')      w.opportunityCount++;
            else if (canon == 'Call')        w.callCount++;
            else if (canon == 'Contract')    w.contractCount++;
            else if (canon == 'WebLead')     w.webLeadCount++;
            else if (canon == 'Survey')      w.surveyCount++;
            else if (canon == 'Review')      w.reviewCount++;
            else if (canon == 'GoogleReview')w.googleReviewCount++;
            else if (canon == 'CaseStudy')   w.caseStudyCount++;
        }
    }

    // 3b) Targets from Key_Result_Target__c
    for (Key_Result_Target__c tr : [
        SELECT Key_Result__c, Object_Type__c, Target__c
        FROM Key_Result_Target__c
        WHERE Key_Result__c IN :krIds
    ]) {
        KeyResultWrapper w = krWrapById.get(tr.Key_Result__c);
        if (w == null) continue;

        String canon = tr.Object_Type__c; // canonical labels in org
        Integer targetVal = (tr.Target__c == null) ? 0 : Integer.valueOf(tr.Target__c);

        if (canon == 'Opportunity')         w.opportunityTarget = targetVal;
        else if (canon == 'Call')           w.callTarget = targetVal;
        else if (canon == 'Contract')       w.contractTarget = targetVal;
        else if (canon == 'WebLead')        w.webLeadTarget = targetVal;
        else if (canon == 'Survey')         w.surveyTarget = targetVal;
        else if (canon == 'Review')         w.reviewTarget = targetVal;
        else if (canon == 'GoogleReview')   w.googleReviewTarget = targetVal;
        else if (canon == 'CaseStudy')      w.caseStudyTarget = targetVal;
    }

    // 3c) Build KR targets list for UI from canonical keys
    for (Id krId : krWrapById.keySet()) {
        KeyResultWrapper w = krWrapById.get(krId);
        if (w.targets == null) w.targets = new List<KeyResultTargetWrapper>();

        if (w.opportunityTarget > 0)
            w.targets.add(new KeyResultTargetWrapper(labelByCanonical.get('Opportunity'), w.opportunityCount, w.opportunityTarget));
        if (w.callTarget > 0)
            w.targets.add(new KeyResultTargetWrapper(labelByCanonical.get('Call'), w.callCount, w.callTarget));
        if (w.contractTarget > 0)
            w.targets.add(new KeyResultTargetWrapper(labelByCanonical.get('Contract'), w.contractCount, w.contractTarget));
        if (w.webLeadTarget > 0)
            w.targets.add(new KeyResultTargetWrapper(labelByCanonical.get('WebLead'), w.webLeadCount, w.webLeadTarget));
        if (w.surveyTarget > 0)
            w.targets.add(new KeyResultTargetWrapper(labelByCanonical.get('Survey'), w.surveyCount, w.surveyTarget));
        if (w.reviewTarget > 0)
            w.targets.add(new KeyResultTargetWrapper(labelByCanonical.get('Review'), w.reviewCount, w.reviewTarget));
        if (w.googleReviewTarget > 0)
            w.targets.add(new KeyResultTargetWrapper(labelByCanonical.get('GoogleReview'), w.googleReviewCount, w.googleReviewTarget));
        if (w.caseStudyTarget > 0)
            w.targets.add(new KeyResultTargetWrapper(labelByCanonical.get('CaseStudy'), w.caseStudyCount, w.caseStudyTarget));
    }

    // 3d) Compute completion based on KR.Metric__c mapped to canonical key
    Map<String, String> uiMetricToCanon = new Map<String, String>{
        'Opportunities' => 'Opportunity',
        'Calls'         => 'Call',
        'Contracts'     => 'Contract',
        'WebLeads'      => 'WebLead',
        'Surveys'       => 'Survey',
        'Reviews'       => 'Review',
        'GoogleReviews' => 'GoogleReview',
        'CaseStudies'   => 'CaseStudy',
        'Opportunity'   => 'Opportunity',
        'Call'          => 'Call',
        'Contract'      => 'Contract',
        'WebLead'       => 'WebLead',
        'Survey'        => 'Survey',
        'Review'        => 'Review',
        'GoogleReview'  => 'GoogleReview',
        'CaseStudy'     => 'CaseStudy'
    };

    for (Id krId : krWrapById.keySet()) {
        KeyResultWrapper w = krWrapById.get(krId);
        String canon = uiMetricToCanon.get(w.keyResult.Metric__c);

        Integer current = 0;
        Integer target = 0;

        if (canon == 'Opportunity')      { current = w.opportunityCount; target = w.opportunityTarget; }
        else if (canon == 'Call')        { current = w.callCount;        target = w.callTarget; }
        else if (canon == 'Contract')    { current = w.contractCount;    target = w.contractTarget; }
        else if (canon == 'WebLead')     { current = w.webLeadCount;     target = w.webLeadTarget; }
        else if (canon == 'Survey')      { current = w.surveyCount;      target = w.surveyTarget; }
        else if (canon == 'Review')      { current = w.reviewCount;      target = w.reviewTarget; }
        else if (canon == 'GoogleReview'){ current = w.googleReviewCount;target = w.googleReviewTarget; }
        else if (canon == 'CaseStudy')   { current = w.caseStudyCount;   target = w.caseStudyTarget; }

        w.computedCurrent = current;
        w.computedTarget = target;
        }
    }


    // 4. Objective totals + objective lines
    List<ObjectiveWithKeyResults> results = new List<ObjectiveWithKeyResults>();

    for (Objective__c obj : objectives) {
        List<KeyResultWrapper> wrapped = krMap.containsKey(obj.Id) ? krMap.get(obj.Id) : new List<KeyResultWrapper>();

        Integer totalKrs = wrapped.size();
        Integer completedKrs = 0;

        Integer oppCount = 0, callCount = 0, ctrCount = 0, leadCount = 0, survCount = 0, revCount = 0, googCount = 0, caseCount = 0;
        Integer oppT = 0, callT = 0, ctrT = 0, leadT = 0, survT = 0, revT = 0, googT = 0, caseT = 0;
        
        for (KeyResultWrapper w : wrapped) {
                // objective-level current totals by KR metric
                String m = normalizeType(w.keyResult.Metric__c);

                if      (m == 'Opportunities') oppCount  += w.computedCurrent;
                else if (m == 'Calls')         callCount += w.computedCurrent;
                else if (m == 'Contracts')     ctrCount  += w.computedCurrent;
                else if (m == 'WebLeads')      leadCount += w.computedCurrent;
                else if (m == 'Surveys')       survCount += w.computedCurrent;
                else if (m == 'Reviews')       revCount  += w.computedCurrent;
                else if (m == 'GoogleReviews') googCount += w.computedCurrent;
                else if (m == 'CaseStudies')   caseCount += w.computedCurrent;

                // objective-level target totals (sum all KR targets)
                oppT  += (w.opportunityTarget == null ? 0 : w.opportunityTarget);
                callT += (w.callTarget == null ? 0 : w.callTarget);
                ctrT  += (w.contractTarget == null ? 0 : w.contractTarget);
                leadT += (w.webLeadTarget == null ? 0 : w.webLeadTarget);
                survT += (w.surveyTarget == null ? 0 : w.surveyTarget);
                revT  += (w.reviewTarget == null ? 0 : w.reviewTarget);
                googT += (w.googleReviewTarget == null ? 0 : w.googleReviewTarget);
                caseT += (w.caseStudyTarget == null ? 0 : w.caseStudyTarget);

                // completed KRs
                if (w.computedTarget != null && w.computedTarget > 0 && w.computedCurrent >= w.computedTarget) {
                    completedKrs++;
                }
            }

        Decimal objPct = (totalKrs == 0) 
        ? 0 
        : (Decimal.valueOf(completedKrs) / Decimal.valueOf(totalKrs)) * 100;

        ObjectiveWithKeyResults owrap = new ObjectiveWithKeyResults(
            obj, wrapped,
            oppCount, callCount, ctrCount, leadCount, survCount, revCount, googCount, caseCount
        );
        owrap.KeyResultTotalCount = totalKrs;
        owrap.KeyResultCompletedCount = completedKrs;
        owrap.ObjectiveCompletionPercent = objPct;

        // Objective lines (for task screenshot)
        owrap.lines = new List<ObjectiveTargetLine>();
        if (leadT > 0) owrap.lines.add(new ObjectiveTargetLine('WebLeads',      leadCount, leadT));
        if (oppT  > 0) owrap.lines.add(new ObjectiveTargetLine('Opportunities', oppCount,  oppT));
        if (callT > 0) owrap.lines.add(new ObjectiveTargetLine('Calls',         callCount, callT));
        if (ctrT  > 0) owrap.lines.add(new ObjectiveTargetLine('Contracts',     ctrCount,  ctrT));
        if (survT > 0) owrap.lines.add(new ObjectiveTargetLine('Surveys',       survCount, survT));
        if (revT  > 0) owrap.lines.add(new ObjectiveTargetLine('Reviews',       revCount,  revT));
        if (googT > 0) owrap.lines.add(new ObjectiveTargetLine('GoogleReviews', googCount, googT));
        if (caseT > 0) owrap.lines.add(new ObjectiveTargetLine('CaseStudies',   caseCount, caseT));

        results.add(owrap);
    }

    return results;
}
    private static String normalizeType(String s) {
            if (String.isBlank(s)) return null;
            return s.replace(' ', '');
        }

    // =========================
    // WRAPPERS
    // =========================

   public class ObjectiveWithKeyResults {
    @AuraEnabled public Objective__c objective             { get; set; }
    @AuraEnabled public List<KeyResultWrapper> keyResults  { get; set; }
    @AuraEnabled public Integer OpportunityCount   { get; set; }
    @AuraEnabled public Integer CallCount          { get; set; }
    @AuraEnabled public Integer ContractCount      { get; set; }
    @AuraEnabled public Integer LeadCount          { get; set; }
    @AuraEnabled public Integer SurveyCount        { get; set; }
    @AuraEnabled public Integer ReviewCount        { get; set; }
    @AuraEnabled public Integer GoogleReviewCount  { get; set; }
    @AuraEnabled public Integer CaseStudyCount     { get; set; }
    @AuraEnabled public Integer KeyResultTotalCount { get; set; }
    @AuraEnabled public Integer KeyResultCompletedCount { get; set; }
    @AuraEnabled public Decimal ObjectiveCompletionPercent { get; set; }
    @AuraEnabled public List<ObjectiveTargetLine> lines { get; set; }

    public ObjectiveWithKeyResults() {}

        public ObjectiveWithKeyResults(
            Objective__c obj,
            List<KeyResultWrapper> krs,
            Integer oppCount,
            Integer callCount,
            Integer contractCount,
            Integer leadCount,
            Integer surveyCount,
            Integer reviewCount,
            Integer googleReviewCount,
            Integer caseStudyCount
        ) {
            this.objective          = obj;
            this.keyResults         = krs;
            this.OpportunityCount   = oppCount;
            this.CallCount          = callCount;
            this.ContractCount      = contractCount;
            this.LeadCount          = leadCount;
            this.SurveyCount        = surveyCount;
            this.ReviewCount        = reviewCount;
            this.GoogleReviewCount  = googleReviewCount;
            this.CaseStudyCount     = caseStudyCount;
        }
    }

    public class ObjectiveTargetLine {
        @AuraEnabled public String objectType;
        @AuraEnabled public Integer current;
        @AuraEnabled public Integer target;

        public ObjectiveTargetLine(String t, Integer c, Integer tg) {
            objectType = t;
            current = c;
            target = tg;
        }
    }

    public class KeyResultTargetWrapper {
            @AuraEnabled public String objectType;
            @AuraEnabled public Integer target;
            @AuraEnabled public Integer current;

            public KeyResultTargetWrapper(String objectType, Integer current, Integer target) {
                this.objectType = objectType;
                this.target = target;
                this.current = current;
            }
        }

        // Wrapper for Related Record
    // public class RelatedRecordWrapper {
    //     @AuraEnabled public String id;
    //     @AuraEnabled public String recordType;
    //     @AuraEnabled public String name;
    //     @AuraEnabled public Date recordDate;
    //     @AuraEnabled public String status;
    //     @AuraEnabled public String recordId;

    //     public RelatedRecordWrapper(Related_Record__c record) {
    //         this.id = record.Id;
    //         this.recordType = record.Record_Type__c;
    //         this.name = record.Name__c != null ? record.Name__c : record.Id; // safer
    //         this.recordDate = record.Date__c;
    //         this.status = record.Status__c;
    //         this.recordId = record.Id; // fixed
    //     }
    // }

    

    // Wrapper for Objective with counts
    // public class ObjectiveWrapper {
    //     @AuraEnabled public Objective__c objective { get; set; }
    //     @AuraEnabled public Integer OpportunityCount { get; set; }
    //     @AuraEnabled public Integer CallCount { get; set; }
    //     @AuraEnabled public Integer ContractCount { get; set; }
    //     @AuraEnabled public Integer LeadCount { get; set; }
    //     @AuraEnabled public Integer SurveyCount { get; set; }
    //     @AuraEnabled public Integer ReviewCount { get; set; }
    //     @AuraEnabled public Integer GoogleReviewCount { get; set; }
    //     @AuraEnabled public Integer CaseStudyCount { get; set; }

    // public ObjectiveWrapper(
    //     Objective__c o, 
    //     Integer opps, 
    //     Integer calls, 
    //     Integer contracts,
    //     Integer leads,
    //     Integer surveys,
    //     Integer reviews,
    //     Integer googleReviews,
    //     Integer caseStudies
    //     ) {
    //     this.objective = o;
    //     this.OpportunityCount = opps;
    //     this.CallCount = calls;
    //     this.ContractCount = contracts;
    //     this.LeadCount = leads;
    //     this.SurveyCount = surveys;
    //     this.ReviewCount = reviews;
    //     this.GoogleReviewCount = googleReviews;
    //     this.CaseStudyCount = caseStudies;
    //     }
    // }

    // Wrapper for Key Result with completion percentage
    public class KeyResultWrapper {
        @AuraEnabled public Key_Result__c keyResult { get; set; }

        @AuraEnabled public Integer opportunityCount { get; set; }
        @AuraEnabled public Integer callCount { get; set; }
        @AuraEnabled public Integer contractCount { get; set; }
        @AuraEnabled public Integer webLeadCount { get; set; }
        @AuraEnabled public Integer surveyCount { get; set; }
        @AuraEnabled public Integer reviewCount { get; set; }
        @AuraEnabled public Integer googleReviewCount { get; set; }
        @AuraEnabled public Integer caseStudyCount { get; set; }

        @AuraEnabled public Integer opportunityTarget { get; set; }
        @AuraEnabled public Integer callTarget { get; set; }
        @AuraEnabled public Integer contractTarget { get; set; }
        @AuraEnabled public Integer webLeadTarget { get; set; }
        @AuraEnabled public Integer surveyTarget { get; set; }
        @AuraEnabled public Integer reviewTarget { get; set; }
        @AuraEnabled public Integer googleReviewTarget { get; set; }
        @AuraEnabled public Integer caseStudyTarget { get; set; }

        @AuraEnabled public Integer computedCurrent { get; set; }
        @AuraEnabled public Integer computedTarget { get; set; }

        @AuraEnabled public List<KeyResultTargetWrapper> targets { get; set; }

        public KeyResultWrapper(Key_Result__c kr) {
            keyResult = kr;

            opportunityCount = 0;
            callCount = 0;
            contractCount = 0;
            webLeadCount = 0;
            surveyCount = 0;
            reviewCount = 0;
            googleReviewCount = 0;
            caseStudyCount = 0;

            opportunityTarget = 0;
            callTarget = 0;
            contractTarget = 0;
            webLeadTarget = 0;
            surveyTarget = 0;
            reviewTarget = 0;
            googleReviewTarget = 0;
            caseStudyTarget = 0;

            computedCurrent = 0;
            computedTarget = 0;

            targets = new List<KeyResultTargetWrapper>();
        }
    }
}
