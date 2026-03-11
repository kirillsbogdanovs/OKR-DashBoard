@isTest
public class OKRControllerTest{

    @TestSetup
    static void setupData(){
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        insert new Objective__c(
            Name = 'Setup Objective',
            Year__c = 2024,
            User__c = testUser.Id,
            OwnerId = testUser.Id
        );
    }

    @isTest 
    static void testGetUsers(){
        Test.startTest();
        List<OKRController.UserOption> users = OKRController.getActiveUsers();
        Test.stopTest();

        System.assertNotEquals(null, users, 'Users should not be null');
    }

    @isTest
    static void testGetObjectives(){
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        Test.startTest();
        List<Objective__c> objs = OKRController.getObjectives(testUser.Id, 2024);
        Test.stopTest();

        System.assertNotEquals(null, objs, 'Objectives should not be null');
        System.assertEquals(1, objs.size(), 'There should be one objective');
    }

    @isTest
    static void testGetObjective(){
        Objective__c objs = [SELECT Id FROM Objective__c WHERE Name = 'Setup Objective' LIMIT 1];

        Test.startTest();
        Objective__c obj = OKRController.getObjective(objs.Id);
        Test.stopTest();

        System.assertNotEquals(null, obj, 'Objective should not be null');
        System.assertEquals('Setup Objective', obj.Name, 'Objective name should match');
    }

    @isTest
    static void testSaveObjective(){

        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        Objective__c obj = new Objective__c(
            Name = 'Test Objective',
            Year__c = 2024,
            User__c = testUser.Id,
            OwnerId = testUser.Id,
            Category__c = 'Sales'
        );
        Test.startTest();
        Objective__c result = OKRController.saveObjective(obj);
        Test.stopTest();

        List<Objective__c> saved = [SELECT Id, Name FROM Objective__c WHERE Name = 'Test Objective'];
        System.assertEquals(1, saved.size(), 'Objective should be saved');
        System.assertEquals('Test Objective', saved[0].Name, 'Name should match');
    }

    @isTest
    static void testSaveKeyResult(){

        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Objective__c obj = [SELECT Id FROM Objective__c WHERE Name = 'Setup Objective' LIMIT 1];

        Key_Result__c kr = new Key_Result__c(
            Name = 'Test Key Result',
            Objective__c = obj.Id,
            Metric__c = 'Surveys',
            Target_Value__c = 10
        );

        Test.startTest();
        Key_Result__c result = OKRController.saveKeyResult(kr);
        Test.stopTest();

        List<Key_Result_Target__c> targets = [SELECT Id FROM Key_Result_Target__c WHERE Key_Result__c = :result.Id];
        System.assertEquals(1, targets.size(), 'Target should be created');
    }

    @isTest
    static void testGetObjectivesWithKeyResults(){
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Objective__c obj = [SELECT Id FROM Objective__c WHERE Name = 'Setup Objective' LIMIT 1];

        Key_Result__c kr = new Key_Result__c(
            Name = 'Test Key Result for GetObjWithKr',
            Objective__c = obj.Id,
            Metric__c = 'Surveys',
            Target_Value__c = 10
        );
        insert kr;

        Test.startTest();
        List<OKRController.ObjectiveWithKeyResults> results = OKRController.getObjectivesWithKeyResults(testUser.Id, 2024);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Objectives should not be null');
        System.assertEquals(1, results.size(), 'There should be one objective');
    }

    @isTest
    static void testGetKeyResults(){
        Objective__c obj = [SELECT Id FROM Objective__c WHERE Name = 'Setup Objective' LIMIT 1];

        Key_Result__c kr = new Key_Result__c(
            Name = 'Test Key Result for GetKeyResults',
            Objective__c = obj.Id,
            Metric__c = 'Surveys',
            Target_Value__c = 10
        );
        insert kr;
        
        Test.startTest();
        List<Key_Result__c> results = OKRController.getKeyResults(obj.Id);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Key Results should not be null');
        System.assertEquals(1, results.size(), 'There should be one key result');
    }

    @isTest
    static void testGetKeyResultTargets(){
        Objective__c obj = [SELECT Id FROM Objective__c WHERE Name = 'Setup Objective' LIMIT 1];
        Key_Result__c kr = new Key_Result__c(
            Name = 'Test Key Result for GetKeyResults',
            Objective__c = obj.Id
        );
        insert kr;

        Key_Result_Target__c target = new Key_Result_Target__c(
            Key_Result__c = kr.Id,
            Object_Type__c = 'Survey',
            Target__c = 15
        );
        insert target;
        
        Test.startTest();
        List<OKRController.TargetInput> results = OKRController.getKeyResultTargets(kr.Id);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Key Result Targets should not be null');
        System.assertEquals(1, results.size(), 'There should be one key result target');
    }

    @isTest
    static void testSaveKeyResultTargets(){

        Objective__c obj = [SELECT Id FROM Objective__c WHERE Name = 'Setup Objective' LIMIT 1];

        Key_Result__c kr = new Key_Result__c(
            Name = 'Test Key Result for SaveKeyResultTargets',
            Objective__c = obj.Id,
            Metric__c = 'Surveys',
            Target_Value__c = 10
        );
        insert kr;
        
        String targets = '[{"objectType":"Opportunity","target":12},{"objectType":"Survey","target":15}]';

        Test.startTest();
        OKRController.saveKeyResultTargets(kr.Id, targets);
        Test.stopTest();

        List<Key_Result_Target__c> savedTargets = [SELECT Id FROM Key_Result_Target__c WHERE Key_Result__c = :kr.Id];
        System.assertEquals(2, savedTargets.size(), 'Two targets should be saved');
    }

