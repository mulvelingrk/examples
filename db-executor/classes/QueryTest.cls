@isTest
private class QueryTest {
    
    // API Version 66 applies SYSTEM_MODE by default:
    @isTest
    static void testDefaultMode66() {
        User admin = [ select Profile.Name from User where Profile.Name = 'System Administrator' limit 1 ];
        User user_a = newUser('a');
        User user_b = newUser('b');
        User user_c = newUser('c');
        User user_d = newUser('d');
        System.runAs(admin) {
            insert new User[]{ user_a, user_b, user_c };
        }
        
        System.runAs(user_a) {
            insert new TestPrivate__c[]{ new TestPrivate__c(Name='A1'), new TestPrivate__c(Name='A2'), new TestPrivate__c(Name='A3') };
        }
        System.runAs(user_b) {
            insert new TestPrivate__c[]{ new TestPrivate__c(Name='B1'), new TestPrivate__c(Name='B2') };
        }
        System.runAs(user_c) {
            insert new TestPrivate__c[]{ new TestPrivate__c(Name='C1') };
        }
        
        System.runAs(user_a) {
            Assert.areEqual(3, Query66Caller.undeclared_withShare().size());
            Assert.areEqual(6, Query66Caller.undeclared_withoutShare().size());
            Assert.areEqual(3, Query66Caller.undeclared_inherited().size());
        }
        System.runAs(user_b) {
            Assert.areEqual(2, Query66Caller.undeclared_withShare().size());
            Assert.areEqual(6, Query66Caller.undeclared_withoutShare().size());
            Assert.areEqual(2, Query66Caller.undeclared_inherited().size());
        }
        System.runAs(user_c) {
            Assert.areEqual(1, Query66Caller.undeclared_withShare().size());
            Assert.areEqual(6, Query66Caller.undeclared_withoutShare().size());
            Assert.areEqual(1, Query66Caller.undeclared_inherited().size());
        }
        System.runAs(user_d) {
            Assert.areEqual(0, Query66Caller.undeclared_withShare().size());
            Assert.areEqual(6, Query66Caller.undeclared_withoutShare().size());
            Assert.areEqual(0, Query66Caller.undeclared_inherited().size());
        }
        
        System.runAs(user_a) {
            Assert.areEqual(3, Query66Caller.withShare_inherited().size());
            Assert.areEqual(6, Query66Caller.withoutShare_inherited().size());
            Assert.areEqual(6, Query66Caller.withShare_withoutShare().size());
            Assert.areEqual(3, Query66Caller.withoutShare_withShare().size());
        }
        System.runAs(user_b) {
            Assert.areEqual(2, Query66Caller.withShare_inherited().size());
            Assert.areEqual(6, Query66Caller.withoutShare_inherited().size());
            Assert.areEqual(6, Query66Caller.withShare_withoutShare().size());
            Assert.areEqual(2, Query66Caller.withoutShare_withShare().size());
        }
        System.runAs(user_c) {
            Assert.areEqual(1, Query66Caller.withShare_inherited().size());
            Assert.areEqual(6, Query66Caller.withoutShare_inherited().size());
            Assert.areEqual(6, Query66Caller.withShare_withoutShare().size());
            Assert.areEqual(1, Query66Caller.withoutShare_withShare().size());
        }
        System.runAs(user_d) {
            Assert.areEqual(0, Query66Caller.withShare_inherited().size());
            Assert.areEqual(6, Query66Caller.withoutShare_inherited().size());
            Assert.areEqual(6, Query66Caller.withShare_withoutShare().size());
            Assert.areEqual(0, Query66Caller.withoutShare_withShare().size());
        }
        
        System.runAs(user_a) {
            Assert.areEqual(3, new Query66Caller().inner_inherited_userExecutor().size());
            Assert.areEqual(3, new Query66Caller().inner_withShare_userExecutor().size());
            Assert.areEqual(3, new Query66Caller().inner_withoutShare_userExecutor().size());
            Assert.areEqual(3, new Query66Caller.WithShare().inner_inherited_userExecutor().size());
            Assert.areEqual(3, new Query66Caller.WithShare().inner_withShare_userExecutor().size());
            Assert.areEqual(3, new Query66Caller.WithShare().inner_withoutShare_userExecutor().size());
            Assert.areEqual(3, new Query66Caller.WithoutShare().inner_inherited_userExecutor().size());
            Assert.areEqual(3, new Query66Caller.WithoutShare().inner_withShare_userExecutor().size());
            Assert.areEqual(3, new Query66Caller.WithoutShare().inner_withoutShare_userExecutor().size());
            
            Assert.areEqual(6, new Query66Caller().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller().inner_withoutShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithShare().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithShare().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithShare().inner_withoutShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithoutShare().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithoutShare().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithoutShare().inner_withoutShare_systemExecutor().size());
        }
        System.runAs(user_d) {
            Assert.areEqual(0, new Query66Caller().inner_inherited_userExecutor().size());
            Assert.areEqual(0, new Query66Caller().inner_withShare_userExecutor().size());
            Assert.areEqual(0, new Query66Caller().inner_withoutShare_userExecutor().size());
            Assert.areEqual(0, new Query66Caller.WithShare().inner_inherited_userExecutor().size());
            Assert.areEqual(0, new Query66Caller.WithShare().inner_withShare_userExecutor().size());
            Assert.areEqual(0, new Query66Caller.WithShare().inner_withoutShare_userExecutor().size());
            Assert.areEqual(0, new Query66Caller.WithoutShare().inner_inherited_userExecutor().size());
            Assert.areEqual(0, new Query66Caller.WithoutShare().inner_withShare_userExecutor().size());
            Assert.areEqual(0, new Query66Caller.WithoutShare().inner_withoutShare_userExecutor().size());
            
            Assert.areEqual(6, new Query66Caller().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller().inner_withoutShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithShare().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithShare().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithShare().inner_withoutShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithoutShare().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithoutShare().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithoutShare().inner_withoutShare_systemExecutor().size());
        }
    }
    
