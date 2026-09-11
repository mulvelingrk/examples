# Overview
Here are the steps for performing a FULL cleanup of all HierShare v2 side-effects (sharing & shadow records). The deletion of physical groups is parallelizable, which is of particular import due to how excruciatingly slow these operations are in larger HierShare implementations (> 100K physical Public Groups). Parallelization increases deletion throughput of Groups by a factor of 20x to 50x.
 
# Pre-Requisites
This process requires bespoke Apex classes (my own) to perform the cleanup. We do not have this code in any packaged product. The "source of truth" for these files is this repo (for now), though they probably belong in rkcore package (eventually). These classes must first be bundled in a Change Set and deployed to Prod. HierShareLooperTest should provide adequate test coverage:
HierShareLooper
HierShareLooperEraseBacklog
HierShareLooperFillBacklog
HierShareLooperPhaseBatch
HierShareLooperProcessBacklog
HierShareLooperTest
HierShareClobberPhase

# Step 1
De-activate HierShare v2 via its Process Administration page. We don't want HierShare triggers (and triggered-Flows) actively generating partial HierShare side-effects while cleanup is processing. The goal here is to achieve a "clean slate" before re-activation (if at all).

# Step 2
Parallelized cleanup of physical HierShare Groups (nodes) and by consequence (platform cascade-deletion) their associated GroupMembers (edges). Groups not related to HierShare will not be touched. 

Apex Execute Anonymous (Dev Console) the following code, and wait for it to finish by monitoring Setup > Apex Jobs
!! This step can take several hours to complete for larger orgs. Worst case known scenario is an org with 1.4 million Groups, and that takes ~ 10 - 16 hours even with parallelization. This step can dispatch us to thousands of parallelized Apex Queueable jobs, so the Apex Jobs list will look absolutely chaotic during this time. Most orgs should have ample async job capacity for this processing, and it will not affect User activity in the org.

```java
// Mass-parallelized deletion of ALL HierShare physical groups, with default chunking of 50:
new HierShareLooper.ProcessCoordinator()
    .startNewSequence()
        .clobberSettings()
            .physicalGroups()
            .allAssignSets()
            //.limitx(200)
            .parallelize()
        .pop()
        .thenClobber()
    .start();
```

# Step 3
Cleanup rkcore__HierShare_Group_Mappings__c (Group Mappings) and rkcore__HierShare_GroupMember_Mappings__c (GroupMember Mappings). Since these utilize "soft" or "polymorphic" external ID references to their physical Groups, they are not cascade-deleted by the prior step.

Apex Execute Anonymous (Dev Console) the following code, and wait for it to finish by monitoring Setup > Apex Jobs. This job should run much faster than the prior one.

```java
// Secondary cleanup of all rkcore HierShare shadow objects:
new HierShareLooper.ProcessCoordinator()
    .startNewSequence()
        .clobberSettings()
            .groupMemberMappings()
            .allAssignSets()
            //.limitx(200)
        .pop()
    .thenClobber()
        .clobberSettings()
            .groups()
            .allAssignSets()
            //.limitx(200)
        .pop()
    .thenClobber()
    .start();
```
 
# Step 4
Apex Execute Anonymous (Dev Console) the following code. It is "synchronous" and nearly instant (up to 30 seconds) so you do not need to monitor Apex Jobs. 
!! Note this only clears the older "Legacy Looper" backlog. New "Advanced Looper" uses a different Object for its work items queue (TODO).

```
// Clear out dead rkcore HierShare processing backlog:
delete [ select id from rkcore__Process_Request__c ];
```