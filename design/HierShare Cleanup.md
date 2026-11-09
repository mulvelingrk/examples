# HierShare Cleanup Strategies
Here is my design draft for new HierShare "Cleanup" tooling to improve upon pain-points encountered with the unmanaged "Clobber" scripts I have floating around - which are themselves an improvement over rkcore's built-in "Cleanup" processing (exposed in HierShare's Process Admin UI). The latter is NOT recommended for use, and should be removed from the UI. 

## Philosophy of Approach:
- HierShare artifacts consist of Physical entities plus HierShare-metadata entities a.k.a. "Mappings"
    - Physical: {ChildObject}__Share, GroupMapping, Group
        - These standard objects do NOT contain information about the applicable ConfigKey, AssignmentScope, AccessLevel - because we can't add custom fields!
        - Because of this, Physical entities cannot be _selectively_ deleted (e.g. by AssignmentScope) without their matching Mapping entities
    - Mapping: HierShare_Group_Mapping__c, HierShare_GroupMember_Mapping__c
        - These custom objects DO contain information about the applicable ConfigKey, AssignmentScope, AccessLevel
        - These objects are needed in lieu of custom fields on Physical entities
        - We can selectively delete Mappings -OR- Physical entities matched to Mappings. We cannot selectively delete _unmapped_ Physical entities.
- Physical entities belonging to HierShare may only be identified broadly, by common HierShare naming convention, as follows:
    - Group: Name LIKE 'HierShare\_%' (can also use DeveloperName)
    - GroupMember: Group.Name LIKE 'HierShare\_%' (can also use DeveloperName)
    - {ChildObject}__Share: UserOrGroup.Name LIKE 'HierShare\_%' -OR- ShareReason = {HierShare.Config.shareReason}
        - UserOrGroup is a polymorphic parent relationship, but we are able to query against its Group facet
