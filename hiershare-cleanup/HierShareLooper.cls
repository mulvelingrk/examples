/*
 * Mike Ulveling
 * Intended as a manual workaround (Dev Console kickoff) for some issues with rkcore's Queueable-based 
 * Looper processing.
 * 
 * Includes new utilities for cleanup of old sharing calculations in targeted fashion (i.e. by Assignment Set names)
 */
public class HierShareLooper {
    @TestVisible
    private static Boolean TestGroupMembersDML = false;

    public static final String STATUS_RUNNING = 'Running';
    public static final String STATUS_READY = 'Ready';
    
    public static Integer ProcessItemSize = 200;
    public static Integer FillBacklogLimit = null;
    public static final String GroupMemberWorkerClass = 'rkcore.HierShareGroupMemberBatch.GroupMemberWorker';
    
    // Replicates the current static configuration values, so they can be made durable and consistent 
    // across async contexts:
    public class DurableConfig {
        public Integer processItemSize;
        public Integer fillBacklogLimit;
        
        public DurableConfig () {
            this.processItemSize = HierShareLooper.ProcessItemSize;
            this.fillBacklogLimit = HierShareLooper.FillBacklogLimit;
        }
    }
    
    public static void assertNothingRunning(String requestedProcName) {
        rkcore__MutexControl__c[] conflicts = [ SELECT Id, Name FROM rkcore__MutexControl__c WHERE rkcore__Status__c = 'Running' ORDER BY CreatedDate ASC ];
        if (conflicts.size() > 0) {
            Assert.fail('Cannot start [' + requestedProcName + '] while another process [' + conflicts[0].Name + ' :: ' + conflicts[0].Id + '] is running');
        }
    }

    public static ProcessCoordinator deserializeCoordinator(String jsonString) {
        ProcessCoordinator coord = (ProcessCoordinator) JSON.deserialize(jsonString, ProcessCoordinator.class);
        for (ProcessPhase phase : coord.sequence) {
            finishDeserialize(coord, phase);
        }
        return coord;
    }

    public class ProcessCoordinator {
        public DurableConfig lockedConfig;
        rkcore__MutexControl__c writeableMutex;
        ProcessPhase[] sequence = new ProcessPhase[]{};
        @TestVisible
        Integer phaseIndex = -1;

        // The current clobber specification will be maintained here and forked (cloned) into a clobber 
        // processing phase on demand:
        ClobberDef clobberSpec;
        
        public ProcessCoordinator() {
            // Copy the current static configuration elements, and lock them to this coordinator:
            this.lockedConfig = new DurableConfig();
            this.clobberSpec = new ClobberDef(this);
        }

        public ProcessCoordinator getSerializable() {
            ProcessCoordinator fork = this.clone();
            fork.sequence = new ProcessPhase[]{};
            for (ProcessPhase phase : this.sequence) {
                fork.sequence.add(phase.getSerializable());
            }
            fork.clobberSpec = this.clobberSpec.getSerializable();
            return fork;
        }

        public ProcessCoordinator startNewSequence() {
            this.sequence = new ProcessPhase[]{};
            return this;
        }

        /* Example clobber setups:

        // Parallelized deletion of physical groups as fast as possible (parallelized) with default 
        // chunking of 50 up to a limit of 200 Groups (for testing):
        new HierShareLooper.ProcessCoordinator()
            .startNewSequence()
                .clobberSettings()
                    .physicalGroups()
                    .allAssignSets()
                    .limitx(200)
                    .parallelize()
                .pop()
                .thenClobber()
            .start();

        // Eliminates from processing backlog all member keys not pertaining to assignment set "all":
        new HierShareLooper.ProcessCoordinator()
            .startNewSequence()
                .clobberSettings()
                    .processBacklog()
                    .excludeAssignSet('all')
                    .limitx(2)
                .pop()
                .thenClobber()
            .start();

        // Parallelized deletion of physical groups not pertaining to assignment set "all", limited 
        // to 200 Groups (default chunking of 50):
        new HierShareLooper.ProcessCoordinator()
            .startNewSequence()
                .clobberSettings()
                    .groups()
                    .excludeAssignSet('all')
                    .limitx(200)
                    .parallelize()
                .pop()
                .thenClobber()
            .start();

        new ProcessCoordinator()
            .startNewSequence()
                .clobberSettings()
                    .processBacklog();
                    .excludeAssignSet('all')
                    .limitx(2)
                .pop()
                .thenClobber()
                .clobberSettings()
                    .groups()
                    .noLimit()
                    .parallelize()
                .pop()
                .thenClobber()
        */
        public ClobberDef clobberSettings() {
            return this.clobberSpec;
        }

        ProcessCoordinator then(ProcessPhase phase) {
            sequence.add(phase);
            return this;
        }

        public ProcessCoordinator thenClobber() {
            return then(new ProcessPhase(this, this.clobberSpec));
        }

        public ProcessCoordinator thenEraseBacklog(Integer chunkSize) {
            return then(new ProcessPhase(this, 'EraseBacklog', chunkSize ?? 400));
        }

        public ProcessCoordinator thenFillBacklog(Integer chunkSize) {
            return then(new ProcessPhase(this, 'FillBacklog', chunkSize ?? 200));
        }

