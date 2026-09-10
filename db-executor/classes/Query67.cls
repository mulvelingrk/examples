public virtual inherited sharing class Query67 {

    public virtual TestPrivate__c[] readAll() {
        return [ select Name from TestPrivate__c ];
    }
    
    public virtual TestPrivate__c[] readAll(AccessLevel lvl) {
        return Database.query('select Name from TestPrivate__c', lvl);
    }
    
    public virtual TestPrivate__c[] readAll(DatabaseExecutor executor) {
        return executor.query('select Name from TestPrivate__c');
    }
    
    public with sharing class WithShare extends Query67 {
        public override TestPrivate__c[] readAll() {
            return [ select Name from TestPrivate__c ];
        }
        
        public override TestPrivate__c[] readAll(AccessLevel lvl) {
            return Database.query('select Name from TestPrivate__c', lvl);
        }
        
        public override TestPrivate__c[] readAll(DatabaseExecutor executor) {
            return executor.query('select Name from TestPrivate__c');
        }
    }
    
    public without sharing class WithoutShare extends Query67 {
        public override TestPrivate__c[] readAll() {
            return [ select Name from TestPrivate__c ];
        }
        
        public override TestPrivate__c[] readAll(AccessLevel lvl) {
            return Database.query('select Name from TestPrivate__c', lvl);
        }
        
        public override TestPrivate__c[] readAll(DatabaseExecutor executor) {
            return executor.query('select Name from TestPrivate__c');
        }
    }
}