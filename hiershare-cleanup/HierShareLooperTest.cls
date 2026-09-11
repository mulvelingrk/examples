@IsTest
private class HierShareLooperTest {
    
    @IsTest 
    private static void testFillAndProcess() {
        Data data = new Data();

        HierShareLooper.TestGroupMembersDML = false;
        HierShareLooper.ProcessItemSize = 10;
        HierShareLooper.ProcessCoordinator coord = new HierShareLooper.ProcessCoordinator();
        coord.startNewSequence().thenFillBacklog(200).start();

        Integer mappingsCount = [ SELECT count() FROM rkcore__HierShare_GroupMember_Mapping__c ];
        System.assertEquals(19, mappingsCount);

        Integer processItemCount = [ SELECT count() FROM rkcore__Process_Request__c ];
        //System.debug([ SELECT Id, rkcore__Scope_Size__c, rkcore__Process_Type__c FROM rkcore__Process_Request__c ]);
        System.assertEquals(2, processItemCount);

        HierShareLooper.TestGroupMembersDML = true;
        coord = new HierShareLooper.ProcessCoordinator();
        Test.startTest();
        coord.startNewSequence().thenProcessBacklog(2).start();
        Test.stopTest();
        HierShareLooper.TestGroupMembersDML = false;

        Integer groupMemberCount = [ SELECT count() FROM GroupMember WHERE GroupId IN :data.getAllGroupIDs() ];
        System.assertEquals(19, groupMemberCount);
    }

    @IsTest 
    private static void testFillAndErase() {
        Data data = new Data();
        Integer mappingsCount = [ SELECT count() FROM rkcore__HierShare_GroupMember_Mapping__c ];
        System.assertEquals(19, mappingsCount);

        HierShareLooper.TestGroupMembersDML = false;
        HierShareLooper.ProcessItemSize = 10;
        HierShareLooper.ProcessCoordinator coord = new HierShareLooper.ProcessCoordinator();
        coord.startNewSequence().thenFillBacklog(200).start();

        Integer processItemCount = [ SELECT count() FROM rkcore__Process_Request__c ];
        System.assertEquals(2, processItemCount);

        coord = new HierShareLooper.ProcessCoordinator();
        coord.startNewSequence().thenEraseBacklog(200).start();
        processItemCount = [ SELECT count() FROM rkcore__Process_Request__c ];
        System.assertEquals(0, processItemCount);
    }

    @IsTest 
    private static void testFillAndProcessError() {
        Data data = new Data();

        // Manually add a circular reference mapping - this should cause a processing error!
        rkcore__HierShare_GroupMember_Mapping__c circularMapping = data.hierMapping('A', 'A');
        insert circularMapping;
        // !! rkcore triggers will have automatically inserted their own Process_Request records for the above 
        // mappings - delete them for these tests:
        delete [ SELECT Id FROM rkcore__Process_Request__c ];

        Integer mappingsCount = [ SELECT count() FROM rkcore__HierShare_GroupMember_Mapping__c ];
        System.assertEquals(20, mappingsCount);

        HierShareLooper.TestGroupMembersDML = false;
        HierShareLooper.ProcessItemSize = 10;
        HierShareLooper.ProcessCoordinator coord = new HierShareLooper.ProcessCoordinator();
        coord.startNewSequence().thenFillBacklog(200).start();

        Integer processItemCount = [ SELECT count() FROM rkcore__Process_Request__c ];
        System.assertEquals(2, processItemCount);

        HierShareLooper.TestGroupMembersDML = true;
        coord = new HierShareLooper.ProcessCoordinator();
        Test.startTest();
        coord.startNewSequence().thenProcessBacklog(2).start();
        Test.stopTest();
        HierShareLooper.TestGroupMembersDML = false;

        //System.assertEquals(1, coord.currentPhase.rowErrorCount);

        Integer groupMemberCount = [ SELECT count() FROM GroupMember WHERE GroupId IN :data.getAllGroupIDs() ];
        System.assertEquals(19, groupMemberCount);
    }

    @IsTest 
    private static void testFill() {
        HierShareLooper.testFill();
        HierShareClobberPhase.testFill();
        HierShareLooperProcessBacklog.testFill();
    }

