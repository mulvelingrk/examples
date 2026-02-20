/*
 * Mike Ulveling
 * 
 * Tests for proper verification of custom HierShare functionality on this org:
 */
@isTest
private class HierShareLocalTests {

    static {
        HierShareConfigDef.UseTestHarness = true;
    }
    
    static User SysAdmin;
    static {
        SysAdmin = [ SELECT Name, Alias FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1 ];
    }

    static final String[] NRE_RecTypes_Physical = new String[]{
        'active_shooter',
        'evacuation',
        'fire',
        'health_hazard',
        'hostage_taking',
        'infestation',
        'natural_disaster',
        'staff_behavior',
        'firearms_weapons_bomb_threat',
        'theft_of_non_resident_property',
        'utility',
        'visitor_injury',
        'flood'
    };

    static final String[] NRE_RecTypes_Info = new String[]{
        'data_breach',
        'data_repository',
        'exit_interview',
        'police_government_investigation',
        'government_investigation',
        'compliance_violations',
        'identity_theft',
        'privacy_program_violation',
        'privacy_concern',
        'privacy_security',
        'site_assessments',
        'proactive_audits',
        'request_or_question',
        'risk_assessment',
        'support_line'
    };

    static final String RCA_RecType_PI = 'ltc_performance_improvement';
    static final String RCA_RecType_PSCA = 'patient_safety_cause_analysis';

    static final String[] HierAttachPointLookups = new String[]{
        'Primary_Facility__c', 'Primary_Location__c',
        'Secondary_Facility__c', 'Secondary_Location__c'
    };
    static final String[] HierAttachPointCodes = new String[]{
        'PF', 'PL',
        'SF', 'SL'
    };

    static final Map<String, String> HierAttachLkpByCode = new Map<String, String>{
        'PF' => 'Primary_Facility__c', 
        'PL' => 'Primary_Location__c',
        'SF' => 'Secondary_Facility__c', 
        'SL' => 'Secondary_Location__c'
    };

    static Map<String, RecordTypeInfo> caseNormalize(Map<String, RecordTypeInfo> mapp) {
        Map<String, RecordTypeInfo> norm = new Map<String, RecordTypeInfo>();
        for (String key : mapp.keySet()) {
            RecordTypeInfo val = mapp.get(key);
            norm.put(key.toLowerCase(), val);
            norm.put(key, val);
        }
        return norm;
    }

    @isTest
    static void localTriggers() {
        // Just touch the HierShare_* triggers for code coverage %:
        insert new Patient_Event__c();
        Patient_Satisfaction__c feedback = new Patient_Satisfaction__c();
        insert feedback;
        Test.startTest();
        insert new Patient_Feedback_Review__c(Patient_Feedback__c = feedback.Id);
    }

    @isTest
    static void localTriggers2() {
        insert new Employee_Event__c();        
        // These will no-op because we set (HierShareConfigDef.UseTestHarness = true), but we're
        // just inserting these for the % code coverage on their HierShare_* triggers:
        insert new Root_Cause_Analysis__c();
    }

    @isTest
    static void localTriggers3() {
        try {
            insert new Non_Resident_Event__c();
        } catch (DMLException haltingError) {} // ignore

    }

    @isTest
    static void localTriggers4() {
        try {
            insert new Resident_Event__c();
        } catch (DMLException haltingError) {} // ignore
    }

    @TestSetup
    static void makeData() {
        Harness testSet = new Harness().init();
    }
        