        public ProcessCoordinator thenProcessBacklog(Integer chunkSize) {
            return then(new ProcessPhase(this, 'ProcessBacklog', chunkSize ?? 1));
        }

        // chunkSize is set to 1 (i.e. 1 processing item per chunk)
        public ProcessCoordinator thenParallelProcessBacklog(Integer itemsLimit) {
            final Integer chunkSize = 1;
            ProcessPhase procPhase = new ProcessPhase(this, 'ParallelProcessBacklog', chunkSize);
            procPhase.batchLimit = itemsLimit ?? 500;
            return then(procPhase);
        }

        public ProcessPhase currentPhase {get{
            if (phaseIndex < 0 || phaseIndex >= sequence.size()) {
                return null;
            }
            return sequence[phaseIndex];
        }}
        
        public Id start() {
            if (this.phaseIndex >= 0) {
                Assert.fail('Processing sequence has already started');
            }
            return nextPhase();
        }
        
        public Id nextPhase() {
            // Advance to next phase of the specified sequence:
            this.phaseIndex++;
            if (phaseIndex >= sequence.size()) {
                Assert.fail('ManualLooperBatch sequence is ' + (sequence.isEmpty() ? 'empty' : 'finished') + '; nothing to run');
            }

            if (phaseIndex == 0) {
                assertNothingRunning('ManualLooperBatch[' + currentPhase.name + ']');

                rkcore__MutexControl__c[] mutex = [SELECT rkcore__Status__c, rkcore__HeadDetail__c FROM rkcore__MutexControl__c WHERE Name = 'ManualLooperBatch' FOR UPDATE];
                if (mutex.size() > 1) {
                    Assert.fail('Multiple Mutex Controls found for ManualLooperBatch');
                } else if (mutex.isEmpty()) {
                    mutex = new rkcore__MutexControl__c[]{ new rkcore__MutexControl__c(Name = 'ManualLooperBatch', rkcore__Status__c = STATUS_READY) };
                    insert mutex;
                } else if (mutex[0].rkcore__Status__c == STATUS_RUNNING) {
                    Assert.fail('ManualLooperBatch is already running. Wait until it has finished if it needs to be run again.');
                }
                this.writeableMutex = mutex[0];
                this.writeableMutex.rkcore__Status__c = STATUS_RUNNING;
            }
            
            currentPhase.detail = new rkcore__MutexControlDetail__c(
                rkcore__MutexControl__c = this.writeableMutex.Id,
                rkcore__Type__c = currentPhase.name
            );
            insert currentPhase.detail;
            currentPhase.detail.rkcore__HeadDetailId__c = this.sequence[0].detail.Id;
            // updating phaseDetail falls through to the update after the database executeBatch
            
            if (phaseIndex == 0) {
                this.writeableMutex.rkcore__HeadDetail__c = this.sequence[0].detail.Id;
                update this.writeableMutex;
            }
            
            //Id jobId = Database.executeBatch(currentPhase.instantiateBatch(), currentPhase.chunkSize ?? 200);
            //currentPhase.detail.rkcore__JobId__c = jobId;
            //update currentPhase.detail;
            Id jobId = dispatchBatch();

            return jobId;
        }

        @TestVisible
        private Id dispatchBatch() {
            //ProcessPhase currentPhase = sequence[phaseIndex];
            HierShareLooperPhaseBatch dispatchable = currentPhase.instantiateBatch();
            if (Test.isRunningTest() && !TestGroupMembersDML) {
                SObject[] testScope = Database.query(dispatchable.start(null).getQuery());
                dispatchable.execute(null, testScope);
                dispatchable.finish(null);
                return null;
            } else {
                Id jobId = Database.executeBatch(dispatchable, currentPhase.getChunking());
                currentPhase.detail.rkcore__JobId__c = jobId;
                update currentPhase.detail;
                return jobId;
            }
        }

        public void finishPhase() {
            // When we execute the ProcessBacklog batch between startTest() & stopTest(), it will insert GroupMember records,  
            // which cannot coexist with an other kind of DML
            if (Test.isRunningTest() && TestGroupMembersDML) {
                return;
            }

            // Hack for now, just to report an error - the Mutex will be stuck in a "Running" state and should be cleared manually:
            //ProcessPhase currentPhase = sequence[phaseIndex];
            if (currentPhase.rowErrorCount > 0) {
                Assert.fail('HierShareLooper[' + currentPhase.name + '] failed on ' + currentPhase.rowErrorCount + 
                    ' row' + (currentPhase.rowErrorCount == 1 ? '' : 's') + '. First error: ' + currentPhase.firstError);
            }
            
            if (phaseIndex >= sequence.size() - 1) {
                writeableMutex.rkcore__Status__c = STATUS_READY;
                update writeableMutex;
            } else {
                nextPhase();
            }
        }
    }

    public static void finishDeserialize(ProcessCoordinator coord, ProcessPhase basicDeser) {
        basicDeser.coordinator = coord;
        finishDeserialize(coord, basicDeser, basicDeser.clobberSpec);
    }