    // API Version 67 applies USER_MODE by default:
    @isTest
    static void testDefaultMode67() {
        User admin = [ select Profile.Name from User where Profile.Name = 'System Administrator' limit 1 ];
        User user_a = newUser('a');
        User user_b = newUser('b');
        User user_c = newUser('c');
        User user_d = newUser('d');
        System.runAs(admin) {
            insert new User[]{ user_a, user_b, user_c };
        }
        
        System.runAs(user_a) {
            insert new TestPrivate__c[]{ new TestPrivate__c(Name='A1'), new TestPrivate__c(Name='A2'), new TestPrivate__c(Name='A3') };
        }
        System.runAs(user_b) {
            insert new TestPrivate__c[]{ new TestPrivate__c(Name='B1'), new TestPrivate__c(Name='B2') };
        }
        System.runAs(user_c) {
            insert new TestPrivate__c[]{ new TestPrivate__c(Name='C1') };
        }
        
        System.runAs(user_a) {
            Assert.areEqual(3, Query67Caller.undeclared_withShare().size());
            Assert.areEqual(3, Query67Caller.undeclared_withoutShare().size());
            Assert.areEqual(3, Query67Caller.undeclared_inherited().size());
        }
        System.runAs(user_b) {
            Assert.areEqual(2, Query67Caller.undeclared_withShare().size());
            Assert.areEqual(2, Query67Caller.undeclared_withoutShare().size());
            Assert.areEqual(2, Query67Caller.undeclared_inherited().size());
        }
        System.runAs(user_c) {
            Assert.areEqual(1, Query67Caller.undeclared_withShare().size());
            Assert.areEqual(1, Query67Caller.undeclared_withoutShare().size());
            Assert.areEqual(1, Query67Caller.undeclared_inherited().size());
        }
        System.runAs(user_d) {
            Assert.areEqual(0, Query67Caller.undeclared_withShare().size());
            Assert.areEqual(0, Query67Caller.undeclared_withoutShare().size());
            Assert.areEqual(0, Query67Caller.undeclared_inherited().size());
        }
        
        System.runAs(user_a) {
            Assert.areEqual(3, Query67Caller.withShare_inherited().size());
            Assert.areEqual(3, Query67Caller.withoutShare_inherited().size());
            Assert.areEqual(3, Query67Caller.withShare_withoutShare().size());
            Assert.areEqual(3, Query67Caller.withoutShare_withShare().size());
        }
        System.runAs(user_b) {
            Assert.areEqual(2, Query67Caller.withShare_inherited().size());
            Assert.areEqual(2, Query67Caller.withoutShare_inherited().size());
            Assert.areEqual(2, Query67Caller.withShare_withoutShare().size());
            Assert.areEqual(2, Query67Caller.withoutShare_withShare().size());
        }
        System.runAs(user_c) {
            Assert.areEqual(1, Query67Caller.withShare_inherited().size());
            Assert.areEqual(1, Query67Caller.withoutShare_inherited().size());
            Assert.areEqual(1, Query67Caller.withShare_withoutShare().size());
            Assert.areEqual(1, Query67Caller.withoutShare_withShare().size());
        }
        System.runAs(user_d) {
            Assert.areEqual(0, Query67Caller.withShare_inherited().size());
            Assert.areEqual(0, Query67Caller.withoutShare_inherited().size());
            Assert.areEqual(0, Query67Caller.withShare_withoutShare().size());
            Assert.areEqual(0, Query67Caller.withoutShare_withShare().size());
        }
    }
    