    @isTest
    static void testCreateEventLink(){
        
        Objective__c obj = [SELECT Id FROM Objective__c WHERE Name = 'Setup Objective' LIMIT 1];

        Key_Result__c kr = new Key_Result__c(
            Name = 'Test Key Result for CreateEventLink',
            Objective__c = obj.Id
        );
        insert kr;

        Survey__c survey = new Survey__c(
            Name = 'Test Survey'
        );
        insert survey;

        Test.startTest();
        OKRController.createEventLink(kr.Id, survey.Id, 'Survey');
        Test.stopTest();

        List<Key_Result_Event_Link__c> links = [SELECT Id FROM Key_Result_Event_Link__c WHERE Key_Result__c = :kr.Id AND RecordId__c = :String.valueOf(survey.Id)];
        System.assertEquals(1, links.size(), 'One link should be created');
    }

    @isTest
    static void testCreateRelatedRecord(){
        Objective__c obj = [SELECT Id FROM Objective__c WHERE Name = 'Setup Objective' LIMIT 1];
        Key_Result__c kr = new Key_Result__c(
            Name = 'Test Key Result for CreateRelatedRecord',
            Objective__c = obj.Id
        );
        insert kr;

        Map<String, Object> fields = new Map<String, Object>{
            'Name' => 'Test Survey'
        };

        Test.startTest();
        OKRController.createRelatedRecord('Survey__c',kr.Id, fields);
        Test.stopTest();

        List<Survey__c> surveys = [SELECT Id FROM Survey__c WHERE Name = 'Test Survey'];
        System.assertEquals(1, surveys.size(), 'One survey should be created');
    }

    @isTest
    static void testSendKRData(){
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Objective__c obj = [SELECT Id FROM Objective__c WHERE Name = 'Setup Objective' LIMIT 1];
        
        Key_Result__c kr = new Key_Result__c(
            Name = 'Test Key Result for SaveKeyResultTargets',
            Objective__c = obj.Id,
            Metric__c = 'Surveys',
            Target_Value__c = 10
        );
        insert kr;

        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            LeadSource = 'Web'
        );
        insert testLead;

        List<Key_Result_Event_Link__c> links = new List<Key_Result_Event_Link__c>{
            new Key_Result_Event_Link__c(Key_Result__c = kr.Id, RecordId__c = String.valueOf(testLead.Id), Object_Type__c = 'WebLead'),
            new Key_Result_Event_Link__c(Key_Result__c = kr.Id, RecordId__c = kr.Id, Object_Type__c = 'Opportunity'),
            new Key_Result_Event_Link__c(Key_Result__c = kr.Id, RecordId__c = kr.Id, Object_Type__c = 'Call'),
            new Key_Result_Event_Link__c(Key_Result__c = kr.Id, RecordId__c = kr.Id, Object_Type__c = 'Contract'),
            new Key_Result_Event_Link__c(Key_Result__c = kr.Id, RecordId__c = kr.Id, Object_Type__c = 'Survey'),
            new Key_Result_Event_Link__c(Key_Result__c = kr.Id, RecordId__c = kr.Id, Object_Type__c = 'Review'),
            new Key_Result_Event_Link__c(Key_Result__c = kr.Id, RecordId__c = kr.Id, Object_Type__c = 'GoogleReview'),
            new Key_Result_Event_Link__c(Key_Result__c = kr.Id, RecordId__c = kr.Id, Object_Type__c = 'CaseStudy'),
            new Key_Result_Event_Link__c(Key_Result__c = kr.Id, RecordId__c = kr.Id, Object_Type__c = 'Event')
        };
        insert links;

        List<Key_Result_Target__c> targets = new List<Key_Result_Target__c>{
            new Key_Result_Target__c(Key_Result__c = kr.Id, Object_Type__c = 'Opportunity', Target__c = 5),
            new Key_Result_Target__c(Key_Result__c = kr.Id, Object_Type__c = 'Call', Target__c = 5),
            new Key_Result_Target__c(Key_Result__c = kr.Id, Object_Type__c = 'Contract', Target__c = 5),
            new Key_Result_Target__c(Key_Result__c = kr.Id, Object_Type__c = 'WebLead', Target__c = 5),
            new Key_Result_Target__c(Key_Result__c = kr.Id, Object_Type__c = 'Survey', Target__c = 5),
            new Key_Result_Target__c(Key_Result__c = kr.Id, Object_Type__c = 'Review', Target__c = 5),
            new Key_Result_Target__c(Key_Result__c = kr.Id, Object_Type__c = 'GoogleReview', Target__c = 5),
            new Key_Result_Target__c(Key_Result__c = kr.Id, Object_Type__c = 'CaseStudy', Target__c = 5),
            new Key_Result_Target__c(Key_Result__c = kr.Id, Object_Type__c = 'Event', Target__c = 5)
        };
        insert targets;

        Test.startTest();
        List<OKRController.ObjectiveWithKeyResults> results = OKRController.getObjectivesWithKeyResults(testUser.Id, 2024);
        Test.stopTest();

        OKRController.KeyResultWrapper krWrapper = results[0].keyResults[0];
        System.assertEquals(1, krWrapper.opportunityCount);
        System.assertEquals(1, krWrapper.callCount);
        System.assertEquals(1, krWrapper.contractCount);
        System.assertEquals(1, krWrapper.webLeadCount);
        System.assertEquals(1, krWrapper.surveyCount);
        System.assertEquals(1, krWrapper.reviewCount);
        System.assertEquals(1, krWrapper.googleReviewCount);
        System.assertEquals(1, krWrapper.caseStudyCount);
        System.assertEquals(1, krWrapper.eventCount);
        System.assertEquals(5, krWrapper.opportunityTarget);
        System.assertEquals(5, krWrapper.surveyTarget);
    }
}