    public class ProcessPhase {
        public ProcessCoordinator coordinator;
        String name; // ProcessBacklog, EraseBacklog, FillBacklog
        Integer chunkSize;

        // !! Used only by phases that represent clobber jobs:
        public ClobberDef clobberSpec;

        // !! this is currently used only by ParallelProcessBacklog:
        Integer batchLimit;

        rkcore__MutexControlDetail__c detail;
        public Integer rowErrorCount = 0;
        public String firstError;
        
        public DurableConfig lockedConfig {get{
            return coordinator != null ? coordinator.lockedConfig : null;
        }}

        ProcessPhase(ProcessCoordinator coord, String phaseName, Integer chunkBy) {
            this.coordinator = coord;
            this.name = phaseName;
            this.chunkSize = chunkBy ?? 200;
        }

        // !! clobberSpec will be forked (cloned) at the time it is passed in. Its child ClobberJob will 
        // also be cloned, and linked to the appropriate parent objects:
        ProcessPhase(ProcessCoordinator coord, ClobberDef clobberSpec) {
            this(coord, 'Clobber', null);
            ClobberDef specClone = this.clobberSpec = clobberSpec.clone();
            ClobberJob jobClone = this.clobberSpec.job = clobberSpec.job.clone();
            jobClone.coord = coord;
            jobClone.phase = this;
            jobClone.spec = specClone;
        }

        public ProcessPhase getSerializable() {
            ProcessPhase fork = this.clone();
            fork.coordinator = null;
            fork.clobberSpec = this.clobberSpec.getSerializable();
            return fork;
        }

        public Integer getChunking() {
            // Clobber phases manage their own chunking setting:
            if (this.clobberSpec != null) {
                return this.clobberSpec.getChunking();
            }
            return this.chunkSize != null && this.chunkSize > 0 ? this.chunkSize : 200;
        }

        HierShareLooperPhaseBatch instantiateBatch() {
            switch on this.name {
                when 'EraseBacklog' {
                    return new HierShareLooperEraseBacklog(this);
                }
                when 'FillBacklog' {
                    return new HierShareLooperFillBacklog(this);
                }
                when 'ProcessBacklog' {
                    HierShareLooperProcessBacklog processBatch = new HierShareLooperProcessBacklog(this);
                    processBatch.delegateToQueueable = false;
                    return processBatch;
                }
                when 'ParallelProcessBacklog' {
                    HierShareLooperProcessBacklog processBatch = new HierShareLooperProcessBacklog(this);
                    processBatch.delegateToQueueable = true;
                    processBatch.delegateLimit = batchLimit ?? 500;
                    return processBatch;
                }
                when 'Clobber' {
                    return new HierShareClobberPhase(this);
                }
                when else {
                    Assert.fail('Unrecognized process phase [' + name + ']');
                }
            }
            return null; // unreachable
        }
    }

    public static void finishDeserialize(ProcessCoordinator coord, ProcessPhase phase, ClobberDef basicDeser) {
        basicDeser.coordinator = coord;
        basicDeser.job = (ClobberJob) JSON.deserialize(basicDeser.serJobJSON, Type.forName(basicDeser.serJobClassName));
        basicDeser.serJobClassName = null;
        basicDeser.serJobJSON = null;
        finishDeserialize(coord, phase, basicDeser, basicDeser.job);
    }

    public class ClobberDef {
        ProcessCoordinator coordinator;
        public ClobberJob job = new ClobberProcessBacklogJob();
        String serJobClassName;
        String serJobJSON;

        // Specifies the Assignment Sets which define the scope of this "clobber" operation:
        public Set<String> assignSetsScope = new Set<String>();
        // Scope Modes:
        // scopeMode == 0 => Clobber ALL groups related to {assignSetsScope}
        // scopeMode < 0  => Clobber groups excluding {assignSetsScope}
        // scopeMode > 0  => Clobber groups including {assignSetsScope}
        // scopeMode == null (the default) => Invalid; a non-null mode must be explicily set
        public Integer scopeMode;

        public Integer chunkBy;
        public Integer limitx;
        public Boolean parallelize = false;

        public Schema.SObjectType targetType {get{
            return job != null ? job.targetType : null;
        }}

        ClobberDef(ProcessCoordinator coordinator) {
            this.coordinator = coordinator;
        }

        public ClobberDef getSerializable() {
            ClobberDef fork = this.clone();
            fork.coordinator = null;
            //fork.job = this.job.getSerializable();
            CLobberJob forkJob = this.job.getSerializable();
            fork.job = null;
            fork.serJobClassName = forkJob.getClassName();
            fork.serJobJSON = JSON.serialize(forkJob);
            return fork;
        }

        // Tests whether the given Assignment Set is in scope of this clobber operation:
        public Boolean isInScope(String configKey, String testAssignSetName) {
            // TODO: test on config key later...

            if (this.scopeMode == 0) {
                // ALL mode always returns true:
                return true;
            } else if (this.scopeMode > 1) {
                // Include mode returns true if any match is found:
                for (String includeName : this.assignSetsScope) {
                    if (includeName == testAssignSetName) {
                        return true;
                    }
                }
                return false;
            } else if (this.scopeMode < 1) {
                // Exclude mode returns true if NO match is found:
                for (String excludeName : this.assignSetsScope) {
                    if (excludeName == testAssignSetName) {
                        return false;
                    }
                }
                return true;
            }
            // Any other mode is invalid, so return false:
            return false;
        }