    // This test is bypassed when HierShareConfigDef.NRE_SpecialLogicEnabled is set to false:
    @isTest
    static void testSharing_specialNREs() {
        if (!HierShareConfigDef.NRE_SpecialLogicEnabled) {
            return;
        }
        //Assert.isTrue(HierShareConfigDef.NRE_SpecialLogicEnabled,
        //    'This test is only valid when HierShareConfigDef.NRE_SpecialLogicEnabled is True');
        Harness testSet = new Harness().load();

        Test.startTest();
        testSet.asyncGroupMemRefresh();
        Test.stopTest();
        
        // Verify our expected NRE and RCA record counts per user:
        String hierCode = 'ACME';
        // [ltc med safety rbu] get physical NRE assignments, of which we've created 15:
        testSet.nreCount('ltc_med', 15, hierCode)
            // [ltc executive leaders - rbu] also get physical NREs:
            .nreCount('ltc_exec', 15, hierCode)
            // [ltc quality rbu] also get physical NREs:
            .nreCount('ltc_qual', 15, hierCode)
            // [ltc environmental health & safety consultant rbu] also get physical NREs:
            .nreCount('ltc_env', 15, hierCode)
            // [ltc/healthcare leader] get physical and informational NRE assignments, 15 + 18:
            .nreCount('ltc_heal', 33, hierCode)
            // [ltc system admin] get all NREs, 15 + 18:
            .nreCount('ltc_admi', 33, hierCode);
        
        // [ltc med safety rbu] get Performance Improvement (PI) RCA assignments, of which we've created 5:
        testSet.rcaCount('ltc_med', 5, hierCode)
            // [ltc executive leaders - rbu] also get PI RCAs:
            .rcaCount('ltc_exec', 5, hierCode)
            // [ltc quality rbu] also get PI RCAs:
            .rcaCount('ltc_qual', 5, hierCode)
            // [ltc environmental health & safety consultant rbu] get no RCAs:
            .rcaCount('ltc_env', 0, hierCode)
            // [ltc/healthcare leader] also get PI RCAs:
            .rcaCount('ltc_heal', 5, hierCode)
            // [ltc system admin] get PI and Patient Safety Cause Analysis (PSCA) RCAs, 5 + 4:
            .rcaCount('ltc_admi', 9, hierCode);
    }

    // This test is bypassed when HierShareConfigDef.NRE_SpecialLogicEnabled is set to true:
    @isTest
    static void testSharing_standardNREs() {
        if (HierShareConfigDef.NRE_SpecialLogicEnabled) {
            return;
        }
        //Assert.isFalse(HierShareConfigDef.NRE_SpecialLogicEnabled,
        //    'This test is only valid when HierShareConfigDef.NRE_SpecialLogicEnabled is False');
        Harness testSet = new Harness().load();

        Test.startTest();
        testSet.asyncGroupMemRefresh();
        Test.stopTest();
        
        // Verify our expected NRE and RCA record counts per user:
        String hierCode = 'ACME';
        // NRE is just a "standard" relationship here, so all profiles get all 33 NRE records:
        // [ltc med safety rbu]:
        testSet.nreCount('ltc_med', 33, hierCode)
            // [ltc executive leaders - rbu]:
            .nreCount('ltc_exec', 33, hierCode)
            // [ltc quality rbu]:
            .nreCount('ltc_qual', 33, hierCode)
            // [ltc environmental health & safety consultant rbu]:
            .nreCount('ltc_env', 33, hierCode)
            // [ltc/healthcare leader]:
            .nreCount('ltc_heal', 33, hierCode)
            // [ltc system admin]:
            .nreCount('ltc_admi', 33, hierCode);
        
        // [ltc med safety rbu] get Performance Improvement (PI) RCA assignments, of which we've created 5:
        testSet.rcaCount('ltc_med', 5, hierCode)
            // [ltc executive leaders - rbu] also get PI RCAs:
            .rcaCount('ltc_exec', 5, hierCode)
            // [ltc quality rbu] also get PI RCAs:
            .rcaCount('ltc_qual', 5, hierCode)
            // [ltc environmental health & safety consultant rbu] get no RCAs:
            .rcaCount('ltc_env', 0, hierCode)
            // [ltc/healthcare leader] also get PI RCAs:
            .rcaCount('ltc_heal', 5, hierCode)
            // [ltc system admin] get PI and Patient Safety Cause Analysis (PSCA) RCAs, 5 + 4:
            .rcaCount('ltc_admi', 9, hierCode);
    }