    @isTest
    static void testExecutors() {
        User admin = [ select Profile.Name from User where Profile.Name = 'System Administrator' limit 1 ];
        User user_a = newUser('a');
        User user_b = newUser('b');
        User user_c = newUser('c');
        User user_d = newUser('d');
        System.runAs(admin) {
            insert new User[]{ user_a, user_b, user_c };
        }
        
        System.runAs(user_a) {
            insert new TestPrivate__c[]{ new TestPrivate__c(Name='A1'), new TestPrivate__c(Name='A2'), new TestPrivate__c(Name='A3') };
        }
        System.runAs(user_b) {
            insert new TestPrivate__c[]{ new TestPrivate__c(Name='B1'), new TestPrivate__c(Name='B2') };
        }
        System.runAs(user_c) {
            insert new TestPrivate__c[]{ new TestPrivate__c(Name='C1') };
        }
        
        // When you go through DatabaseExecutor, it REMOVES the complex interactive effects of: static context (lexical / enclosing class), 
        // dynamic context (override method "home class" / dynamic caller), and API version (66 / 67)! All that matters is the specific 
        // instance of DatabaseExecutor you've chosen to go through! This is great because it makes your intent clear and normalizes behavior:
        System.runAs(user_a) {
            // Any queries thru DatabaseExecutor.UserMode will enforce security (RLS) regardless of API or outer context:
            Assert.areEqual(3, new Query66Caller().inner_inherited_userExecutor().size());
            Assert.areEqual(3, new Query66Caller().inner_withShare_userExecutor().size());
            Assert.areEqual(3, new Query66Caller().inner_withoutShare_userExecutor().size());
            Assert.areEqual(3, new Query66Caller.WithShare().inner_inherited_userExecutor().size());
            Assert.areEqual(3, new Query66Caller.WithShare().inner_withShare_userExecutor().size());
            Assert.areEqual(3, new Query66Caller.WithShare().inner_withoutShare_userExecutor().size());
            Assert.areEqual(3, new Query66Caller.WithoutShare().inner_inherited_userExecutor().size());
            Assert.areEqual(3, new Query66Caller.WithoutShare().inner_withShare_userExecutor().size());
            Assert.areEqual(3, new Query66Caller.WithoutShare().inner_withoutShare_userExecutor().size());
            Assert.areEqual(3, new Query67Caller().inner_inherited_userExecutor().size());
            Assert.areEqual(3, new Query67Caller().inner_withShare_userExecutor().size());
            Assert.areEqual(3, new Query67Caller().inner_withoutShare_userExecutor().size());
            Assert.areEqual(3, new Query67Caller.WithShare().inner_inherited_userExecutor().size());
            Assert.areEqual(3, new Query67Caller.WithShare().inner_withShare_userExecutor().size());
            Assert.areEqual(3, new Query67Caller.WithShare().inner_withoutShare_userExecutor().size());
            Assert.areEqual(3, new Query67Caller.WithoutShare().inner_inherited_userExecutor().size());
            Assert.areEqual(3, new Query67Caller.WithoutShare().inner_withShare_userExecutor().size());
            Assert.areEqual(3, new Query67Caller.WithoutShare().inner_withoutShare_userExecutor().size());
            
            // Any queries thru DatabaseExecutor.SystemMode will bypass security regardless of API or outer context:
            Assert.areEqual(6, new Query66Caller().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller().inner_withoutShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithShare().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithShare().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithShare().inner_withoutShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithoutShare().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithoutShare().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithoutShare().inner_withoutShare_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller().inner_withoutShare_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller.WithShare().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller.WithShare().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller.WithShare().inner_withoutShare_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller.WithoutShare().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller.WithoutShare().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller.WithoutShare().inner_withoutShare_systemExecutor().size());
        }
        System.runAs(user_d) {
            // Any queries thru DatabaseExecutor.UserMode will enforce security (RLS) regardless of API or outer context:
            Assert.areEqual(0, new Query66Caller().inner_inherited_userExecutor().size());
            Assert.areEqual(0, new Query66Caller().inner_withShare_userExecutor().size());
            Assert.areEqual(0, new Query66Caller().inner_withoutShare_userExecutor().size());
            Assert.areEqual(0, new Query66Caller.WithShare().inner_inherited_userExecutor().size());
            Assert.areEqual(0, new Query66Caller.WithShare().inner_withShare_userExecutor().size());
            Assert.areEqual(0, new Query66Caller.WithShare().inner_withoutShare_userExecutor().size());
            Assert.areEqual(0, new Query66Caller.WithoutShare().inner_inherited_userExecutor().size());
            Assert.areEqual(0, new Query66Caller.WithoutShare().inner_withShare_userExecutor().size());
            Assert.areEqual(0, new Query66Caller.WithoutShare().inner_withoutShare_userExecutor().size());
            Assert.areEqual(0, new Query67Caller().inner_inherited_userExecutor().size());
            Assert.areEqual(0, new Query67Caller().inner_withShare_userExecutor().size());
            Assert.areEqual(0, new Query67Caller().inner_withoutShare_userExecutor().size());
            Assert.areEqual(0, new Query67Caller.WithShare().inner_inherited_userExecutor().size());
            Assert.areEqual(0, new Query67Caller.WithShare().inner_withShare_userExecutor().size());
            Assert.areEqual(0, new Query67Caller.WithShare().inner_withoutShare_userExecutor().size());
            Assert.areEqual(0, new Query67Caller.WithoutShare().inner_inherited_userExecutor().size());
            Assert.areEqual(0, new Query67Caller.WithoutShare().inner_withShare_userExecutor().size());
            Assert.areEqual(0, new Query67Caller.WithoutShare().inner_withoutShare_userExecutor().size());
            
            // Any queries thru DatabaseExecutor.SystemMode will bypass security regardless of API or outer context:
            Assert.areEqual(6, new Query66Caller().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller().inner_withoutShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithShare().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithShare().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithShare().inner_withoutShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithoutShare().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithoutShare().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query66Caller.WithoutShare().inner_withoutShare_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller().inner_withoutShare_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller.WithShare().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller.WithShare().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller.WithShare().inner_withoutShare_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller.WithoutShare().inner_inherited_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller.WithoutShare().inner_withShare_systemExecutor().size());
            Assert.areEqual(6, new Query67Caller.WithoutShare().inner_withoutShare_systemExecutor().size());
        }
    }
    
    static Profile TestProfile;
    static {
        TestProfile = [ select Name from Profile where Name = 'Test Profile' ];
    }
    
    static User newUser(String n) {
        return new User(
            FirstName = 'User',
            LastName = n,
            Email = 'user_' + n + '@testharness.com',
            Username = 'user_' + n + '@testharness.com',
            Alias = n,
            ProfileId = TestProfile.Id,
            TimeZoneSidKey = 'GMT',
            LocaleSidKey = 'en_US',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8'
        );
    }
}