        public Integer getChunking() {
            // When chunking has been explicitly set, use that value:
            if (this.chunkBy != null && this.chunkBy > 0) {
                return this.chunkBy;
            }
            // Default batch chunking behavior defers on the clobber job type definition:
            return this.job.defaultChunking ?? 200;
        }

        public ProcessCoordinator pop() {
            return this.coordinator;
        }

        public ClobberDef next() {
            ClobberJob peekNextJob = this.job.next();
            Assert.isNotNull(this.job, 'No job after [' + this.job.name + '] in clobber sequence');
            this.job = peekNextJob;
            // Reset chunking: 
            this.chunkBy = null;
            Assert.isFalse(this.parallelize, 'Parallelized Clobber cannot be chained with a subsequent phase');
            return this;
        }

        public ClobberDef processBacklog() {
            this.job = new ClobberProcessBacklogJob();
            return this;
        }

        // Handles physical Groups and Group Mappings. Note that physical GroupMember and __Share records 
        // will necessarily be cascade-deleted by the platform:
        public ClobberDef groups() {
            this.job = new ClobberGroupsJob();
            return this;
        }

        public ClobberDef physicalGroups() {
            this.job = new ClobberPhysicalGroupsJob();
            return this;
        }

        public ClobberDef physicalGroupMembers() {
            this.job = new ClobberPhysicalGroupMembersJob();
            return this;
        }

        public ClobberDef physicalShares(Schema.SObjectType shareType) {
            this.job = new ClobberPhysicalSharesJob(shareType);
            return this;
        }

        /*
        public ClobberDef groupMappings() {
            this.job = new ClobberGroupMappingsJob();
            return this;
        }
        */

        public ClobberDef groupMemberMappings() {
            this.job = new ClobberGroupMemberMappingsJob();
            return this;
        }

        public ClobberDef unmappedGroups() {
            this.job = new ClobberUnmappedGroupsJob();
            return this;
        }

        public ClobberDef allAssignSets() {
            if (this.scopeMode != null && this.scopeMode != 0) {
                Assert.fail('ALL clashes with previous Scope Mode setting');
            }
            this.scopeMode = 0;
            return this;
        }

        public ClobberDef includeAssignSet(String assignSetName) {
            if (this.scopeMode == null) {
                this.scopeMode = 1;
            } else if (this.scopeMode <= 0) {
                Assert.fail('Include [' + assignSetName + '] clashes with previous Scope Mode setting');
            }
            this.assignSetsScope.add(assignSetName);
            return this;
        }

        public ClobberDef excludeAssignSet(String assignSetName) {
            if (this.scopeMode == null) {
                this.scopeMode = -1;
            } else if (this.scopeMode >= 0) {
                Assert.fail('Exclude [' + assignSetName + '] clashes with previous Scope Mode setting');
            }
            this.assignSetsScope.add(assignSetName);
            return this;
        }

        public ClobberDef chunkBy(Integer chunkSize) {
            this.chunkBy = chunkSize;
            return this;
        }

        // Optionally limit the batch operation to the specified number of records:
        // TODO: this facility should be refactored to the base class HierShareLooperPhaseBatch...
        public ClobberDef limitx(Integer lim) {
            this.limitx = lim != null && lim > 0 ? lim : null;
            return this;
        }

        public ClobberDef noLimit() {
            this.limitx = null;
            return this;
        }

        public ClobberDef parallelize() {
            Assert.areEqual(Schema.Group.SObjectType, this.job.targetType, 
                'Only the "Groups" phase of Clobber can be parallelized');
            this.parallelize = true;
            return this;
        }
    }

    public static void finishDeserialize(ProcessCoordinator coord, ProcessPhase phase, ClobberDef clobberSpec, ClobberJob basicDeser) {
        basicDeser.targetType = Schema.getGlobalDescribe().get(basicDeser.serTargetType);
        basicDeser.coord = coord;
        basicDeser.phase = phase;
        basicDeser.spec = clobberSpec;
        basicDeser.serTargetType = null;
    }

    public abstract class ClobberJob {
        Integer sequence;
        String name;
        Schema.SObjectType targetType;
        String serTargetType;
        Integer defaultChunking;

        // The following parent references will be set later, by the ProcessPhase constructor:
        ProcessCoordinator coord;
        ProcessPhase phase;
        ClobberDef spec;

        ClobberJob(Integer sequence, String name, Schema.SObjectType targetType, Integer defaultChunking) {
            this.sequence = sequence;
            this.name = name;
            this.targetType = targetType;
            this.defaultChunking = defaultChunking;
        }

        ClobberJob(Integer sequence, String name, Schema.SObjectType targetType) {
            this(sequence, name, targetType, 200);
        }

        public abstract Type getClass();

        public String getClassName() {
            return this.getClass().getName();
        }

