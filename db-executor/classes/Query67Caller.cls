public virtual class Query67Caller {
    
    public virtual TestPrivate__c[] inner_inherited() {
        return new Query67().readAll();
    }
    
    public virtual TestPrivate__c[] inner_withShare() {
        return new Query67.WithShare().readAll();
    }
    
    public virtual TestPrivate__c[] inner_withoutShare() {
        return new Query67.WithoutShare().readAll();
    }

    public virtual TestPrivate__c[] inner_inherited(AccessLevel lvl) {
        return new Query67().readAll(lvl);
    }
    
    public virtual TestPrivate__c[] inner_withShare(AccessLevel lvl) {
        return new Query67.WithShare().readAll(lvl);
    }
    
    public virtual TestPrivate__c[] inner_withoutShare(AccessLevel lvl) {
        return new Query67.WithoutShare().readAll(lvl);
    }
    
    public virtual TestPrivate__c[] inner_inherited_userExecutor() {
        return new Query66().readAll(DatabaseExecutor.UserMode);
    }
    
    public virtual TestPrivate__c[] inner_withShare_userExecutor() {
        return new Query66.WithShare().readAll(DatabaseExecutor.UserMode);
    }


    public virtual TestPrivate__c[] inner_withoutShare_userExecutor() {
        return new Query66.WithoutShare().readAll(DatabaseExecutor.UserMode);
    }

    public virtual TestPrivate__c[] inner_inherited_systemExecutor() {
        return new Query66().readAll(DatabaseExecutor.SystemMode);
    }
    
    public virtual TestPrivate__c[] inner_withShare_systemExecutor() {
        return new Query66.WithShare().readAll(DatabaseExecutor.SystemMode);
    }


    public virtual TestPrivate__c[] inner_withoutShare_systemExecutor() {
        return new Query66.WithoutShare().readAll(DatabaseExecutor.SystemMode);
    }

    public with sharing class WithShare extends Query67Caller {
        public override TestPrivate__c[] inner_inherited() {
            return new Query67().readAll();
        }
        
        public override TestPrivate__c[] inner_withShare() {
            return new Query67.WithShare().readAll();
        }
        
        public override TestPrivate__c[] inner_withoutShare() {
            return new Query67.WithoutShare().readAll();
        }
    
        public override TestPrivate__c[] inner_inherited(AccessLevel lvl) {
            return new Query67().readAll(lvl);
        }
        
        public override TestPrivate__c[] inner_withShare(AccessLevel lvl) {
            return new Query67.WithShare().readAll(lvl);
        }
        
        public override TestPrivate__c[] inner_withoutShare(AccessLevel lvl) {
            return new Query67.WithoutShare().readAll(lvl);
        }
        
        public override TestPrivate__c[] inner_inherited_userExecutor() {
            return new Query66().readAll(DatabaseExecutor.UserMode);
        }
        
        public override TestPrivate__c[] inner_withShare_userExecutor() {
            return new Query66.WithShare().readAll(DatabaseExecutor.UserMode);
        }
    
    
        public override TestPrivate__c[] inner_withoutShare_userExecutor() {
            return new Query66.WithoutShare().readAll(DatabaseExecutor.UserMode);
        }
    
        public override TestPrivate__c[] inner_inherited_systemExecutor() {
            return new Query66().readAll(DatabaseExecutor.SystemMode);
        }
        
        public override TestPrivate__c[] inner_withShare_systemExecutor() {
            return new Query66.WithShare().readAll(DatabaseExecutor.SystemMode);
        }
    
    
        public override TestPrivate__c[] inner_withoutShare_systemExecutor() {
            return new Query66.WithoutShare().readAll(DatabaseExecutor.SystemMode);
        }
    }
    
    public without sharing class WithoutShare extends Query67Caller {
        public override TestPrivate__c[] inner_inherited() {
            return new Query67().readAll();
        }
        
        public override TestPrivate__c[] inner_withShare() {
            return new Query67.WithShare().readAll();
        }
        
        public override TestPrivate__c[] inner_withoutShare() {
            return new Query67.WithoutShare().readAll();
        }
    
        public override TestPrivate__c[] inner_inherited(AccessLevel lvl) {
            return new Query67().readAll(lvl);
        }
        
        public override TestPrivate__c[] inner_withShare(AccessLevel lvl) {
            return new Query67.WithShare().readAll(lvl);
        }
        
        public override TestPrivate__c[] inner_withoutShare(AccessLevel lvl) {
            return new Query67.WithoutShare().readAll(lvl);
        }
        
        public override TestPrivate__c[] inner_inherited_userExecutor() {
            return new Query66().readAll(DatabaseExecutor.UserMode);
        }
        
        public override TestPrivate__c[] inner_withShare_userExecutor() {
            return new Query66.WithShare().readAll(DatabaseExecutor.UserMode);
        }
    
    
        public override TestPrivate__c[] inner_withoutShare_userExecutor() {
            return new Query66.WithoutShare().readAll(DatabaseExecutor.UserMode);
        }
    
        public override TestPrivate__c[] inner_inherited_systemExecutor() {
            return new Query66().readAll(DatabaseExecutor.SystemMode);
        }
        
        public override TestPrivate__c[] inner_withShare_systemExecutor() {
            return new Query66.WithShare().readAll(DatabaseExecutor.SystemMode);
        }
    
    
        public override TestPrivate__c[] inner_withoutShare_systemExecutor() {
            return new Query66.WithoutShare().readAll(DatabaseExecutor.SystemMode);
        }
    }
    
    public static TestPrivate__c[] undeclared_inherited() {
        return new Query67Caller().inner_inherited();
    }
    
    public static TestPrivate__c[] undeclared_withShare() {
        return new Query67Caller().inner_withShare();
    }
    
    public static TestPrivate__c[] undeclared_withoutShare() {
        return new Query67Caller().inner_withoutShare();
    }
    
    public static TestPrivate__c[] withShare_inherited() {
        return new Query67Caller.WithShare().inner_inherited();
    }
    
    public static TestPrivate__c[] withoutShare_inherited() {
        return new Query67Caller.WithoutShare().inner_inherited();
    }
    
    public static TestPrivate__c[] withoutShare_withShare() {
        return new Query67Caller.WithoutShare().inner_withShare();
    }
    
    public static TestPrivate__c[] withShare_withoutShare() {
        return new Query67Caller.WithShare().inner_withoutShare();
    }
}