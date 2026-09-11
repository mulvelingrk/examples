public class HierShareLooperEraseBacklog extends HierShareLooperPhaseBatch {
        public HierShareLooperEraseBacklog(HierShareLooper.ProcessPhase phase) {
            super(phase);
        }

        public override Database.QueryLocator start(Database.BatchableContext bc){
            return Database.getQueryLocator('SELECT Id from rkcore__Process_Request__c');
        }

        public override void execute(Database.BatchableContext bc, List<SObject> records) {
            delete records;
        }
    }