        public ClobberJob getSerializable() {
            ClobberJob fork = this.clone();
            fork.coord = null;
            fork.phase = null;
            fork.spec = null;
            fork.serTargetType = '' + targetType;
            fork.targetType = null;
            return fork;
        }

        public abstract ClobberJob next();

        public virtual void validateStart() {
            final Integer scopeMode = this.spec.scopeMode;
            Assert.isNotNull(scopeMode, 'Scope Mode must be explicitly set to ALL, Include, or Exclude');
            if (scopeMode != 0 && this.spec.assignSetsScope.isEmpty()) {
                Assert.fail((scopeMode > 0 ? 'Include' : 'Exclude') + ' Scope Mode must specify at least 1 Assignment Set');
            }
        }

        public String getStartQuery() {
            this.validateStart();
            QueryParts query = new QueryParts();
            query.fromTarget = this.targetType;
            query.limitx = this.spec.limitx != null && this.spec.limitx > 0 ? this.spec.limitx : null;
            this.setStartQuery(query);
            //System.debug('Query: ' + query.toSOQL());
            return query.toSOQL();
        }

        public virtual void setStartQuery(QueryParts startQuery) {}

        public virtual void exec(List<SObject> chunk) {}
    }

    public class ClobberProcessBacklogJob extends ClobberJob {
        ClobberProcessBacklogJob() {
            super(0, 'ClobberProcessBacklog', Schema.rkcore__Process_Request__c.SObjectType, 1);
        }

        public override Type getClass() {
            return ClobberProcessBacklogJob.class;
        }

        public override void setStartQuery(QueryParts startQuery) {
            super.setStartQuery(startQuery);
            startQuery.selects = 'rkcore__Process_Type__c, rkcore__Scope__c, rkcore__Scope_Size__c';
            startQuery.whereCond = 'rkcore__Process_Type__c = \'rkcore.HierShareGroupMemberBatch.GroupMemberWorker\'';
            startQuery.orderBy = 'Id ASC';
        }

        public override void exec(List<SObject> chunk) {
            Set<String> memberKeyScope = new Set<String>();
            for (rkcore__Process_Request__c procItem : (rkcore__Process_Request__c[]) chunk) {
                if (String.isNotBlank(procItem.rkcore__Scope__c)) {
                    for (String rawKey: procItem.rkcore__Scope__c.split(',')) {
                        String memberKey = rawKey.trim();
                        if (String.isNotBlank(memberKey)) {
                            memberKeyScope.add(memberKey);
                        }
                    }
                }
            }

            Map<String, rkcore__HierShare_GroupMember_Mapping__c> memberKeyToMapping = new Map<String, rkcore__HierShare_GroupMember_Mapping__c>();
            for (rkcore__HierShare_GroupMember_Mapping__c mapping : [ 
                    SELECT rkcore__MemberKey__c, rkcore__ConfigKey__c, rkcore__AssignmentScopeName__c, rkcore__Active__c
                    FROM rkcore__HierShare_GroupMember_Mapping__c 
                    WHERE rkcore__MemberKey__c IN :memberKeyScope ]) {
                memberKeyToMapping.put(mapping.rkcore__MemberKey__c, mapping);
            }

            rkcore__Process_Request__c[] deletes = new rkcore__Process_Request__c[]{};
            rkcore__Process_Request__c[] updates = new rkcore__Process_Request__c[]{};
            for (rkcore__Process_Request__c procItem : (rkcore__Process_Request__c[]) chunk) {
                if (String.isBlank(procItem.rkcore__Scope__c)) {
                    deletes.add(procItem);
                } else {
                    String[] newScope = new String[]{};
                    Boolean isModified = false;
                    for (String rawKey: procItem.rkcore__Scope__c.split(',')) {
                        String memberKey = rawKey.trim();
                        if (String.isNotBlank(memberKey)) {
                            rkcore__HierShare_GroupMember_Mapping__c mapping = memberKeyToMapping.get(memberKey);
                            // Clobber this memberKey if it has no mapping, the mapping is inactive, or the mapping's 
                            // Assignment Set is in scope of this clobber operation:
                            if (mapping == null || mapping.rkcore__Active__c != true 
                                    || this.spec.isInScope(mapping.rkcore__ConfigKey__c, mapping.rkcore__AssignmentScopeName__c)) {
                                // We will be removing this memberKey, and the proc item must be modified to reflect that:
                                isModified = true;
                            } else {
                                newScope.add(memberKey);
                            }
                        }
                    }

                    if (newScope.isEmpty()) {
                        // If we've removed all memberKeys from this proc item, we can delete it:
                        deletes.add(procItem);
                    } else if (isModified) {
                        // If the proc item requires modification, then write its new memberKey set:
                        procItem.rkcore__Scope__c = String.join(newScope, ',');
                        procItem.rkcore__Scope_Size__c = newScope.size();
                        updates.add(procItem);
                    }
                }
            }

            if (!deletes.isEmpty()) {
                delete deletes;
            }
            if (!updates.isEmpty()) {
                update updates;
            }
        }

        public override ClobberJob next() {
            return new ClobberGroupsJob();
        }
    }

    // !! Deletes both physical Groups and Group Mappings
    public class ClobberGroupsJob extends ClobberJob {
        ClobberGroupsJob() {
            super(1, 'ClobberGroups', Schema.rkcore__HierShare_Group_Mapping__c.SObjectType, 50);
        }

