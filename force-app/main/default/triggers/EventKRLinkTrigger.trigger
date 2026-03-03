trigger EventKRLinkTrigger on Event_KR_Link__c (after insert) {
    List<Key_Result_Event_Link__c> krlink = new List<Key_Result_Event_Link__c>();
    
    for(Event_KR_Link__c link : Trigger.new){
        if (link.Key_Result__c != null && !String.isBlank(link.Event_Id__c)){
            krlink.add(new Key_Result_Event_Link__c(
                Key_Result__c = link.Key_Result__c,
                RecordId__c = link.Event_Id__c,
                Object_Type__c = 'Event'
            ));
        }
    }
    if (!krlink.isEmpty()){
        insert krlink;
    }
}