    private class Data {
        String[] nodes;
        String[] assignees;
        Map<String, Group> allGroupsMap = new Map<String, Group>();
        Map<String, rkcore__HierShare_GroupMember_Mapping__c> allMappings = new Map<String, rkcore__HierShare_GroupMember_Mapping__c>();

        Data() {
            init();
        }

        Set<Id> getAllGroupIDs() {
            Set<Id> allIDs = new Set<Id>();
            for (Group grp : allGroupsMap.values()) {
                allIDs.add(grp.Id);
            }
            return allIDs;
        }

        virtual void init() {
            this.nodes = 'ABCDEFGHIJ'.split('');
            this.assignees = '0123456789'.split('');
            Group[] allGroups = new Group[]{};
            for (String node : nodes) {
                allGroups.add(new Group(Name = node, DeveloperName = 'HierShare_' + node));
            }
            for (String assignee : assignees) {
                allGroups.add(new Group(Name = assignee, DeveloperName = 'HierShare_' + assignee));
            }
            insert allGroups;
            for (Group grp : allGroups) {
                allGroupsMap.put(grp.Name, grp);
            }

            // Make node "A" the parent of B and C (lvl 2):
            hierMapping('A', 'B');
            hierMapping('A', 'C');
            // Make node "B" the parent of D, E, and F (lvl 3):
            hierMapping('B', 'D');
            hierMapping('B', 'E');
            hierMapping('B', 'F');
            // Make node "C" the parent of G, H, and I (lvl 3):
            hierMapping('C', 'G');
            hierMapping('C', 'H');
            hierMapping('C', 'I');
            // Make node "I" the parent of J (lvl 4):
            hierMapping('I', 'J');

            assignMapping('A', '0');
            assignMapping('B', '1');
            assignMapping('C', '2');
            assignMapping('D', '3');
            assignMapping('E', '4');
            assignMapping('F', '5');
            assignMapping('G', '6');
            assignMapping('H', '7');
            assignMapping('I', '8');
            assignMapping('J', '9');

            insert allMappings.values();

            // !! rkcore triggers will have automatically inserted their own Process_Request records for the above 
            // mappings - delete them for these tests:
            delete [ SELECT Id FROM rkcore__Process_Request__c ];
        }

        rkcore__HierShare_GroupMember_Mapping__c hierMapping(String parentNode, String childNode) {
            Id childGroupId = allGroupsMap.get(childNode).Id;
            Id parentGroupId = allGroupsMap.get(parentNode).Id;
            rkcore__HierShare_GroupMember_Mapping__c mapping = new rkcore__HierShare_GroupMember_Mapping__c(
                // Make the parent node's group a member of its child node's group:
                rkcore__MemberKey__c = '' + childGroupId + parentGroupId, // GroupId + UserOrGroupId
                rkcore__Active__c = true,
                rkcore__Type__c = 'Hierarchy', // 'Hierarchy', 'Assignment'
                rkcore__NodeGroupId__c = childGroupId,
                rkcore__UserOrGroupId__c = null, // 'Assignment' types only
                rkcore__ParentGroupId__c = parentGroupId // 'Hierarchy' types only
            );
            allMappings.put(mapping.rkcore__MemberKey__c, mapping);
            return mapping;
        }

        rkcore__HierShare_GroupMember_Mapping__c assignMapping(String node, String assignee) {
            Id nodeGroupId = allGroupsMap.get(node).Id;
            Id assigneeGroupId = allGroupsMap.get(assignee).Id;
            rkcore__HierShare_GroupMember_Mapping__c mapping = new rkcore__HierShare_GroupMember_Mapping__c(
                // Make the assignee group a member of the target node's group:
                rkcore__MemberKey__c = '' + allGroupsMap.get(node).Id + assigneeGroupId, // GroupId + UserOrGroupId
                rkcore__Active__c = true,
                rkcore__Type__c = 'Assignment', // 'Hierarchy', 'Assignment'
                rkcore__NodeGroupId__c = nodeGroupId,
                rkcore__UserOrGroupId__c = assigneeGroupId
            );
            allMappings.put(mapping.rkcore__MemberKey__c, mapping);
            return mapping;
        }
    }
}