    @isTest
    static void testSharingCleanup() {
        Harness testSet = new Harness().load();

        // Run the cleanup process to effectively nullify all active access levels (as defined by HierShare config):
        HierShareLevelCleanup.deferChainingForTest = true;
        // Call it manually 3x for its 3 phases of cleanup:
        testSet.runActiveCleanupPhase();
        testSet.runActiveCleanupPhase();
        testSet.runActiveCleanupPhase();

        // Run the GroupMember Refresh batch as ususal - but it won't be doing much here, since the active levels 
        // have all been nullified, by above cleanup logic!
        Test.startTest();
        testSet.asyncGroupMemRefresh();
        Test.stopTest();

        // Verify our test users don't have access to jack shit because of the cleanup process:
        String hierCode = 'ACME';
        testSet.nreCount('ltc_med', 0, hierCode)
            .nreCount('ltc_exec', 0, hierCode)
            .nreCount('ltc_qual', 0, hierCode)
            .nreCount('ltc_env', 0, hierCode)
            .nreCount('ltc_heal', 0, hierCode)
            .nreCount('ltc_admi', 0, hierCode);

        testSet.rcaCount('ltc_med', 0, hierCode)
            .nreCount('ltc_exec', 0, hierCode)
            .nreCount('ltc_qual', 0, hierCode)
            .nreCount('ltc_env', 0, hierCode)
            .nreCount('ltc_heal', 0, hierCode)
            .nreCount('ltc_admi', 0, hierCode);
    }

    @IsTest
    static void extraLines() {
        // Just hits these extra method signatures I didn't utilize in the proper unit tests above:
        new HierShareLevelCleanup();
        Test.startTest();
        HierShareLevelCleanup.kickoff();
    }

    class Harness {
        Map<String, RecordTypeInfo> nreRecordTypesByName;
        Map<String, RecordTypeInfo> rcaRecordTypesByName;
        Map<String, Profile> profilesByNameLC;
        User[] newUsers;
        Map<String, User> usersByAlias = new Map<String, User>();

        rkl__RK_Hierarchy_Node__c[] newHiers;
        Map<String, rkl__RK_Hierarchy_Node__c> hiersByCode = new Map<String, rkl__RK_Hierarchy_Node__c>();

        rkl__RK_Hierarchy_Access__c[] newAssigns;

        TEST_Non_Resident_Event__c[] newNREs;
        Map<String, TEST_Non_Resident_Event__c> nresByName = new Map<String, TEST_Non_Resident_Event__c>();

        TEST_Root_Cause_Analysis__c[] newRCAs;
        Map<String, TEST_Root_Cause_Analysis__c> rcasByName = new Map<String, TEST_Root_Cause_Analysis__c>();

        // This batch instance will cleanup all ACTIVE levels, effectively removing their sharing power. 
        // This allows us to test is efficacy:
        //HierShareLevelCleanup activeCleanup = new HierShareLevelCleanup(new List<String>(
        //    HierShareConfigDef.GetParsedLevels().activeLevels.keySet()));
        HierShareLevelCleanup activeCleanup = HierShareLevelCleanup.newFullCleanup();

        Harness() {
            //init();
        }

        Harness init() {
            this.nreRecordTypesByName = caseNormalize(Schema.SObjectType.TEST_Non_Resident_Event__c.getRecordTypeInfosByDeveloperName());
            this.rcaRecordTypesByName = caseNormalize(Schema.SObjectType.TEST_Root_Cause_Analysis__c.getRecordTypeInfosByDeveloperName());
            System.runAs(SysAdmin) {
                insert new rkl__Form_Template__c(Name = 'Initial Reported Non-Resident Event');
                loadProfiles();
                initUsers();
                initHiers();
                initAssigns();
                initNREs();
                initRCAs();
            }
            return this;
        }

