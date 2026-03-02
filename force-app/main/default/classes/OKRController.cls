// public Makes the class accessible to other Apex code and to LWC/Aura (when methods are @AuraEnabled).
public with sharing class OKRController {

    // Returns a list of Objective__c records for a user and year.
    @AuraEnabled(cacheable=true)
    public static List<Objective__c> getObjectives(Id ownerId, Integer year) {
        return [
            SELECT Id, Name, Description__c, Year__c, Category__c, TargetValue__c
                FROM Objective__c 
                WHERE OwnerId = :ownerId 
                AND Year__c = :year 
                ORDER BY Order__c];
    }

    // Returns a list of User picklist options for the UI.
    @AuraEnabled(cacheable=true)
    public static List<UserOption> getActiveUsers() {
    try {
        List<UserOption> out = new List<UserOption>();
        for (User u : [
            SELECT Id, Name
            FROM User
            WHERE IsActive = true
            ORDER BY Name
        ]) {
            out.add(new UserOption((String)u.Id, u.Name));
        }
        return out;
    } catch (Exception e) {
        User me = [SELECT Id, Name FROM User WHERE Id = :UserInfo.getUserId()];
        return new List<UserOption>{ new UserOption((String)me.Id, me.Name) };
    }
}

// A simple data transfer object that serializes nicely to JSON for LWC
public class UserOption {
    @AuraEnabled public String value;
    @AuraEnabled public String label;
    public UserOption(String value, String label) {
        this.value = value;
        this.label = label;
    }
}

    // Returns all Key_Result__c for an Objective.
    @AuraEnabled(cacheable=true)
    public static List<Key_Result__c> getKeyResults(Id objectiveId) {
        return [SELECT Id, Name, Current_Value__c, Target_Value__c, Status__c 
                FROM Key_Result__c 
                WHERE Objective__c = :objectiveId 
                ORDER BY Order__c];
    }

    // Save Key Result and ensure a related Key Result Target row exists or updated for the metric
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

        // Ensure we have an Id after upsert, because sometimes in certain patterns the passed object may not have Id
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
            'CaseStudies'    => 'CaseStudy',
            'Events'        => 'Event'
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
                // Enforce uniqueness 1 target per ObjectType of KR
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

    // ==============================
    // Multiple targets per Key Result
    // subtype is only for WebLead
    // ==============================

    // Normalizer for string object types inputs, to avoid issues with extra spaces or nulls.
    private static String norm(String s) {
        return String.isBlank(s) ? '' : s.trim();
    }


    // Returns list of targets from Key_Result_Target__c for UI editing.
    @AuraEnabled(cacheable=true)
    public static List<TargetInput> getKeyResultTargets(Id keyResultId) {
        List<TargetInput> out = new List<TargetInput>();

        for (Key_Result_Target__c t : [
            SELECT Object_Type__c, Target__c
            FROM Key_Result_Target__c
            WHERE Key_Result__c = :keyResultId
            ORDER BY Object_Type__c
        ]) {
            TargetInput ti = new TargetInput();
            ti.objectType = t.Object_Type__c;
            ti.target = (t.Target__c == null ? 0 : Integer.valueOf(t.Target__c));
            out.add(ti);
        }
        return out;
    }

    // Saves targets for a Key Result, expects a JSON string of list of {objectType, target} objects.
    @AuraEnabled
    public static void saveKeyResultTargets(Id keyResultId, String targetsJson) {
    
    if (keyResultId == null) {
        throw new AuraHandledException('keyResultId is required');
    }
    if (String.isBlank(targetsJson)) {
        throw new AuraHandledException('targetsJson is required');
    }

    // Delete existing targets first
    List<Key_Result_Target__c> existing = [
        SELECT Id FROM Key_Result_Target__c 
        WHERE Key_Result__c = :keyResultId
    ];
    if (!existing.isEmpty()) {
        delete existing;
    }

    // Parse JSON
    List<Object> parsed = (List<Object>) JSON.deserializeUntyped(targetsJson);
    
    List<Key_Result_Target__c> toInsert = new List<Key_Result_Target__c>();
    
    for (Object item : parsed) {
        Map<String, Object> row = (Map<String, Object>) item;
        String objectType = (String) row.get('objectType');
        Integer targetVal = ((Decimal) row.get('target')).intValue();
        
        if (String.isBlank(objectType) || targetVal == null) continue;
        
        toInsert.add(new Key_Result_Target__c(
            Key_Result__c = keyResultId,
            Object_Type__c = objectType,
            Target__c = targetVal
        ));
    }
    
    if (!toInsert.isEmpty()) {
        insert toInsert;
    }
}

    // Get counts of related records for a Key Result, returns a Map<String, Integer> of counts for different objects.
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

    // Dynamic record creation method
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

        @AuraEnabled
        public static void createEventLink(Id keyResultId, Id recordId, String objectType){
            insert new Key_Result_Event_Link__c(
                Key_Result__c = keyResultId,
                RecordId__c = String.valueOf(recordId),
                Object_Type__c = objectType
             );
        }

    // Fetch Objectives with their Key Results, builds a hierarchical DTO
    @AuraEnabled(cacheable=true)
    public static List<ObjectiveWithKeyResults> getObjectivesWithKeyResults(Id ownerId, Integer year) {

    // 1) Objectives
    List<Objective__c> objectives = [
        SELECT Id, Name, Description__c, Year__c, Category__c, Order__c, User__c
        FROM Objective__c
        WHERE User__c = :ownerId AND Year__c = :year
        ORDER BY Order__c
    ];
    if (objectives.isEmpty()) return new List<ObjectiveWithKeyResults>();

    Set<Id> objIds = new Set<Id>();
    for (Objective__c o : objectives) objIds.add(o.Id);

    // 2) Sets objectives to their KRs, KRs Id to wrapper
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
    
    // 3a) Progress rows
    List<Key_Result_Event_Link__c> allLinks = [
        SELECT Key_Result__c, Object_Type__c, RecordId__c
        FROM Key_Result_Event_Link__c
        WHERE Key_Result__c IN :krIds
    ];
    
    Set<Id> leadIds = new Set<Id>();
        for (Key_Result_Event_Link__c link : allLinks) {
            if (link.Object_Type__c == 'WebLead' && !String.isBlank(link.RecordId__c)) {
                leadIds.add((Id)link.RecordId__c);
            }
        }
    
    Map<Id, String> leadSourceById = new Map<Id, String>();
        if (!leadIds.isEmpty()) {
            for (Lead ld : [
                SELECT Id, LeadSource
                FROM Lead
                WHERE Id IN :leadIds
            ]) {
                leadSourceById.put(ld.Id, ld.LeadSource);
            }
        }

    Map<Id, Map<String, Integer>> webLeadCountsByKr = new Map<Id, Map<String, Integer>>();

    // Canonical keys and friendly labels
    Map<String, String> labelByCanonical = new Map<String, String>{
        'Opportunity'   => 'Opportunities',
        'Call'          => 'Calls',
        'Contract'      => 'Contracts',
        'WebLead'       => 'WebLeads',
        'Survey'        => 'Surveys',
        'Review'        => 'Reviews',
        'GoogleReview'  => 'GoogleReviews',
        'CaseStudy'     => 'CaseStudies',
        'Event'         => 'Events'
    };

    for (Key_Result_Event_Link__c link : allLinks) {
        KeyResultWrapper w = krWrapById.get(link.Key_Result__c);
        if (w == null ) continue;

        String canon = link.Object_Type__c; // already canonical in org
        if (String.isBlank(canon)) continue;

        if (!String.isBlank(link.RecordId__c)) {

            if (canon == 'WebLead') {
            w.webLeadCount++;

            String src = leadSourceById.get((Id)link.RecordId__c);
            if (String.isBlank(src)) src = 'Unknown';

            if (!webLeadCountsByKr.containsKey(link.Key_Result__c)) {
                webLeadCountsByKr.put(link.Key_Result__c, new Map<String, Integer>());
            }
            Map<String, Integer> bySrc = webLeadCountsByKr.get(link.Key_Result__c);
            bySrc.put(src, (bySrc.containsKey(src) ? bySrc.get(src) : 0) + 1);

            continue; // IMPORTANT so it doesn't fall through other counters
        }

            if (canon == 'Opportunity')      w.opportunityCount++;
            else if (canon == 'Call')        w.callCount++;
            else if (canon == 'Contract')    w.contractCount++;
            else if (canon == 'Survey')      w.surveyCount++;
            else if (canon == 'Review')      w.reviewCount++;
            else if (canon == 'GoogleReview')w.googleReviewCount++;
            else if (canon == 'CaseStudy')   w.caseStudyCount++;
            else if (canon == 'Event')       w.eventCount++;
        }
    }

    // 3b) Load targets from Key_Result_Target__c

    for (Key_Result_Target__c tr : [
        SELECT Key_Result__c, Object_Type__c, Target__c
        FROM Key_Result_Target__c
        WHERE Key_Result__c IN :krIds
    ]) {
    
    KeyResultWrapper w = krWrapById.get(tr.Key_Result__c);
    if (w == null) {
        continue;
    }

    String canon = tr.Object_Type__c;
    Integer targetVal = (tr.Target__c == null) ? 0 : Integer.valueOf(tr.Target__c);

    System.debug('🔍 Processing: canon=' + canon + ', targetVal=' + targetVal);

    if (canon == 'Opportunity') {
        w.opportunityTarget = targetVal;
        //System.debug('✅ Set opportunityTarget = ' + targetVal);
    }
    else if (canon == 'Call') {
        w.callTarget = targetVal;
        //System.debug('✅ Set callTarget = ' + targetVal);
    }
    else if (canon == 'Contract') {
        w.contractTarget = targetVal;
        //System.debug('✅ Set contractTarget = ' + targetVal);
    }
    else if (canon == 'WebLead') {
        w.webLeadTarget = targetVal;
        //System.debug('✅ Set webLeadTarget = ' + targetVal);
    }
    else if (canon == 'Survey') {
        w.surveyTarget = targetVal;
        //System.debug('✅ Set surveyTarget = ' + targetVal);
    }
    else if (canon == 'Review') {
        w.reviewTarget = targetVal;
        //System.debug('✅ Set reviewTarget = ' + targetVal);
    }
    else if (canon == 'GoogleReview') {
        w.googleReviewTarget = targetVal;
        //System.debug('✅ Set googleReviewTarget = ' + targetVal);
    }
    else if (canon == 'Event') {
        w.eventTarget = targetVal;
    }
    else if (canon == 'CaseStudy') {
        w.caseStudyTarget = targetVal;
        //System.debug('✅ Set caseStudyTarget = ' + targetVal);
    }
    else {
        System.debug(' UNKNOWN Object_Type__c: ' + canon);
    }
}

    // 3c) Build KR targets list for UI from canonical keys
    for (Id krId : krWrapById.keySet()) {
        KeyResultWrapper w = krWrapById.get(krId);
        if (w.targets == null) w.targets = new List<KeyResultTargetWrapper>();

        if (w.opportunityTarget > 0) {
        w.targets.add(new KeyResultTargetWrapper('Opportunities', w.opportunityCount, w.opportunityTarget));
    }
    if (w.callTarget > 0) {
        w.targets.add(new KeyResultTargetWrapper('Calls', w.callCount, w.callTarget));
    }
    if (w.contractTarget > 0) {
        w.targets.add(new KeyResultTargetWrapper('Contracts', w.contractCount, w.contractTarget));
    }
    if (w.surveyTarget > 0) {
        w.targets.add(new KeyResultTargetWrapper('Surveys', w.surveyCount, w.surveyTarget));
    }
    if (w.reviewTarget > 0) {
        w.targets.add(new KeyResultTargetWrapper('Reviews', w.reviewCount, w.reviewTarget));
    }
    if (w.googleReviewTarget > 0) {
        w.targets.add(new KeyResultTargetWrapper('GoogleReviews', w.googleReviewCount, w.googleReviewTarget));
    }
    if (w.caseStudyTarget > 0) {
        w.targets.add(new KeyResultTargetWrapper('CaseStudies', w.caseStudyCount, w.caseStudyTarget));
    }
    if (w.eventTarget > 0) {
        w.targets.add(new KeyResultTargetWrapper('Events', w.eventCount, w.eventTarget));
    }
    if (w.webLeadTarget > 0) {
        w.targets.add(new KeyResultTargetWrapper('WebLeads', w.webLeadCount, w.webLeadTarget));
    } else if (w.webLeadCount > 0) {
        // Show current even if no target set
        w.targets.add(new KeyResultTargetWrapper('WebLeads', w.webLeadCount, 0));
    }

        // Breakdown lines (current only, auto from LeadSource)
        Map<String, Integer> bySrc = webLeadCountsByKr.get(krId);
        if (bySrc != null) {
            for (String src : bySrc.keySet()) {
                w.targets.add(new KeyResultTargetWrapper(src + ' Leads', bySrc.get(src), 0));
            }
        }
    }


    // 3d) Compute computedCurrent and computedTarget
    Map<String, String> uiMetricToCanon = new Map<String, String>{
        'Opportunities' => 'Opportunity',
        'Calls'         => 'Call',
        'Contracts'     => 'Contract',
        'WebLeads'      => 'WebLead',
        'Surveys'       => 'Survey',
        'Reviews'       => 'Review',
        'GoogleReviews' => 'GoogleReview',
        'CaseStudies'   => 'CaseStudy',
        'Events'        => 'Event',
        'Opportunity'   => 'Opportunity',
        'Call'          => 'Call',
        'Contract'      => 'Contract',
        'WebLead'       => 'WebLead',
        'Survey'        => 'Survey',
        'Review'        => 'Review',
        'GoogleReview'  => 'GoogleReview',
        'CaseStudy'     => 'CaseStudy',
        'Event'         => 'Event'
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
        else if (canon == 'Event')       { current = w.eventCount;       target = w.eventTarget; }

        w.computedCurrent = current;
        w.computedTarget = target;
        }
    }


    // 4. Objective-level totals and completion
    List<ObjectiveWithKeyResults> results = new List<ObjectiveWithKeyResults>();

    for (Objective__c obj : objectives) {
        List<KeyResultWrapper> wrapped = krMap.containsKey(obj.Id) ? krMap.get(obj.Id) : new List<KeyResultWrapper>();

        Integer totalKrs = wrapped.size();
        Integer completedKrs = 0;

        Integer oppCount = 0, callCount = 0, ctrCount = 0, leadCount = 0, survCount = 0, revCount = 0, googCount = 0, caseCount = 0, eventCount = 0;
        Integer oppT = 0, callT = 0, ctrT = 0, leadT = 0, survT = 0, revT = 0, googT = 0, caseT = 0, eventT = 0;
        
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
                else if (m == 'Events')         w.eventCount += w.computedCurrent;

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
            oppCount, callCount, ctrCount, leadCount, survCount, revCount, googCount, caseCount, eventCount
        );
        owrap.KeyResultTotalCount = totalKrs;
        owrap.KeyResultCompletedCount = completedKrs;
        owrap.ObjectiveCompletionPercent = objPct;

        // Objective lines (one line in objective totals)
        owrap.lines = new List<ObjectiveTargetLine>();
        if (leadT > 0) owrap.lines.add(new ObjectiveTargetLine('WebLeads',      leadCount, leadT));
        if (oppT  > 0) owrap.lines.add(new ObjectiveTargetLine('Opportunities', oppCount,  oppT));
        if (callT > 0) owrap.lines.add(new ObjectiveTargetLine('Calls',         callCount, callT));
        if (ctrT  > 0) owrap.lines.add(new ObjectiveTargetLine('Contracts',     ctrCount,  ctrT));
        if (survT > 0) owrap.lines.add(new ObjectiveTargetLine('Surveys',       survCount, survT));
        if (revT  > 0) owrap.lines.add(new ObjectiveTargetLine('Reviews',       revCount,  revT));
        if (googT > 0) owrap.lines.add(new ObjectiveTargetLine('GoogleReviews', googCount, googT));
        if (caseT > 0) owrap.lines.add(new ObjectiveTargetLine('CaseStudies',   caseCount, caseT));
        if (eventT > 0) owrap.lines.add(new ObjectiveTargetLine('Events',         eventCount, eventT));

        results.add(owrap);
    }

    return results;
}
    // Used to make strings comparable when UI might send “Google Reviews” vs “GoogleReviews”
    private static String normalizeType(String s) {
            if (String.isBlank(s)) return null;
            return s.replace(' ', '');
        }

    // =========================
    // WRAPPERS
    // =========================

    // Wrapper for Objective with its Key Results and related counts, used for LWC display.
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
    @AuraEnabled public Integer EventCount         { get; set; }
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
            Integer caseStudyCount,
            Integer eventCount
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
            this.EventCount         = eventCount;
        }
    }

    // Simple wrapper for objective-level target lines (e.g. WebLeads: 30/50)
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

    // Wrapper for Key Result targets, used for UI editing of multiple targets.
    public class KeyResultTargetWrapper {
            @AuraEnabled public String objectType;
            @AuraEnabled public Integer target;
            @AuraEnabled public Integer current;
            @AuraEnabled public String rowKey;

            public KeyResultTargetWrapper(String objectType, Integer current, Integer target) {
                this.objectType = objectType;
                this.current = current;
                this.target = target;
            }
        }

        // Used for editing targets when creating new Key Result
        public class TargetInput {
            @AuraEnabled public String objectType;   // e.g. 'Opportunity', 'WebLead'
            @AuraEnabled public Integer target;      // e.g. 50    
        }

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
        @AuraEnabled public Integer eventCount { get; set; }

        @AuraEnabled public Integer opportunityTarget { get; set; }
        @AuraEnabled public Integer callTarget { get; set; }
        @AuraEnabled public Integer contractTarget { get; set; }
        @AuraEnabled public Integer webLeadTarget { get; set; }
        @AuraEnabled public Integer surveyTarget { get; set; }
        @AuraEnabled public Integer reviewTarget { get; set; }
        @AuraEnabled public Integer googleReviewTarget { get; set; }
        @AuraEnabled public Integer caseStudyTarget { get; set; }
        @AuraEnabled public Integer eventTarget { get; set; }

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
            eventCount = 0;

            opportunityTarget = 0;
            callTarget = 0;
            contractTarget = 0;
            webLeadTarget = 0;
            surveyTarget = 0;
            reviewTarget = 0;
            googleReviewTarget = 0;
            caseStudyTarget = 0;
            eventTarget = 0;

            computedCurrent = 0;
            computedTarget = 0;

            targets = new List<KeyResultTargetWrapper>();
        }
    }
}
