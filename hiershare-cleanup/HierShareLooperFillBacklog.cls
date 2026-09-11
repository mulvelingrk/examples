public class HierShareLooperFillBacklog extends HierShareLooperPhaseBatch {
    
    public HierShareLooperFillBacklog (HierShareLooper.ProcessPhase phase) {
        super(phase);
    }

    public override Database.QueryLocator start(Database.BatchableContext bc) {
        Integer fillLimit = this.phase.lockedConfig.fillBacklogLimit;
        return Database.getQueryLocator(
            // query each node's group, its parent node, and its parent node's group:
            'SELECT rkcore__MemberKey__c ' +
            ' FROM rkcore__HierShare_GroupMember_Mapping__c ' +
            // this order-by is not necessary to the processing algorithm's correctness, but it improves performance:
            ' ORDER BY rkcore__MemberKey__c' + 
            (fillLimit != null ? ' LIMIT ' + fillLimit : ''));
    }

    public override void execute(Database.BatchableContext bc, List<SObject> memRegs) {
        Set<String> memberKeyScope = new Set<String>();
        for (rkcore__HierShare_GroupMember_Mapping__c memReg : (rkcore__HierShare_GroupMember_Mapping__c[]) memRegs) {
            memberKeyScope.add(memReg.rkcore__MemberKey__c);
        }
        rkcore__Process_Request__c[] processReqs = new rkcore__Process_Request__c[]{};
        String[] keyQueue = new List<String>(memberKeyScope);
        Integer processItemSize = this.phase.lockedConfig.processItemSize;
        do {
            String[] keyChunk = new String[]{};
            while (keyChunk.size() < processItemSize && !keyQueue.isEmpty()) {
                keyChunk.add(keyQueue.remove(0));
            }
            processReqs.add(new rkcore__Process_Request__c(
                rkcore__Scope__c = String.join(new List<String>(keyChunk), ','), 
                rkcore__Scope_Size__c = keyChunk.size(),
                rkcore__Process_Type__c = HierShareLooper.GroupMemberWorkerClass)); //GROUP_MEMBER_PROCESS_WORKER_CLASS));
        } while (!keyQueue.isEmpty());
        insert processReqs;
    }
}