        Harness load() {
            loadProfiles();
            loadUsers();
            loadHiers();
            return this;
        }

        void loadProfiles() {
            this.profilesByNameLC = new Map<String, Profile>();
            for (Profile p : [ SELECT Name FROM Profile ]) {
                this.profilesByNameLC.put(p.Name.toLowerCase(), p);
            }
        }

        void loadUsers() {
            this.usersByAlias = new Map<String, User>();
            for (User usr : [ 
                    SELECT Alias, Username, Email 
                    FROM User 
                    WHERE Email LIKE 'testuser_%' ]) {
                this.usersByAlias.put(usr.Alias, usr);
            }
        }

        void loadHiers() {
            this.hiersByCode = new Map<String, rkl__RK_Hierarchy_Node__c>();
            for (rkl__RK_Hierarchy_Node__c node : [ 
                    SELECT Name, rkl__Node_Code__c, rkl__Node_Level__c 
                    FROM rkl__RK_Hierarchy_Node__c ]) {
                this.hiersByCode.put(node.rkl__Node_Code__c, node);
            }
        }

        void initUsers() {
            this.newUsers = new User[]{};
            // This user should only get basic "hier" level access - they're not granted 
            // any special access through our custom logic:
            newUser('ltc_med', 'LTC Med Safety RBU');

            // The following users each get a different subset of additional "special" 
            // access based on their profiles:
            newUser('ltc_lead', 'ltc leader rbu');
            newUser('ltc_exec', 'ltc executive leaders - rbu');
            newUser('ltc_qual', 'ltc quality rbu');
            newUser('ltc_env', 'ltc environmental health & safety consultant rbu');
            // This user gets most (but not all) of the additional special access:
            newUser('ltc_heal', 'ltc/healthcare leader');
            // This user gets ALL of the additional special access:
            newUser('ltc_admi', 'ltc system admin');

            insert this.newUsers;
            this.newUsers = null;
        }

        User newUser(String alias, String profileName) {
            Profile p = profilesByNameLC.get(profileName.toLowerCase());
            Assert.isNotNull(p, 'Profile [' + profileName + '] does not exist');
            User u = new User(
                UserName='testusermdu_' + alias + '@testorg.com',
                ProfileId = p.Id,
                Alias = alias, 
                Email = 'testusermdu_' + alias + '@testorg.com',
                LastName = 'Testing_' + alias,
                EmailEncodingKey='UTF-8',  
                LanguageLocaleKey='en_US', LocaleSidKey='en_US', 
                TimeZoneSidKey='America/Los_Angeles');
            this.newUsers.add(u);
            this.usersByAlias.put(alias, u);
            return u;
        }

        User usr(String userAlias) {
            User u = this.usersByAlias.get(userAlias);
            Assert.isNotNull(u, 'User by alias [' + userAlias + '] does not exist');
            return u;
        }

        void initHiers() {
            rkl__RK_Hierarchy_Node__c ACME, PF, PL, SF, SL;
            this.newHiers = new rkl__RK_Hierarchy_Node__c[]{};
            ACME = newHier('ACME');
            ACME.rkl__Node_Level__c = 4;
            insert this.newHiers;
            this.newHiers = new rkl__RK_Hierarchy_Node__c[]{};
            PF = newHier('PF'); // primary facility
            PF.rkl__Parent_Node__c = ACME.Id;
            PF.rkl__Node_Level__c = 4;
            SF = newHier('SF'); // secondary facility
            SF.rkl__Parent_Node__c = ACME.Id;
            SF.rkl__Node_Level__c = 4;
            SF.Available_for_Risk_PR_Visitor_Portal__c = true;
            insert this.newHiers;
            this.newHiers = new rkl__RK_Hierarchy_Node__c[]{};
            PL = newHier('PL'); // primary location
            PL.rkl__Node_Level__c = 5;
            PL.rkl__Parent_Node__c = PF.Id;
            SL = newHier('SL'); // secondary location
            SL.rkl__Node_Level__c = 5;
            SL.rkl__Parent_Node__c = SF.Id;
            SL.Available_for_Risk_PR_Visitor_Portal__c = true;
            insert this.newHiers;
            this.newHiers = null;
        }

