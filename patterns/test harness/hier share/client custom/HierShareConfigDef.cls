global class HierShareConfigDef extends rkl.HierShare.ConfigDef {
    
    public static Boolean UseTestHarness = false;

    // NRE's (Non-Resident Events) have been reverted to "standard" relationships logic for now, at 
    // client's request. Change this flag to `true` to engage special logic for NRE's:
    public static Boolean NRE_SpecialLogicEnabled = false;

    // Mike Ulveling
    // Doing this implementation because it's a bit more involved than normal.

    // The custom level logic (ActiveLevels, ExtraneousLevels) ONLY applies to Non-Resident Event (NRE) 
    // and Root Cause Analysis (RCA)! All other Objects will use the standard "all or nothing" setup with
    // default level "1". Furthermore, these Objects (NRE, RCA) both engage the same 4 attachment points 
    // to hierarchy: PrimaryFacility, PrimaryLocation, SecondaryFacility, SecondaryLocation

    // "nre" stands for Object: Non-Resident Event
    // "rca" stands for Object: Root Cause Analysis
    static Map<String, String> DefaultActiveLevels = new Map<String, String>{
        // Basic "standard" level of access for hierarchy nodes and for "simple" child Objects that don't
        // require access subdivided by RecordTypes - i.e. they enact "all or nothing" access congruent
        // to their hierarchy node access:
        'hier' => 'RK_Share_Group_hier__c',

        // The following levels define subdivisions of the NRE and RCA Objects:

        // This level is for NRE RecordTypes that represent phsyical damage, injury, or illness:
        'nre_phys' => 'RK_Share_Group_nre_phys__c',
        // This level is for NRE RecordTypes that represent informational events, like data breaches:
        'nre_info' => 'RK_Share_Group_nre_info__c',
        // This level is for RCA's "Performance Improvement" RecordType: 
        'rca_pi' => 'RK_Share_Group_rca_pi__c',
        // This level is for RCA's "Patient Safety Cause Analysis" RecordType:
        'rca_psca' => 'RK_Share_Group_rca_psca__c'
    };

    // Before the special access logic for NRE and RCA was implemented, this HierShare implementation used 
    // the "default" access level "1" for everything. This access will now be removed and migrated to the 
    // "hier" level:
    static Map<String, String> ExtraneousLevels = new Map<String, String>{
        '1' => 'rkl__RK_Share_Group_1__c'
    };

    private static ParsedLevels ParsedLevelsCache;

    public class ParsedLevels {
        public Map<String, String> activeLevels = new Map<String, String>();
        public Map<String, String> defunctLevels = new Map<String, String>();
    }

    public static ParsedLevels GetParsedLevels() { 
        if (ParsedLevelsCache == null) {
            // The following is for reference if we ever need the HierShare levels to be metadata-driven:
            /*
            ParsedLevelsCache = new ParsedLevels();
            if (LevelsMetadata == null) {
                HierShare_Access_Levels__mdt[] actives = [ 
                    SELECT Active_Level_Mappings__c, Defunct_Level_Mappings__c 
                    FROM HierShare_Access_Levels__mdt 
                    WHERE Active__c = true ]; 
                
                // Only take from HierShare_Access_Levels__mdt is we had exactly ONE row flagged Active:
                if (actives.size() == 1) {
                    LevelsMetadata = actives[0];
                }
            }

            if (String.isNotBlank(LevelsMetadata.Active_Level_Mappings__c)) {
                ParsedLevelsCache.activeLevels = (Map<String, String>) 
                    JSON.deserialize(LevelsMetadata.Active_Level_Mappings__c, Map<String, String>.class);
            } else {
                ParsedLevelsCache.activeLevels = DefaultActiveLevels.clone();
            
            }
            if (String.isNotBlank(LevelsMetadata.Defunct_Level_Mappings__c)) {
                ParsedLevelsCache.defunctLevels = (Map<String, String>) 
                    JSON.deserialize(LevelsMetadata.Defunct_Level_Mappings__c, Map<String, String>.class);
            }
            */
            ParsedLevelsCache = new ParsedLevels();
            ParsedLevelsCache.activeLevels = DefaultActiveLevels.clone();
            ParsedLevelsCache.defunctLevels = ExtraneousLevels.clone();
        }
        return ParsedLevelsCache;
    }

    // Use this method to help ensure we don't grant or allow access levels that aren't currently 
    // "active":
    public static String[] FilterLevels(String[] unfilteredLevels) {
        Set<String> filtered = new Set<String>();
        for (String lvl : unfilteredLevels) {
            if (String.isNotBlank(lvl)) {
                String lvlProper = GetActiveLevelsLcToProper().get(lvl.toLowerCase());
                if (String.isNotBlank(lvlProper)) {
                    filtered.add(lvlProper);
                }
            }
        }
        return filtered.isEmpty() ? null : new List<String>(filtered);
    }

    private static Map<String, String> ActiveLevelsLcToProper;

    public static Map<String, String> GetActiveLevelsLcToProper() {
        if (ActiveLevelsLcToProper == null) {
            ActiveLevelsLcToProper = new Map<String, String>();
            Set<String> activeLevels = HierShareConfigDef.GetParsedLevels().activeLevels.keySet();
            for (String lvl : activeLevels) {
                ActiveLevelsLcToProper.put(lvl.toLowerCase(), lvl);
            }
        }
        return ActiveLevelsLcToProper;
    }

    static rkl.HierShare.Config CachedConfig;
    
    global override rkl.HierShare.Config getConfig() {
        if (CachedConfig != null) {
            return CachedConfig;
        }

        rkl.HierShare.Config config = new rkl.HierShare.Config();
        CachedConfig = config;

        ParsedLevels levels = GetParsedLevels();
        // Active levels as defined by the above map:
        for (String lvl : levels.activeLevels.keySet()) {
            config.level(lvl, levels.activeLevels.get(lvl));
        }
        // Extraneous Level-groups - use HierShareLevelCleanup for sterilization of these Levels:
        // !! Leaving these in for now so a full recalc will REMOVE access to them for all users!
        for (String lvl : levels.defunctLevels.keySet()) {
            config.level(lvl, levels.defunctLevels.get(lvl));
        }

        config
            // An assigned User always gets access to hierarchy nodes and "standard" child Objects 
            // via the "hier" level:
            .grantUserAccessAlways('hier')
            // An assigned User conditionally gets extra access levels to the special-access NRE 
            // and RCA Objects, subdivided by RecordTypes, based on their Profile.Name:
            .grantUserAccess(GrantSpecialAccess.class);

        // RCA's use new "special" relationships logic:
        // Order: PrimaryFacility, PrimaryLocation, SecondaryFacility, SecondaryLocation:
        specialRels(config, '{0}Root_Cause_Analysis__r, {0}Root_Cause_Analysis2__r, {0}Root_Cause_Analysis1__r, {0}Root_Cause_Analysis3__r');
        
        // NRE "special" relationship logic is engaged only when this static flag is set to true:
        final String NRE_Rels = '{0}Non_Resident_Events__r, {0}Non_Resident_Events1__r, {0}Non_Resident_Events2__r, {0}Non_Resident_Events3__r';
        if (NRE_SpecialLogicEnabled == true) {
            specialRels(config, NRE_Rels);
        } else {
            standardRels(config, NRE_Rels);
        }
        
        // Everything left (Patient Events, Employee Events, Patient Fedback, Patient Feedback Review, 
        // Resident Events) needs to use "standard" relationships logic:

        // Order: PrimaryFacility, PrimaryLocation, SecondaryFacility, SecondaryLocation:
        standardRels(config, 'Patient_Events1__r, Patient_Safety_Incidents__r, Patient_Events4__r, Patient_Events__r' 
            // ThirdFacility, ThirdLocation, FourthFacility, FourthLocation:
            + ', Patient_Events2__r, Patient_Events5__r, Patient_Events3__r, Patient_Events6__r');

        standardRels(config, 'Employee_Events1__r, Employee_Events__r, Employee_Events2__r, Employee_Events3__r');
        
        standardRels(config, 'Patient_Feedback1__r, Patient_Satisfaction__r, Patient_Feedback2__r, Patient_Feedback__r' 
            + ', Patient_Feedback3__r, Patient_Feedback4__r, Patient_Feedback5__r, Patient_Feedback6__r');
        
        standardRels(config, 'Resident_Events__r, Resident_Events1__r, Resident_Events2__r, Resident_Events3__r');
               
        return config;

        /* Old logic:
         *
        return new rkl.HierShare.Config()
            // .childRel(new rkl.HierShare.ChildRel('Patient_Events__r').shareReason('SecondaryLocation'))
            .childRel(new rkl.HierShare.ChildRel('Patient_Events1__r').shareReason('PrimaryFacility'))
            .childRel(new rkl.HierShare.ChildRel('Patient_Safety_Incidents__r').shareReason('PrimaryLocation'))
            .childRel(new rkl.HierShare.ChildRel('Patient_Events4__r').shareReason('SecondaryFacility'))
            .childRel(new rkl.HierShare.ChildRel('Patient_Events__r').shareReason('SecondaryLocation'))
            .childRel(new rkl.HierShare.ChildRel('Patient_Events2__r').shareReason('ThirdFacility'))
            .childRel(new rkl.HierShare.ChildRel('Patient_Events5__r').shareReason('ThirdLocation'))
            .childRel(new rkl.HierShare.ChildRel('Patient_Events3__r').shareReason('FourthFacility'))
            .childRel(new rkl.HierShare.ChildRel('Patient_Events6__r').shareReason('FourthLocation'))
            .childRel(new rkl.HierShare.ChildRel('Employee_Events1__r').shareReason('PrimaryFacility'))
            .childRel(new rkl.HierShare.ChildRel('Employee_Events__r').shareReason('PrimaryLocation'))
            .childRel(new rkl.HierShare.ChildRel('Employee_Events2__r').shareReason('SecondaryFacility'))
            .childRel(new rkl.HierShare.ChildRel('Employee_Events3__r').shareReason('SecondaryLocation'))
            .childRel(new rkl.HierShare.ChildRel('Patient_Feedback1__r').shareReason('PrimaryFacility'))
            .childRel(new rkl.HierShare.ChildRel('Patient_Satisfaction__r').shareReason('PrimaryLocation'))
            .childRel(new rkl.HierShare.ChildRel('Patient_Feedback2__r').shareReason('SecondaryFacility'))
            .childRel(new rkl.HierShare.ChildRel('Patient_Feedback__r').shareReason('SecondaryLocation'))
            .childRel(new rkl.HierShare.ChildRel('Patient_Feedback3__r').shareReason('ThirdFacility'))
            .childRel(new rkl.HierShare.ChildRel('Patient_Feedback4__r').shareReason('ThirdLocation'))
            .childRel(new rkl.HierShare.ChildRel('Patient_Feedback5__r').shareReason('FourthFacility'))
            .childRel(new rkl.HierShare.ChildRel('Patient_Feedback6__r').shareReason('FourthLocation'))
            // Ian Ljungquist - SANF - SS - Changed Patient Feedback Review to master-detail with Patient Feedback - RK Case 593749
            //.childRel(new rkl.HierShare.ChildRel('Patient_Feedback_Review__r').shareReason('PrimaryFacility'))
            //.childRel(new rkl.HierShare.ChildRel('Patient_Feedback_Review3__r').shareReason('PrimaryLocation'))
            //.childRel(new rkl.HierShare.ChildRel('Patient_Feedback_Review1__r').shareReason('SecondaryFacility'))
            //.childRel(new rkl.HierShare.ChildRel('Patient_Feedback_Review2__r').shareReason('SecondaryLocation'))
            .childRel(new rkl.HierShare.ChildRel('Root_Cause_Analysis__r').shareReason('PrimaryFacility'))
            .childRel(new rkl.HierShare.ChildRel('Root_Cause_Analysis2__r').shareReason('PrimaryLocation'))
            .childRel(new rkl.HierShare.ChildRel('Root_Cause_Analysis1__r').shareReason('SecondaryFacility'))
            .childRel(new rkl.HierShare.ChildRel('Root_Cause_Analysis3__r').shareReason('SecondaryLocation'))
            .childRel(new rkl.HierShare.ChildRel('Non_Resident_Events__r').shareReason('PrimaryFacility'))
            .childRel(new rkl.HierShare.ChildRel('Non_Resident_Events1__r').shareReason('PrimaryLocation'))
            .childRel(new rkl.HierShare.ChildRel('Non_Resident_Events2__r').shareReason('SecondaryFacility'))
            .childRel(new rkl.HierShare.ChildRel('Non_Resident_Events3__r').shareReason('SecondaryLocation'))
            // Truc Nguyen - SANF - Sanford - Long Term Care Implementation - Hiershare setup for Resident Event
            .childRel(new rkl.HierShare.ChildRel('Resident_Events__r').shareReason('PrimaryFacility'))
            .childRel(new rkl.HierShare.ChildRel('Resident_Events1__r').shareReason('PrimaryLocation'))
            .childRel(new rkl.HierShare.ChildRel('Resident_Events2__r').shareReason('SecondaryFacility'))
            .childRel(new rkl.HierShare.ChildRel('Resident_Events3__r').shareReason('SecondaryLocation'))
            //.childRel(new rkl.HierShare.ChildRel('Root_Cause_Analysis4__r').shareReason('Department'))
        */
    }

    // Defines the canonical ordering for the (up to) eight attachment points of child relationships 
    // to the hierarchy (per child object). Values can be used as Sharing Reasons for their attachment point:
    static final String[] AttachPointsEnum = new String[]{
        'PrimaryFacility', 'PrimaryLocation', 
        'SecondaryFacility', 'SecondaryLocation',
        'ThirdFacility', 'ThirdLocation', 
        'FourthFacility', 'FourthLocation'
    };

    // API Name pattern (close enough):
    static final Pattern TokenPatt = Pattern.compile('(?i)(\\{[0-9]\\})?[a-z][a-z0-9_]*+');

    static String[] getTokens(String expr) {
        final String[] testHarnessPrefix = new String[]{ UseTestHarness == true ? 'TEST_' : '' };
        String[] toks = new String[]{};
        Matcher m = TokenPatt.matcher(expr);
        while (m.find()) {
            String tok = m.group(0);
            // Replace any {0} sub-tokens with test-harness prefix qualifier:
            if (m.group(1) != null) {
                tok = String.format(tok, testHarnessPrefix);
            }
            toks.add(tok);
        }
        return toks;
    }

    static void specialRels(rkl.HierShare.Config config, String childRelsExpr) {
        specialRels(config, getTokens(childRelsExpr));
    }

    static void specialRels(rkl.HierShare.Config config, String[] childRelNames) {
        for (Integer i=0; i < childRelNames.size(); i++) {
            String childRel = childRelNames[i];
            if (i >= AttachPointsEnum.size()) {
                throw new IllegalArgumentException(
                    'Rel[' + childRel + ']: Attachment Points past ' + AttachPointsEnum.size() + ' [' 
                    + AttachPointsEnum[AttachPointsEnum.size() - 1] + '] are not recognized');
            }
            String sharingReason = AttachPointsEnum[i];
            specialRel(config, childRel, sharingReason);
        }
    }

    static void specialRel(rkl.HierShare.Config config, 
            String childRelName, String sharingReason) {
        config.childRel(
            new rkl.HierShare.ChildRel(childRelName)
                .shareReason(sharingReason)
                // NRE and RCA Objects conditionally allow access to levels which match their 
                // RecordType.DeveloperName:
                .allowAccess(AllowSpecialAccess.class));
    }

    static void standardRels(rkl.HierShare.Config config, String childRelsExpr) {
        standardRels(config, getTokens(childRelsExpr));
    }

    static void standardRels(rkl.HierShare.Config config, String[] childRelNames) {
        for (Integer i=0; i < childRelNames.size(); i++) {
            String childRel = childRelNames[i];
            if (i >= AttachPointsEnum.size()) {
                throw new IllegalArgumentException(
                    'Rel[' + childRel + ']: Attachment Points past ' + AttachPointsEnum.size() + ' [' 
                    + AttachPointsEnum[AttachPointsEnum.size() - 1] + '] are not recognized');
            }
            String sharingReason = AttachPointsEnum[i];
            standardRel(config, childRel, sharingReason);
        }
    }

    static void standardRel(rkl.HierShare.Config config, 
            String childRelName, String sharingReason) {
        config.childRel(
            new rkl.HierShare.ChildRel(childRelName)
                .shareReason(sharingReason)    
                .allowAccessAlways('hier'));
    }

    global class GrantSpecialAccess extends rkl.HierShare.ApexCustomAccess {
        global override Map<Id, Object> loadCustomContext(sObject[] userRecords) {
            return new Map<Id, sObject>(Database.query(
                'SELECT Profile.Name FROM User WHERE Id IN :userRecords'));
        }
    
        // An assigned User conditionally gets extra access levels (to Claim__c RecordTypes) based 
        // on their Profile.Name:
        global override String[] getCustomAccessLevels(rkl.HierShare.Config c,
                sObject srcUser, Object customContext) {
            
            switch on ((User) customContext).Profile.Name.toLowerCase() {
                when 'ltc leader rbu', 
                        'ltc executive leaders - rbu', 
                        'ltc quality rbu',
                        'ltc med safety rbu' {
                    return FilterLevels(new String[]{ 'nre_phys', 'rca_pi' });
                }
                when 'ltc environmental health & safety consultant rbu' {
                    return FilterLevels(new String[]{ 'nre_phys' });
                }
                when 'ltc system admin' {
                    return FilterLevels(new String[]{ 'nre_phys', 'nre_info', 'rca_pi', 'rca_psca' });
                }
                when 'ltc/healthcare leader' {
                    return FilterLevels(new String[]{ 'nre_phys', 'nre_info', 'rca_pi' });
                }
            }
            return null;
        }
    }

    global class AllowSpecialAccess extends rkl.HierShare.ApexCustomAccess {
        global override Map<Id, Object> loadCustomContext(sObject[] recs) {
            if (recs == null || recs.isEmpty()) {
                return new Map<Id, sObject>();
            }
            Schema.sObjectType objType = recs[0].getSObjectType();
            return new Map<Id, sObject>(Database.query(
                'SELECT RecordType.DeveloperName FROM ' + objType + ' WHERE Id IN :recs'));
        }
        
        // This method conditionally grants additional Level access by RecordType: 
        global override String[] getCustomAccessLevels(rkl.HierShare.Config c,
                sObject srcRecord, Object customContext) {
            
            sObject customRec = (sObject) customContext;
            Schema.sObjectType objType = customRec.getSObjectType();
            String objPrefix = String.valueOf(objType);
            if (UseTestHarness == true) {
                objPrefix = objPrefix.replaceFirst('(?i)^TEST_', '');
            }
            RecordType recType = (RecordType) customRec.getSObject('RecordType');
            String qualifiedRecTypeLC = 
                (objPrefix + '.' + recType?.DeveloperName)
                    .toLowerCase();

            switch on qualifiedRecTypeLC {
                when 'non_resident_event__c.active_shooter',
                        'non_resident_event__c.evacuation',
                        'non_resident_event__c.fire',
                        'non_resident_event__c.health_hazard',
                        'non_resident_event__c.hostage_taking',
                        'non_resident_event__c.infestation',
                        'non_resident_event__c.natural_disaster',
                        'non_resident_event__c.staff_behavior',
                        'non_resident_event__c.firearms_weapons_bomb_threat',
                        'non_resident_event__c.theft_of_non_resident_property',
                        'non_resident_event__c.utility',
                        'non_resident_event__c.visitor_injury',
                        'non_resident_event__c.flood' {
                    return FilterLevels(new String[]{ 'nre_phys' });
                }
                when 'non_resident_event__c.data_breach',
                        'non_resident_event__c.data_repository',
                        'non_resident_event__c.exit_interview',
                        'non_resident_event__c.police_government_investigation',
                        'non_resident_event__c.government_investigation',
                        'non_resident_event__c.compliance_violations',
                        'non_resident_event__c.identity_theft',
                        'non_resident_event__c.privacy_program_violation',
                        'non_resident_event__c.privacy_concern',
                        'non_resident_event__c.privacy_security',
                        'non_resident_event__c.site_assessments',
                        'non_resident_event__c.proactive_audits',
                        'non_resident_event__c.request_or_question',
                        'non_resident_event__c.risk_assessment',
                        'non_resident_event__c.support_line' {
                    return FilterLevels(new String[]{ 'nre_info' });
                }
                when 'root_cause_analysis__c.ltc_performance_improvement' {
                    return FilterLevels(new String[]{ 'rca_pi' });
                }
                when 'root_cause_analysis__c.patient_safety_cause_analysis' {
                    return FilterLevels(new String[]{ 'rca_psca' });
                }
            }
    
            // If no condition matches, return null (no additional levels are granted access)
            return null;
        }
    }

    // I've had to move this call outside the HierShare_Non_Resident_Event trigger body, because 
    // this Object is so very hard to work with in test contexts. Even the insert of a SINGLE blank 
    // record will cause Apex tests to timeout!
    public static void nonResidentEventTriggerHandler() {
        if (Test.isRunningTest() && UseTestHarness == true) {
            throw new HaltTriggerException('Halting Non-Resident Event insert for Tests');
        }
        rkl.HierShare.childRelationshipTrigger();
    }

    public class HaltTriggerException extends Exception {}
}