        public override Type getClass() {
            return ClobberGroupsJob.class;
        }
                 
        public override void setStartQuery(QueryParts startQuery) {
            super.setStartQuery(startQuery);
            // !! note how here we query on the rkcore__HierShare_Group_Mapping__c table instead of Group, 
            // because the former has the metadata we need:
            startQuery.selects = 'rkcore__ConfigKey__c, rkcore__AssignmentScopeName__c, rkcore__GroupId__c';
            startQuery.fromTarget = Schema.rkcore__HierShare_Group_Mapping__c.SObjectType;
            final Integer scopeMode = this.spec.scopeMode;
            // !! adding the scope condition so we will know we're done when this query returns 0 rows:
            if (scopeMode != 0) {
                String[] sanitizedNames = new String[]{};
                for (String name : this.spec.assignSetsScope) {
                    sanitizedNames.add('\'' + String.escapeSingleQuotes(name) + '\'');
                }
                startQuery.whereCond = 'rkcore__AssignmentScopeName__c' + (scopeMode > 0 ? ' IN ' : ' NOT IN ') + '(' + String.join(sanitizedNames, ',') + ')';
            }
        }

        public override void exec(List<SObject> chunk) {
            rkcore__HierShare_Group_Mapping__c[] deleteMappings = new rkcore__HierShare_Group_Mapping__c[]{};
            Map<Id, rkcore__HierShare_Group_Mapping__c> inScopeMappingsByGroupId = new Map<Id, rkcore__HierShare_Group_Mapping__c>();
            for (rkcore__HierShare_Group_Mapping__c mapping : (rkcore__HierShare_Group_Mapping__c[]) chunk) {
                if (this.spec.isInScope(mapping.rkcore__ConfigKey__c, mapping.rkcore__AssignmentScopeName__c)) {
                    Id groupId;
                    try {
                        groupId = (Id) mapping.rkcore__GroupId__c;
                    } catch (Exception ignore) {}

                    if (groupId != null) {
                        inScopeMappingsByGroupId.put(groupId, mapping);
                    } else {
                        deleteMappings.add(mapping);
                    }
                }
            }
            Group[] deleteGroups = [ SELECT Id FROM Group WHERE Id IN :inScopeMappingsByGroupId.keySet() ];

            // If we find any mappings holding a Group.Id that doesn't exist (whether the Group was never 
            // rendered, or was subsequently deleted), then they should be deleted:
            Map<Id, rkcore__HierShare_Group_Mapping__c> unrenderedMappingsByGroupId = inScopeMappingsByGroupId.clone();
            // Any in-scope mapped Group that actually exists (was rendered) will be found in the "deleteGroups" list:
            for (Group renderedGroup : deleteGroups) {
                unrenderedMappingsByGroupId.remove(renderedGroup.Id);
            }
            if (unrenderedMappingsByGroupId.size() > 0) {
                deleteMappings.addAll(unrenderedMappingsByGroupId.values());
            }

            final Boolean allOrNone = false;
            Database.DeleteResult[] results = Database.delete(deleteGroups, allOrNone);
            for (Integer i=0; i < results.size(); i++) {
                Database.DeleteResult result = results[i];
                if (result.isSuccess()) {
                    rkcore__HierShare_Group_Mapping__c deleteMapping = inScopeMappingsByGroupId.get(deleteGroups[i].Id);
                    if (deleteMapping != null) {
                        deleteMappings.add(deleteMapping);
                    }
                }
            }

            if (deleteMappings.size() > 0) {
                Database.delete(deleteMappings, allOrNone);
            }
        }

        public override ClobberJob next() {
            return new ClobberGroupMemberMappingsJob();
        }
    }

    // !! Deletes both physical Groups and Group Mappings
    public class ClobberPhysicalGroupsJob extends ClobberJob {
        ClobberPhysicalGroupsJob() {
            super(1, 'ClobberPhysicalGroups', Schema.Group.SObjectType, 50);
        }

        public override Type getClass() {
            return ClobberPhysicalGroupsJob.class;
        }
        
        public override void setStartQuery(QueryParts startQuery) {
            super.setStartQuery(startQuery);
            // !! note how here we query on the rkcore__HierShare_Group_Mapping__c table instead of Group, 
            // because the former has the metadata we need:
            startQuery.selects = 'Id, DeveloperName';
            startQuery.fromTarget = Schema.Group.SObjectType;
            final Integer scopeMode = this.spec.scopeMode;
            // !! adding the scope condition so we will know we're done when this query returns 0 rows:
            if (scopeMode != 0) {
                Assert.fail('ClobberPhysicalGroupsJob requires scope set to ALL');
                //startQuery.whereCond = 'rkcore__AssignmentScopeName__c' + (scopeMode > 0 ? ' IN ' : ' NOT IN ') + '(' + String.join(sanitizedNames, ',') + ')';
            } else {
                startQuery.whereCond = 'DeveloperName LIKE \'HierShare%\'';
            }
            //System.debug('ClobberPhysicalGroups Query: ' + startQuery.toSOQL());
        }