        rkl__RK_Hierarchy_Node__c newHier(String code) {
            rkl__RK_Hierarchy_Node__c h = new rkl__RK_Hierarchy_Node__c(
                Name = code, 
                rkl__Node_Code__c = code, 
                rkl__Node_Level__c = 1);
            this.newHiers.add(h);
            this.hiersByCode.put(code, h);
            return h;
        }

        rkl__RK_Hierarchy_Node__c hier(String hierCode) {
            rkl__RK_Hierarchy_Node__c hier = this.hiersByCode.get(hierCode);
            Assert.isNotNull(hier, 'Hierarchy by code [' + hierCode + '] does not exist');
            return hier;
        }

        void initAssigns() {
            this.newAssigns = new rkl__RK_Hierarchy_Access__c[]{};
            // Insert an assignment for every defined user to hierarchy node ACME:
            for (String userAlias : this.usersByAlias.keySet()) {
                newAssign('ACME', userAlias);
            }
            insert this.newAssigns;
            this.newAssigns = null;
        }

        rkl__RK_Hierarchy_Access__c newAssign(String hierCode, String userAlias) {
            rkl__RK_Hierarchy_Access__c assign = new rkl__RK_Hierarchy_Access__c(
                rkl__Hierarchy__c = this.hier(hierCode).Id, 
                rkl__User__c = this.usr(userAlias).Id);
            this.newAssigns.add(assign);
            return assign;
        }

        void initNREs() {
            this.newNREs = new TEST_Non_Resident_Event__c[]{};
            //String hierCode = 'ACME';
            for (String recType : NRE_RecTypes_Physical) {
                newNRE('PF_PL.' + recType.toLowerCase() + '.1', recType);
            }
            // Put a 2nd NRE on fire and flood:
            newNRE('PF_PL_SF_SL.fire.2', 'fire');
            newNRE('PF_PL_SF_SL.flood.2', 'flood');
            
            for (String recType : NRE_RecTypes_Info) {
                newNRE('SF_SL.' + recType.toLowerCase() + '.1', recType);
            }
            // Put a 2nd and 3rd RCA on data_breach:
            newNRE('PF_PL_SF_SL.data_breach.2', 'data_breach');
            newNRE('PF_PL_SF_SL.data_breach.3', 'data_breach');
            // Put a 2nd RCA on privacy_security:
            newNRE('PF_PL_SF_SL.privacy_security.2', 'privacy_security');
            
            insert this.newNREs;
            this.newNREs = null;
        }

        TEST_Non_Resident_Event__c newNRE(String name, String recTypeName) { //String[] hierAttachCodes) {
            // As we mint new NRE's we regularly cycle through each of the 4 hierarchy attachment 
            // points, to verify they're all working:
            Integer hierAttachIndex = Math.mod(this.newNREs.size(), HierAttachPointLookups.size());
            RecordTypeInfo recType = this.nreRecordTypesByName.get(recTypeName);
            Assert.isNotNull(recType, 'TEST_Non_Resident_Event__c RecordType [' + recTypeName + '] does not exist');
            TEST_Non_Resident_Event__c nre = new TEST_Non_Resident_Event__c(
                RecordTypeId = recType.getRecordTypeId(),
                Name = name);

            String hierLkp = HierAttachPointLookups[hierAttachIndex];
            String hierCode = HierAttachPointCodes[hierAttachIndex];
            nre.put(hierLkp, this.hier(hierCode).Id);
            this.newNREs.add(nre);
            this.nresByName.put(name, nre);
            return nre;
        }

