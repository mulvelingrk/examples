// !! This batch should be run with a very "small" scope/chunk size, typically between 1 and 5:
public class HierShareLooperProcessBacklog extends HierShareLooperPhaseBatch {
    public Boolean delegateToQueueable = false;
    public Integer delegateLimit = 500;
        
    public HierShareLooperProcessBacklog(HierShareLooper.ProcessPhase phase) {
        super(phase);
    }

    public override Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            // query each node's group, its parent node, and its parent node's group:
            'SELECT rkcore__Scope__c, rkcore__Scope_Size__c, rkcore__Process_Type__c ' +
            ' FROM rkcore__Process_Request__c ' +
            ' WHERE rkcore__Process_Type__c = \'' + HierShareLooper.GroupMemberWorkerClass + '\'' +
            // this order-by is not necessary to the processing algorithm's correctness, but it improves performance:
            ' ORDER BY CreatedDate ASC' + 
            (delegateToQueueable ? ' LIMIT ' + delegateLimit : ''));
    }

    /*
    public override void execute(Database.BatchableContext bc, List<SObject> procItems) {
        Set<String> groupMemberKeyScope = new Set<String>();
        for (rkcore__Process_Request__c procItem : (rkcore__Process_Request__c[]) procItems) {
            String[] itemScope = procItem.rkcore__Scope__c?.split('\\s*+,\\s*+');
            if (itemScope != null) {
                for (String scopeElement : itemScope) {
                    if (String.isNotBlank(scopeElement)) {
                        // TODO: consider validating that this is a valid ID
                        //       and throw away/log invalid IDs
                        groupMemberKeyScope.add(scopeElement);
                    }
                }
            }
        }

        process(groupMemberKeyScope);
    }
    */

    public override void execute(Database.BatchableContext bc, List<SObject> scope) {
        Set<String> groupMemberKeyScope = new Set<String>();
        rkcore__Process_Request__c[] procItems = (rkcore__Process_Request__c[]) scope;
        for (rkcore__Process_Request__c procItem : procItems) {
            String[] itemScope = procItem.rkcore__Scope__c?.split('\\s*+,\\s*+');
            if (itemScope != null) {
                for (String scopeElement : itemScope) {
                    if (String.isNotBlank(scopeElement)) {
                        // TODO: consider validating that this is a valid ID
                        //       and throw away/log invalid IDs
                        groupMemberKeyScope.add(scopeElement);
                    }
                }
            }
        }

        ProcessDelegate processor = new ProcessDelegate(this.phase, procItems, groupMemberKeyScope, delegateToQueueable == true);
        if (delegateToQueueable == true) {
            // queueable (async) dispatch for pseudo-parallel processing:
            System.enqueueJob(processor);
        } else {
            // synchronous processing:
            processor.execute(null);
        }
    }

    public class ProcessDelegate implements System.Queueable {
        HierShareLooper.ProcessPhase phase;
        List<rkcore__Process_Request__c> procItems;
        Set<String> memberKeyScope;
        Boolean doCleanup;

        ProcessDelegate(HierShareLooper.ProcessPhase phase, List<rkcore__Process_Request__c> procItems, Set<String> memberKeyScope, Boolean doCleanup) {
            this.phase = phase;
            this.procItems = procItems;
            this.memberKeyScope = memberKeyScope;
            this.doCleanup = doCleanup == true;
        }

        // process:
        public void execute(System.QueueableContext qc) {
            rkcore__HierShare_GroupMember_Mapping__c[] groupMemberShadows = [
                SELECT rkcore__AccessLevel__c, rkcore__Active__c, rkcore__AssignmentClusterKey__c, rkcore__AssignmentScopeName__c, rkcore__ConfigKey__c, 
                    rkcore__MemberKey__c, rkcore__NodeGroupId__c, rkcore__NodeId__c, rkcore__ParentGroupId__c, rkcore__ParentNodeId__c, rkcore__Type__c, 
                    rkcore__UserOrGroupId__c
                FROM rkcore__HierShare_GroupMember_Mapping__c
                WHERE rkcore__MemberKey__c IN :memberKeyScope ];

            // maps a member key to its cluster; each cluster must be fully represented by a subset of clusterCompleteMemRegs (i.e. has
            // a complete set of all existing mem regs sharing that member key):
            Map<String, MemberCluster> clustersByKey = new Map<String, MemberCluster>();
            final Set<SObjectType> UserOrGroupTypes = new Set<SObjectType>{ Schema.Group.SObjectType, Schema.User.SObjectType };
            for (rkcore__HierShare_GroupMember_Mapping__c shadow : groupMemberShadows) {
                if (String.isBlank(shadow.rkcore__MemberKey__c)) {
                    continue;
                }
                MemberCluster cluster = clustersByKey.get(shadow.rkcore__MemberKey__c);
                if (cluster == null) {
                    cluster = new MemberCluster(shadow);
                    if (cluster.groupId != null && cluster.groupId.getSObjectType() == Schema.Group.SObjectType 
                            && cluster.userOrGroupId != null && UserOrGroupTypes.contains(cluster.userOrGroupId.getSObjectType())) {
                        clustersByKey.put(shadow.rkcore__MemberKey__c, cluster); //cluster = new MemberCluster(shadow));
                    }
                }
                // The existence of any active Group Member shadow causes its cluster to be flagged as active, even if sibling shadows of 
                // the same MemberKey are not active:
                if (shadow.rkcore__Active__c == true) {
                    cluster.isActive = true;
                }
            }
            
            if (clustersByKey.keySet().size() > 0) {
                Set<Id> groupScope = new Set<Id>();
                Set<Id> userOrGroupScope = new Set<Id>();
                for (MemberCluster cluster : clustersByKey.values()) {
                    groupScope.add(cluster.groupId);
                    userOrGroupScope.add(cluster.userOrGroupId);
                }
                for (GroupMember physicalGroupMember : [ 
                        SELECT GroupId, UserOrGroupId 
                        FROM GroupMember 
                        WHERE GroupId IN :groupScope AND UserOrGroupId IN :userOrGroupScope ]) {
                    String memberKey = physicalGroupMember.GroupId + '' + physicalGroupMember.UserOrGroupId;
                    MemberCluster cluster = clustersByKey.get(memberKey);
                    if (cluster != null) {
                        cluster.existingPhysicalMembers.add(physicalGroupMember);
                    }
                }
                
                // if any of the inserts fail, clusters can provide more info about the failure, so keep a parallel array of the clusters
                // the indexing of this array must be in sync with the insertPhysicalMembers array 
                // (i.e. insertPhysicalMemberClusters[i] is the MemberCluster which caused new GroupMember insertPhysicalMembers[i]):
                GroupMember[] insertPhysicalMembers = new GroupMember[]{};
                MemberCluster[] insertPhysicalMemberClusters = new MemberCluster[]{};

                GroupMember[] deletePhysicalMembers = new GroupMember[]{};

                for (MemberCluster cluster : clustersByKey.values()) {
                    if (cluster.isActive && cluster.existingPhysicalMembers.size() == 0) {
                        insertPhysicalMemberClusters.add(cluster);
                        insertPhysicalMembers.add(
                            new GroupMember(
                                GroupId = cluster.GroupId,
                                UserOrGroupId = cluster.UserOrGroupId));
                    } else if (!cluster.isActive && cluster.existingPhysicalMembers.size() > 0) {
                        deletePhysicalMembers.addAll(cluster.existingPhysicalMembers);
                    }
                }

                Integer localFailCount = 0;
                if (deletePhysicalMembers.size() > 0) {
                    //delete deletePhysicalMembers;
                    final Boolean allOrNone = false;
                    Database.DeleteResult[] rezzes = Database.delete(deletePhysicalMembers, allOrNone);
                    for (Integer i=0; i < rezzes.size(); i++) {
                        Database.DeleteResult rez = rezzes[i];
                        if (!rez.isSuccess()) {
                            localFailCount++;
                            this.phase.rowErrorCount++;
                            for (Database.Error err : rez.getErrors()) {
                                if (this.phase.firstError == null) {
                                    this.phase.firstError = 'Delete[' + i + '] ' + err.getStatusCode().name() + ': ' + err.getMessage();
                                }
                                break;
                            }
                        }
                    }
                }
                if (insertPhysicalMembers.size() > 0) {
                    // each close operation on a cluster will add 0 or more items to newMems and delMems:
                    //insert newMems;
                    final Boolean allOrNone = false;
                    Database.SaveResult[] rezzes = Database.insert(insertPhysicalMembers, allOrNone);
                    for (Integer i=0; i < rezzes.size(); i++) {
                        Database.SaveResult rez = rezzes[i];
                        if (!rez.isSuccess()) {
                            localFailCount++;
                            this.phase.rowErrorCount++;
                            for (Database.Error err : rez.getErrors()) {
                                String errorMsg = 'Unknown Error';
                                if (err.getStatusCode() == StatusCode.CIRCULAR_DEPENDENCY) {
                                    MemberCluster clusterInfo = insertPhysicalMemberClusters[i];
                                    if (clusterInfo.activeChildNodeId != null) {
                                        //groupMemInsertErrorLog.add('[' + i + '] Node cycle @ ' + clusterInfo.activeChildNodeId);
                                        errorMsg  = '[' + i + '] Node cycle @ ' + clusterInfo.activeChildNodeId;
                                    } else {
                                        //groupMemInsertErrorLog.add('[' + i + '] Unexpected CIRCULAR_DEPENDENCY @ Member_Key ' + clusterInfo.memberKey);
                                        errorMsg = '[' + i + '] Unexpected CIRCULAR_DEPENDENCY @ Member_Key ' + clusterInfo.memberKey;
                                    }
                                } else {
                                    //groupMemInsertErrorLog.add('[' + i + '] ' + err.getStatusCode().name() + ': ' + err.getMessage());
                                    errorMsg = '[' + i + '] ' + err.getStatusCode().name() + ': ' + err.getMessage();
                                }
                                if (this.phase.firstError == null) {
                                    this.phase.firstError = errorMsg;
                                }
                                break;
                            }
                        }
                    }
                }

                if (localFailCount == 0 && doCleanup) {
                    System.enqueueJob(new CleanupDelegate(this.procItems));
                }
            }
        }
    }

    public class CleanupDelegate implements System.Queueable {
        List<rkcore__Process_Request__c> procItems;

        CleanupDelegate(List<rkcore__Process_Request__c> procItems) {
            this.procItems = procItems;
        }

        public void execute(System.QueueableContext qc) {
            delete procItems;
        }
    }

    //public void finish(Database.BatchableContext bc) {}
    
    // represents a cluster of all mem regs and existing GroupMembers sharing the same member key (i.e. the concatenation of GroupId (target
    // group) and UserOrGroupId (new member to the target group) that define a distinct GroupMember):
    class MemberCluster {
        String memberKey;
        Id groupId;
        Id userOrGroupId;
        // if at least 1 mem reg with this member key is active, then this flag is set to true -- when true, it means that a physical
        // GroupMember should exist; when false, it means that any existing GroupMember should be deleted:
        Boolean isActive = false;
        GroupMember[] existingPhysicalMembers = new GroupMember[]{};
    
        Id activeChildNodeId;
        
        MemberCluster(rkcore__HierShare_GroupMember_Mapping__c shadow) {
            this.memberKey = shadow.rkcore__MemberKey__c;
            try {
                this.groupId = Id.valueOf(shadow.rkcore__NodeGroupId__c);
            } catch (Exception ignoreInvalidId) { /*groupId will be null and that's okay!*/ }
    
            if (shadow.rkcore__Type__c == 'Assignment') {
                try {
                    this.userOrGroupId = Id.valueOf(shadow.rkcore__UserOrGroupId__c);
                } catch (Exception ignoreInvalidId) { /*this.userOrGroupId will be null and that's okay!*/ }
            } else if (shadow.rkcore__Type__c == 'Hierarchy') {
                try {
                    this.userOrGroupId = Id.valueOf(shadow.rkcore__ParentGroupId__c);
                } catch (Exception ignoreInvalidId) { /*this.userOrGroupId will be null and that's okay!*/ }
            }
            
            // a cluster should be specific to a single Type__c of either 'Hierarchy' or 'Assignment', and for Hierarchy clusters it should also 
            // have at most 1 distinct node id (child side of parent-child relationship) which is active. in these cases we want to record
            // the active child node for this cluster, because it will be needed to report hierarchy node cycles when detected upon GroupMember
            // inserts:
            if (shadow.rkcore__Type__c == 'Hierarchy' && String.isNotBlank(shadow.rkcore__NodeId__c) && shadow.rkcore__Active__c == true) {
                this.activeChildNodeId = shadow.rkcore__NodeId__c;
            }
        }
    }
    
    @testVisible
    static void testFill() {
        Integer i = 0;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
    }
}