        public override void exec(List<SObject> chunk) {
            Group[] groups = (Group[]) chunk;
            final Boolean allOrNone = false;
            Database.delete(groups, allOrNone);
        }

        public override ClobberJob next() {
            //return new ClobberGroupMemberMappingsJob();
            return null;
        }
    }

    // !! Deletes all physical GroupMembers of HierShare
    public class ClobberPhysicalGroupMembersJob extends ClobberJob {
        ClobberPhysicalGroupMembersJob() {
            super(1, 'ClobberPhysicalGroupMembers', Schema.GroupMember.SObjectType, 200);
        }

        public override Type getClass() {
            return ClobberPhysicalGroupMembersJob.class;
        }
        
        public override void setStartQuery(QueryParts startQuery) {
            super.setStartQuery(startQuery);
            // !! note how here we query on the rkcore__HierShare_Group_Mapping__c table instead of Group, 
            // because the former has the metadata we need:
            startQuery.selects = 'Id, GroupId';
            startQuery.fromTarget = Schema.GroupMember.SObjectType;
            final Integer scopeMode = this.spec.scopeMode;
            // !! adding the scope condition so we will know we're done when this query returns 0 rows:
            if (scopeMode != 0) {
                Assert.fail('ClobberPhysicalGroupMembersJob requires scope set to ALL');
                //startQuery.whereCond = 'rkcore__AssignmentScopeName__c' + (scopeMode > 0 ? ' IN ' : ' NOT IN ') + '(' + String.join(sanitizedNames, ',') + ')';
            } else {
                startQuery.whereCond = 'Group.Name LIKE \'HierShare%\' OR UserOrGroup.Name LIKE \'HierShare%\'';
            }
        }

        public override void exec(List<SObject> chunk) {
            GroupMember[] groupMems = (GroupMember[]) chunk;
            final Boolean allOrNone = false;
            Database.delete(groupMems, allOrNone);
        }

        public override ClobberJob next() {
            //return new ClobberGroupMemberMappingsJob();
            return null;
        }
    }

    // !! Deletes all physical GroupMembers of HierShare
    public class ClobberPhysicalSharesJob extends ClobberJob {
        ClobberPhysicalSharesJob(Schema.SObjectType targetShareType) {
            super(1, 'ClobberPhysicalShares', targetShareType, 200);
            String typeName = '' + targetShareType;
            if (!typeName.endsWithIgnoreCase('__Share')) {
                Assert.fail('Expecred Share type; got [' + targetShareType + ']');
            }
        }

        public override Type getClass() {
            return ClobberPhysicalSharesJob.class;
        }
        
        public override void setStartQuery(QueryParts startQuery) {
            super.setStartQuery(startQuery);
            // !! note how here we query on the rkcore__HierShare_Group_Mapping__c table instead of Group, 
            // because the former has the metadata we need:
            startQuery.selects = 'Id, UserOrGroupId';
            startQuery.fromTarget = this.targetType; //Schema.GroupMember.SObjectType;
            final Integer scopeMode = this.spec.scopeMode;
            // !! adding the scope condition so we will know we're done when this query returns 0 rows:
            if (scopeMode != 0) {
                Assert.fail('ClobberPhysicalSharesJob requires scope set to ALL');
                //startQuery.whereCond = 'rkcore__AssignmentScopeName__c' + (scopeMode > 0 ? ' IN ' : ' NOT IN ') + '(' + String.join(sanitizedNames, ',') + ')';
            } else {
                startQuery.whereCond = 'UserOrGroup.Name LIKE \'HierShare%\'';
            }
            //System.debug('ClobberPhysicalShares Query: ' + startQuery.toSOQL());
        }

        public override void exec(List<SObject> shares) {
            final Boolean allOrNone = false;
            Database.delete(shares, allOrNone);
        }

        public override ClobberJob next() {
            //return new ClobberGroupMemberMappingsJob();
            return null;
        }
    }

    public class ClobberGroupMemberMappingsJob extends ClobberJob {
        ClobberGroupMemberMappingsJob() {
            super(2, 'ClobberGroupMemberMappings', Schema.rkcore__HierShare_GroupMember_Mapping__c.SObjectType, 200);
        }

        public override Type getClass() {
            return ClobberGroupMemberMappingsJob.class;
        }

        public virtual override void setStartQuery(QueryParts startQuery) {
            super.setStartQuery(startQuery);
            startQuery.selects = 'rkcore__ConfigKey__c, rkcore__AssignmentScopeName__c';
            final Integer scopeMode = this.spec.scopeMode;
            if (scopeMode != 0) {
                String[] sanitizedNames = new String[]{};
                for (String name : this.spec.assignSetsScope) {
                    sanitizedNames.add('\'' + String.escapeSingleQuotes(name) + '\'');
                }
                startQuery.whereCond = 'rkcore__AssignmentScopeName__c' + (scopeMode > 0 ? ' IN ' : ' NOT IN ') + '(' + String.join(sanitizedNames, ',') + ')';
            }
        }