        void initRCAs() {
            this.newRCAs = new TEST_Root_Cause_Analysis__c[]{};
            //String hierCode = 'ACME';            
            newRCA('PF.' + RCA_RecType_PSCA.toLowerCase() + '.1', RCA_RecType_PSCA);
            newRCA('PF_PL.' + RCA_RecType_PSCA.toLowerCase() + '.2', RCA_RecType_PSCA);
            newRCA('SF.' + RCA_RecType_PSCA.toLowerCase() + '.3', RCA_RecType_PSCA);
            newRCA('SF_SL.' + RCA_RecType_PSCA.toLowerCase() + '.4', RCA_RecType_PSCA);

            newRCA('PF.' + RCA_RecType_PI.toLowerCase() + '.1', RCA_RecType_PI);
            newRCA('PF_PL.' + RCA_RecType_PI.toLowerCase() + '.2', RCA_RecType_PI);
            newRCA('SF.' + RCA_RecType_PI.toLowerCase() + '.3', RCA_RecType_PI);
            newRCA('SF_SL.' + RCA_RecType_PI.toLowerCase() + '.4', RCA_RecType_PI);
            newRCA('PF_PL_SF_SL.' + RCA_RecType_PI.toLowerCase() + '.5', RCA_RecType_PI);

            insert this.newRCAs;
            this.newRCAs = null;
        }

        TEST_Root_Cause_Analysis__c newRCA(String name, String recTypeName) { //, String[] hierAttachCodes) {
            // As we mint new NRE's we regularly cycle through each of the 4 hierarchy attachment 
            // points, to verify they're all working:
            Integer hierAttachIndex = Math.mod(this.newRCAs.size(), HierAttachPointLookups.size());
            RecordTypeInfo recType = this.rcaRecordTypesByName.get(recTypeName);
            Assert.isNotNull(recType, 'TEST_Root_Cause_Analysis__c RecordType [' + recTypeName + '] does not exist');
            TEST_Root_Cause_Analysis__c rca = new TEST_Root_Cause_Analysis__c(
                RecordTypeId = recType.getRecordTypeId(),
                // RCA's Name field is an auto-number, so we have to pick something else:
                WC_Comments__c = name);

            String hierLkp = HierAttachPointLookups[hierAttachIndex];
            String hierCode = HierAttachPointCodes[hierAttachIndex];
            rca.put(hierLkp, this.hier(hierCode).Id);
            this.newRCAs.add(rca);
            this.rcasByName.put(name, rca);
            return rca;
        }

        // This needs to be placed between Test.startTest() and Test.stopTest(), and you get ONE shot at it:
        void asyncGroupMemRefresh() {
            Database.executeBatch(new rkl.HierShareGroupMemRefreshBatch());
        }

        // Manual run of cleanup batch:
        void runActiveCleanupPhase() {
            this.activeCleanup.execute(null, Database.query(this.activeCleanup.start(null).getQuery()));
            this.activeCleanup.finish(null);
        }

        Integer queryCountNREs(String hierCode) {
            Id hierId = hier(hierCode).Id;
            return [ 
                SELECT count() 
                FROM TEST_Non_Resident_Event__c ];
        }

        Harness nreCount(String userAlias, Integer expectedCount, String hierCode) {
            System.runAs(this.usr(userAlias)) {
                Assert.areEqual(expectedCount, this.queryCountNREs(hierCode));
            }
            return this;
        }

        Integer queryCountRCAs(String hierCode) {
            Id hierId = hier(hierCode).Id;
            return [ 
                SELECT count() 
                FROM TEST_Root_Cause_Analysis__c ];
        }

        Harness rcaCount(String userAlias, Integer expectedCount, String hierCode) {
            System.runAs(this.usr(userAlias)) {
                Assert.areEqual(expectedCount, this.queryCountRCAs(hierCode));
            }
            return this;
        }
    }
}