- Strategy:
    - Start with a scope specification of { ConfigKey, ChildObjects, AssignmentScopes } to select target _Mappings_
    - Delete the selected _Mappings_
    - Delete all Physical HierShare entitities that are now found to be _unmapped_
        - This set includes entities unmapped by the prior step, *plus* any entities that were previously unmapped (orphaned) for any reason. Once unmapped from HierShare, a Physical entity should not exist!
        - The last phase of Physical deletions may be _parallelized_. This throughput gain is especially crucial for Physical Groups, since the platform is _extremely_ slow at their deletion (very complex internal sharing recalculations; sometimes very large cascades). 
            - Without a __JOIN__ or __MERGE__ primitive (e.g. look at MuleSoft's "Scatter and Gather" processor, or Go-routines), we do not have a way to synchronize a next phase / step after a parallelized step. For now, a subsequent step after parallelization must be manually kicked off after monitoring parallelized Apex Jobs for 100% completion. Practically, it's best to arrange processing so only the last step (e.g. Physical Groups deletion) is parallelized, when possible.

## Step 1: ChildObject Shares Cleanup
Generally, it's safest and recommended to first cleanup ChildObject Shares and THEN GroupMembers / Groups as a follow-up step. However, the Shares cleanup step can be skipped in lower-volume orgs, or orgs where the Assignments plus Child-Nodes "fan-out factor" is guaranteed to remain _reasonable_ (~ 10 each Node with no large outliers) across the dataset. If you don't cleanup Shares first, the platform's automatic cascade-deletion can grow too large to handle in a transaction, and this results in one of 2 errors (Query Timeout, Cascade Too Large) along with transaction rollback (no deletions effected).

### Selector Specification
- Specify a ConfigKey (e.g. "Primary" though it needs to support others)
    - Loads Config to determine "current" AssignmentScopes and ChildRelationships (ChildObjects)
- AssignmentScopes selector:
    - Base Scope (choose one):
        - _current_: AssignmentScopes IN the current Config
        - _extraneous_: AssignmentScopes NOT IN the current Config
        - _all_: Union of _current_ and _extraneous_. Like a `*` selector
        - _none_: Combine with Modifiers for surgical selection, e.g. a specific AssignmentSet
    - Modifiers:
        - _include_: Specific (additional) inclusions
        - _exclude_: Specific exclusions (highest priority)
        - _exclude-current_: Excludes all of Config's _current_ AssignmentScopes (highest priority)
        - _none_: Bypass modifier, when unmodified Base Scope is all you need
- ChildObjects selector:
    - Base Scope (choose one):
        - _current_: ChildObjects IN the current Config (via ChildRelationships)
        - _extraneous_: ChildObjects NOT IN the current Config
        - _all_: Union of _current_ and _extraneous_. Like a `*` selector
            - TODO: Research how to progrmatically determine the _all_ ChildObject scope by detecting SharingReasons matching this Config
        - _none_: Combine with Modifiers for surgical selection, e.g. a specific ChildObject
    - Modifiers:
        - _include_: Specific (additional) inclusions
        - _exclude_: Specific exclusions (highest priority)
        - _exclude-current_: Excludes all of Config's _current_ ChildObjects (highest priority)
        - _none_: Bypass modifier, when unmodified Base Scope is all you need
- Unmapped selector:
    - {kill-unmapped}
    - Boolean true/false on whether to delete any _unmapped_ Shares encountered. Default true.
    - TODO: Do we even need this; should we just have `true` implied? Is there ever a scenario we _wouldn't_ want to kill unmapped physical entities?

### Algorithm
- For each ChildObject in-scope:
    - Batch across {ChildObject}__Share WHERE RowCause = {config.shareReason}
        - Optionally _parallelize_ batches (a bit tricky):
            - Batch on Iterable<ChildObject> by 1 => Queueable(Relay) => Batch on {ChildObject}__Share
        - Try to match UserOrGroupId to any HierShare_Group_Mapping__c.rkcore__GroupId__c, matching ConfigKey
            - IF {Mapping exists} AND {Mapping.AssignmentScope is in-scope} THEN
                - Delete the __Share
            - ELSE IF {Mapping does not exist} AND {kill-unmapped} THEN
                - Delete the __Share

### Usage Patterns
1. Cleanup Extraneous and Unmapped Shares
    - Specify ConfigKey 
    - Base Scope: _all_ Modifier: _exclude-current_, for both ChildObjects and AssignmentScopes
    - _kill-unmapped_: true
    - Could be packaged or configured as an RKCron Job for ongoing regular self-cleanup

2. Clobber specific AssignmentScopes, e.g. an AssignmentScope that is no longer needed
    - Specify ConfigKey 
    - ChildObjects Base Scope: _all_ Modifier: _none_
        - Optionally: Base Scope: _current_ Modifier: _none_
    - AssignmentScopes Base Scope: _none_ Modifier: _include_ {specific AssignmentScopes}
    - _kill-unmapped_: true or false (default true recommended)

3. Clobber specific ChildObjects, e.g. a ChildRelationship no longer needed
    - Specify ConfigKey 
    - ChildObjects Base Scope: _none_ Modifier: _include_ {specific AssignmentScopes}
    - AssignmentScopes Base Scope: _all_ Modifier: _none_
    - _kill-unmapped_: true

4. Clobber ALL - Abandon all hope; burn it down to start anew:
    - Specify ConfigKey 
    - Base Scope: _all_ Modifier: _none_, for both ChildObjects and AssignmentScopes
    - _kill-unmapped_: true

## Step 2: Groups & GroupMembers "Mappings-First" Cleanup
This strategy works by first selectively deleting _Mappings_ for each of GroupMembers / Groups, and *then* any Physical GroupMembers / Groups that are presently _unmapped_ (including those recently unmapped by the prior selective deletion!). However, note the 2nd phase is _unselective_ other than its _unmapped_ criteria: it kills all _unmapped_ entities, regardless of their origin ConfigKey or AssignmentScope! GroupMembers are fully processed first (selected Mappings and then _unmapped_), then Groups (again selected Mappings and then _unmapped_). 
Note: If your selection includes currently active GroupMember / Groups in its purview, then active & parallel HierShare recalculations could potentially replace the _Mappings_ during or after Cleanup processing. You must consider whether it is appropriate to first de-Activate HierShare in these cases. 

### Selector Specification
- ConfigKey, AssignmentScopes, and Unmapped selector specification same as "ChildObject Shares Cleanup"
    - No ChildObjects selector needed here
- No ChildObjects specification needed
- {kill-unmapped} is intrinsically true (else this strategy doesn't work; it funnels selected mappings into _unmapped_)
- TODO: Consider the following options:
    - GroupMembers only (no Groups processing)
    - Groups only (no GroupMembers processing)
    - GroupMembers parallelize (only allowed when GroupMembers-only)
        - Can be a useful option if GroupMembers cleanup is taking very long

### Algorithm
- Batch across HierShare_GroupMember_Mapping:
    - !! It's more efficient if in-scope selector logic can be baked into SOQL Query (DatabaseLocator) rather than Apex logic. However the latter is not a severe bottleneck.
    - IF {mapping.AssignmentScope is in-scope} THEN
        - Delete the HierShare_GroupMember_Mapping
- Batch across GroupMember WHERE Group.Name LIKE 'HierShare\_%':
    - Try to match GroupMember.GroupId to any HierShare_GroupMember_Mapping__c.rkcore__NodeGroupId__c, also matching ConfigKey
        - IF {mapping is null} THEN
            - Delete the GroupMember
- Batch across HierShare_Group_Mapping:
    - !! It's more efficient if in-scope selector logic can be baked into SOQL Query (DatabaseLocator) rather than Apex logic. However the latter is not a severe bottleneck.
    - IF {mapping.AssignmentScope is in-scope} THEN
        - Delete the HierShare_Group_Mapping
- Batch across Group WHERE Name LIKE 'HierShare\_%':
    - !! Highly recommneded to _parallelize_ this step. In fact this should probably be forced, not an option.
    - Try to match Group.Id to any HierShare_Group_Mapping__c.rkcore__GroupId__c, also matching ConfigKey
        - IF {mapping is null} THEN
            - Delete the Group

### Usage Patterns
1. Cleanup Extraneous and Unmapped GroupMembers / Groups
    - Specify ConfigKey 
    - AssignmentScopes Base Scope: _all_ Modifier: _exclude-current_
    - Could be packaged or configured as an RKCron Job for ongoing regular self-cleanup

2. Clobber specific AssignmentScopes, e.g. an AssignmentScope that is no longer needed
    - Specify ConfigKey 
    - AssignmentScopes Base Scope: _none_ Modifier: _include_ {specific AssignmentScopes}

3. Clobber ALL - Abandon all hope; burn it down to start anew:
    - Specify ConfigKey 
    - AssignmentScopes Base Scope: _all_ Modifier: _none_

## Groups & GroupMembers "Physical First" Cleanup:

This is how the current "Clobber scripts" work. Is there a valid use case for this that wouldn't be served by "Mappings First" Cleanup above? I sort of like "Mappings First" since we would want to kill unmapped entities in all scnearios, and this (sort of) merges the "selected mapped" and "unmapped" paths into one. 