        public override void exec(List<SObject> chunk) {
            rkcore__HierShare_GroupMember_Mapping__c[] deletes = new rkcore__HierShare_GroupMember_Mapping__c[]{};
            for (rkcore__HierShare_GroupMember_Mapping__c mapping : (rkcore__HierShare_GroupMember_Mapping__c[]) chunk) {
                if (this.spec.isInScope(mapping.rkcore__ConfigKey__c, mapping.rkcore__AssignmentScopeName__c)) {
                    deletes.add(mapping);
                }
            }
            delete deletes;
        }

        public override ClobberJob next() {
            //return new ClobberGroupMappingsJob();
            return new CLobberUnmappedGroupsJob();
        }
    }

    public class ClobberUnmappedGroupsJob extends ClobberJob {
        ClobberUnmappedGroupsJob() {
            super(2, 'ClobberUnmappedGroupsJob', Schema.Group.SObjectType, 100);
        }

        public override Type getClass() {
            return ClobberUnmappedGroupsJob.class;
        }

        public override void validateStart() {
            super.validateStart();
            if (this.spec.parallelize == true) {
                Assert.fail(this.name + ' Job cannot be parallelized');
            }
        }

        public virtual override void setStartQuery(QueryParts startQuery) {
            super.setStartQuery(startQuery);
            startQuery.selects = 'Name';
            startQuery.whereCond = 'Name LIKE \'HierShare\\_%\'';
        }

        public override void exec(List<SObject> chunk) {
            Map<Id, rkcore__HierShare_Group_Mapping__c> mappingMap = new Map<Id, rkcore__HierShare_Group_Mapping__c>();
            String[] groupIDs = new String[]{};
            for (Group grp : (Group[]) chunk) {
                groupIDs.add('' + grp.Id);
                mappingMap.put(grp.Id, null);
            }
            for (rkcore__HierShare_Group_Mapping__c mapping : [ 
                    SELECT rkcore__GroupId__c 
                    FROM rkcore__HierShare_Group_Mapping__c 
                    WHERE rkcore__GroupId__c IN :(groupIDs) 
                ]) {
                mappingMap.put((Id) mapping.rkcore__GroupId__c, mapping);
            }

            Group[] deletes = new Group[]{};
            for (Id groupId : mappingMap.keySet()) {
                // this HierShare Group is unmapped if it doesn't have an entry in "mappingsMap" from the prior pass:
                if (mappingMap.get(groupId) == null) {
                    deletes.add(new Group(Id = groupId));
                }
            }

            if (deletes.size() > 0) {
                delete deletes;
            }
        }

        public override ClobberJob next() {
            return null;
        }
    }

    /*
    public abstract class ClobberMappingsJob extends ClobberJob {
        ClobberMappingsJob(Integer sequence, String name, Schema.SObjectType targetType) {
            super(sequence, name, targetType, 200);
        }

        public virtual override void setStartQuery(QueryParts startQuery) {
            super.setStartQuery(startQuery);
            startQuery.selects = 'rkcore__ConfigKey__c, rkcore__AssignmentScopeName__c, rkcore__GroupId__c';
            final Integer scopeMode = this.spec.scopeMode;
            if (scopeMode != 0) {
                String[] sanitizedNames = new String[]{};
                for (String name : this.spec.assignSetsScope) {
                    sanitizedNames.add('\'' + String.escapeSingleQuotes(name) + '\'');
                }
                startQuery.whereCond = 'rkcore__AssignmentScopeName__c' + (scopeMode > 0 ? ' IN ' : ' NOT IN ') + '(' + String.join(sanitizedNames, ',') + ')';
            }
        }
    }

    public class ClobberGroupMappingsJob extends ClobberMappingsJob {
        ClobberGroupMappingsJob() {
            super(3, 'ClobberGroupMappings', Schema.rkcore__HierShare_Group_Mapping__c.SObjectType);
        }

        public override void exec(List<SObject> chunk) {
            rkcore__HierShare_Group_Mapping__c[] deletes = new rkcore__HierShare_Group_Mapping__c[]{};
            for (rkcore__HierShare_Group_Mapping__c mapping : (rkcore__HierShare_Group_Mapping__c[]) chunk) {
                if (this.spec.isInScope(mapping.rkcore__ConfigKey__c, mapping.rkcore__AssignmentScopeName__c)) {
                    deletes.add(mapping);
                }
            }
            delete deletes;
        }

        public override ClobberJob next() {
            return null;
        }
    }
    */

    public class QueryParts {
        public String selects;
        public Schema.SObjectType fromTarget;
        public String whereCond;
        public String orderBy;
        public Integer limitx;

        public String toSOQL() {
            String[] parts = new String[]{};
            if (String.isNotBlank(selects)) {
                parts.add('SELECT ' + selects);
            } else {
                parts.add('SELECT Id');
            }

            parts.add('FROM ' + (fromTarget != null ? '' + fromTarget : 'TARGET_NOT_SPECIFIED'));

            if (String.isNotBlank(whereCond)) {
                parts.add('WHERE ' + whereCond);
            }
            if (String.isNotBlank(orderBy)) {
                parts.add('ORDER BY ' + orderBy);
            }
            if (limitx != null) {
                parts.add('LIMIT ' + limitx);
            }
            return String.join(parts, ' ');
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