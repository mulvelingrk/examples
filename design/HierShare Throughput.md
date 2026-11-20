
# AsyncLoop Message Structure
Run the following query to see outstanding AsyncLoop Messages for HierShare's Physical GroupMember calculations:

```sql
select rkcore__Process_Key__c, rkcore__Status__c, rkcore__Worker_Strategy__c, rkcore__Scope__c from rkcore__AsyncLoop_Message__c where rkcore__Process_Key__c LIKE 'HierShareGroupMembers' AND rkcore__Status__c = 'New'
```

Example rkcore__AsyncLoop_Message__c.rkcore__Scope__c Payload, showing 100 Work Items delimited by comma.
Each Work Item represents a single physical GroupMember by the form: `{parentGroupId}{assigneeUserOrGroupId}`
```plain-text
00GjH000000GHWpUAO005TV000001soaXYAQ,00GjH000000GHWpUAO005TV000001spumYAA,00GjH000000GHWpUAO005TV000001sRmOYAU,00GjH000000GHWpUAO005TV000001sSgPYAU,00GjH000000GHWpUAO005TV000001sVUUYA2,00GjH000000GHWpUAO005TV000001sW1CYAU,00GjH000000GHWpUAO005TV000001sYsUYAU,00GjH000000GHWpUAO005TV000001sz2sYAA,00GjH000000GHWpUAO005TV000001t0lIYAQ,00GjH000000GHWpUAO005TV000001t1vrYAA,00GjH000000GHWpUAO005TV000001t7LYYAY,00GjH000000GHWpUAO005TV000002FCxWYAW,00GjH000000GHWpUAO005TV000002FNBFYA4,00GjH000000GHWpUAO005TV000002PgHRYA0,00GjH000000GHWpUAO005TV000002WTPKYA4,00GjH000000GHWpUAO005TV000002x686YAA,00GjH000000GHWpUAO005TV000002x687YAA,00GjH000000GHWpUAO005TV000003gSUwYAM,00GjH000000GHWpUAO005TV000003L04mYAC,00GjH000000GHWpUAO005TV000003L04PYAS,00GjH000000GHWpUAO005TV000003nVnAYAU,00GjH000000GHWpUAO005TV000003rdNRYAY,00GjH000000GHWpUAO005TV000003u3VJYAY,00GjH000000GHWpUAO005TV000003VJbuYAG,00GjH000000GHWpUAO005TV000003zVVOYA2,00GjH000000GHWpUAO005TV000003zVVXYA2,00GjH000000GHWpUAO005TV000004afDkYAI,00GjH000000GHWpUAO005TV000004B05BYAS,00GjH000000GHWpUAO005TV00000587UrYAI,00GjH000000GHWpUAO005TV000006AOsTYAW,00GjH000000GHWpUAO005TV000006BsbfYAC,00GjH000000GHWpUAO005TV000006KXt2YAG,00GjH000000GHWpUAO005TV000006OPcRYAW,00GjH000000GHWpUAO005TV000007r1mnYAA,00GjH000000GHwPUAW005TV000001sAzwYAE,00GjH000000GHwPUAW005TV000001shCLYAY,00GjH000000GHwPUAW005TV000001sSGkYAM,00GjH000000GHwPUAW005TV000002FH98YAG,00GjH000000GHwPUAW005TV000003VJRhYAO,00GjH000000GHwPUAW005TV000005DTWFYA4,00GjH000000GHwPUAW005TV000005DTWLYA4,00GjH000000GHWRUA4005TV000001smNWYAY,00GjH000000GHwrUAG005TV000001spzZYAQ,00GjH000000GHwrUAG005TV000001sWX4YAM,00GjH000000GHwrUAG005TV000001sYgsYAE,00GjH000000GHwrUAG005TV000001t2aBYAQ,00GjH000000GHWrUAO005TV000001s49bYAA,00GjH000000GHWrUAO005TV000001s5hGYAQ,00GjH000000GHWrUAO005TV000001s6lsYAA,00GjH000000GHWrUAO005TV000001s8hbYAA,00GjH000000GHWrUAO005TV000001s9InYAI,00GjH000000GHWrUAO005TV000001saFhYAI,00GjH000000GHWrUAO005TV000001sAV1YAM,00GjH000000GHWrUAO005TV000001saxLYAQ,00GjH000000GHWrUAO005TV000001sCwTYAU,00GjH000000GHWrUAO005TV000001sCYZYA2,00GjH000000GHWrUAO005TV000001sDEEYA2,00GjH000000GHWrUAO005TV000001sdiSYAQ,00GjH000000GHWrUAO005TV000001sDWTYA2,00GjH000000GHWrUAO005TV000001sfDFYAY,00GjH000000GHWrUAO005TV000001sfx0YAA,00GjH000000GHWrUAO005TV000001sgBwYAI,00GjH000000GHWrUAO005TV000001sh68YAA,00GjH000000GHWrUAO005TV000001shU8YAI,00GjH000000GHWrUAO005TV000001sibNYAQ,00GjH000000GHWrUAO005TV000001siTrYAI,00GjH000000GHWrUAO005TV000001sjZJYAY,00GjH000000GHWrUAO005TV000001sK4rYAE,00GjH000000GHWrUAO005TV000001sKunYAE,00GjH000000GHWrUAO005TV000001sKZBYA2,00GjH000000GHWrUAO005TV000001sluIYAQ,00GjH000000GHWrUAO005TV000001smASYAY,00GjH000000GHWrUAO005TV000001sMO6YAM,00GjH000000GHWrUAO005TV000001snVCYAY,00GjH000000GHWrUAO005TV000001sO3LYAU,00GjH000000GHWrUAO005TV000001sOi0YAE,00GjH000000GHWrUAO005TV000001spDBYAY,00GjH000000GHWrUAO005TV000001spHxYAI,00GjH000000GHWrUAO005TV000001sPP7YAM,00GjH000000GHWrUAO005TV000001spTRYAY,00GjH000000GHWrUAO005TV000001sPz1YAE,00GjH000000GHWrUAO005TV000001sQ45YAE,00GjH000000GHWrUAO005TV000001sqb7YAA,00GjH000000GHWrUAO005TV000001ss6OYAQ,00GjH000000GHWrUAO005TV000001ss9SYAQ,00GjH000000GHWrUAO005TV000001ssnhYAA,00GjH000000GHWrUAO005TV000001sSVDYA2,00GjH000000GHWrUAO005TV000001sVpzYAE,00GjH000000GHWrUAO005TV000001sw3UYAQ,00GjH000000GHWrUAO005TV000001sw78YAA,00GjH000000GHWrUAO005TV000001sYgvYAE,00GjH000000GHWrUAO005TV000001syJiYAI,00GjH000000GHWrUAO005TV000001t4KCYAY,00GjH000000GHWrUAO005TV000001t5zWYAQ,00GjH000000GHWrUAO005TV000002PR0fYAG,00GjH000000GHWrUAO005TV000003HdhsYAC,00GjH000000GHWrUAO005TV000003imldYAA,00GjH000000GHWrUAO005TV000003ip5AYAQ,00GjH000000GHWrUAO005TV000003L043YAC,00GjH000000GHWrUAO005TV000003L048YAC
```

# x30 (Max) Throughput Strategy
AsyncLoop is my flexible framework for managing & monitoring custom Async Apex processing needs. It allows the definition of any number of custom "Processes":
- Processes are defined as rows in Custom Object `rkcore__AsyncLoop_Process__c`
    - Both packaged (rkcore) and client-specific Process definitions are supported 
- Processes must be uniquely identified by their Process_Key (name)
- Each Process may specify and define 1 or more calculation "Worker Strategies"
    - Each Strategy must be backed by an Apex implementation
- A common Message Queue `rkcore__AsyncLoop_Message__c` is used to submit processing requests to Processes:
    - Messages must address a specific Process by Name: `rkcore__Process_Key__c`
    - Messages must address a target Worker Strategy of that Process: `rkcore__Worker_Strategy__c`
    - Messages may specify a variable number of Work Items: `rkcore__Scope__c`. The correct format & composition of Scope depends on the Worker Strategy. Some strategies (e.g. "Full") do not even use Scope.
- Each Processes operates in its own "Thread", isolated from and in parallel to other Processes.
- A Process's "Main Thread" continually monitors the Message Queue for items addressed to it:
    - Loop:
        - Query pending (New) Messages addressed to the current Process
        - Coalesce & combine multiple pending Messages where possible, subject to "Work Item" limits configured on that Process
        - Process the next (coalesed) Message according to is Worker Strategy, and then mark it as either: Invalid | Success | Failure
        - Break Loop and go into "Standby" mode (terminate Thread) if there are no more Messages to Process
    - Apex Trigger on `rkcore__AsyncLoop_Message__c` publishes "Wake-up" Signals (PlatformEvents) to any addressed Processes it finds in "Standby" mode. This is how we effect "always ON processing" without continuously burning through Async Apex Jobs like crazy.
- Each Process works though its own Messages in strictly sequential / synchronous fashion - no internal parallelization! This is safe, but limits throughput for high volume demands. 
- Processes run in parallel relative to all other Processes
    - You MUST design your Process layout so they are safe to operate in this parallel fashion - e.g. does not elicit lock contentions nor race conditions!
    - If you have any 2 Processes that are NOT safe to run in parallel, you shoud instead combine them and support their disparate processing needs via multiple Worker Strategies.

I have a tenatatively planned enchancement to allow AsyncLoop Processes to each specify (optionally) their own "Thread Multiplier" factor, from 2 - 50.
- Processes must also specify how to derive a "Thread Group Key" from each Work Item
- The Main Process_Key becomes the "Master Routing Thread" at address [0]
    - Master Thread's only job is to take Messages originally addressed to it, and repack & reroute them specifically into its child Threads [1] - [N]
    - Master Thread parses out Work Items from its inbound Messages and uses the "Thread Group Key" specification to repack Work Items under their common "Thread Group Key", which is deterministically hash-mapped into a specific child Thread number [1] - [N]. The newly repacked Messages are addressed to the correct child Thread and inserted (and thereby routed)
    - N=10 Threads results in a maximum theoretical throughput increase of 10x. In practice, it usually works out to 5x - 9x
- We use a hashing algorithm to deterministically map Work Items to Threads. Why? In order to control concurrency (partial serialization) for Work Items that may not be safe to process in parallel. For example: say that processing child records updates a summary field on the parent. If children of a common parent are allowed to process in parallel, this creates lock contentions across the parallel Threads for the common resource: a parent row lock. By hashing on parent ID and deterministically (repeatably) assigning Work Items to a Thread # based on that, we can guarantee Work Items with the same parent *always* process sequentially in the same Thread.  
- Cloned child Processes 1 - N (N being the number of Threads specified) are automatically defined & declared by the framework, when this optional setting N > 1 is detected
    - Need to handle edge cases for N expansion & contraction on existing Processes. What to do with existing in-flight Messages?

If you're a student of Computer Science, you will recognize this as Goku's Kaio-Ken technique. 
The following sections of this document explain how to effect a similar throughput enhancement, without having to wait for the full-blown new feature to be released in a future version of rkcore.

## Step 1: Scripted Support
Run in Developer Console > Execute Anonymous Apex:

```java
// 30x Threads for massive parallelized throughput!
final Integer NUM_THREADS = AsyncLoopMessageRepack.NUM_THREADS; // 30
final String HIERSHARE_PROCESS_KEY = AsyncLoopMessageRepack.HIERSHARE_PROCESS_KEY; // 'HierShareGroupMembers'
// Deactivate HierShare's standard single-threaded AsyncLoop Process: 'HierShareGroupMembers':
rkcore.AsyncLoop.Deactivate(HIERSHARE_PROCESS_KEY);
// Declare multiple parallel AsyncLoop Processes keyed as: `HierShareGroupMembers-{i}` for i in [ 1 - {NUM_THREADS} ]:
final String configJSON = '{' +
'  "noOpSleepThreshold": 2,' +
'  "noOpThrottleMinutes": 0,' +
'  "Partial": {' +
'    "ByMemberKeys": {' +
'      "class": "rkcore.HierShareGroupMemberBatch.AsyncGroupMemberWorker",' +
'      "coalesce": 100' +
'    }' +
'  }' +
'}';
for (Integer i = 1; i <= NUM_THREADS; i++) {
    // e.g. "HierShareGroupMembers-1", "HierShareGroupMembers-2", ...
    rkcore.AsyncLoop.DeclareProcess(HIERSHARE_PROCESS_KEY + '-' + i, configJSON);
}
```

To De-Activate {NUM_THREADS} Threads:
```java
final Integer NUM_THREADS = AsyncLoopMessageRepack.NUM_THREADS; // 30
final String HIERSHARE_PROCESS_KEY = AsyncLoopMessageRepack.HIERSHARE_PROCESS_KEY; // 'HierShareGroupMembers'
for (Integer i = 1; i <= NUM_THREADS; i++) {
    // e.g. "HierShareGroupMembers-1", "HierShareGroupMembers-2", ...
    //rkcore.AsyncLoop.Activate(HIERSHARE_PROCESS_KEY + '-' + i);
    rkcore.AsyncLoop.Dectivate(HIERSHARE_PROCESS_KEY + '-' + i);
}
```

To Re-Activate {NUM_THREADS} Threads:
Note you may need to break this up into chunks of (say) 10 Threads at a time, to stay under Apex SOQL/DML limits:
```java
final Integer NUM_THREADS = AsyncLoopMessageRepack.NUM_THREADS; // 30
final String HIERSHARE_PROCESS_KEY = AsyncLoopMessageRepack.HIERSHARE_PROCESS_KEY; // 'HierShareGroupMembers'
for (Integer i = 1; i <= NUM_THREADS; i++) {
    // e.g. "HierShareGroupMembers-1", "HierShareGroupMembers-2", ...
    //rkcore.AsyncLoop.Activate(HIERSHARE_PROCESS_KEY + '-' + i);
    rkcore.AsyncLoop.Activate(HIERSHARE_PROCESS_KEY + '-' + i);
}
```

## Step 2: New Batch Process: AsyncLoopMessageRepack
- Execute batch on a chunk size of 50 Messages
- 100 Work Items per Message => 5,000 Work Items per Chunk (worst case)
- Re-package Messages:
    - Work items determine parentGropupId: `parentGropupId = {workItem}.substring(0, 18)`
    - Work Items re-grouped (x100) by common `parentGroupId` into new Messages
    - New Messages set rkcore__Process_Key__c: `HIERSHARE_PROCESS_KEY + '-' + (String.valueOf(parentGroupId).hashCode() % NUM_THREADS + 1)`

Batch code:
```java
/*
 * Mike Ulveling
 *
 * High Throughput multi-threaded strategy for HierShareGroupMembers processing. Takes all outstanding AsyncLoop
 * Messages to the standard single-thread "HierShareGroupMembers" process; duplicates, repacks & safely 
 * redistributes them into 30 parallel processes named `HierShareGroupMembers-{i}` for i in 1 ... 30
 */
public with sharing class AsyncLoopMessageRepack implements Database.Batchable<sObject> {
    public static final String HIERSHARE_PROCESS_KEY = 'HierShareGroupMembers';
    public static final Integer NUM_THREADS = 30; // Kaio-Ken x30
    public static final Integer COALESCE = 100;
    
    public Iterable<sObject> start(Database.BatchableContext bc) {
        // Query AsyncLoop Messages targeting HierShare's standard single-thread process:
        return Database.getQueryLocator([ 
            SELECT rkcore__Scope__c 
            FROM rkcore__AsyncLoop_Message__c 
            WHERE rkcore__Process_Key__c = 'HierShareGroupMembers' AND rkcore__Status__c = 'New' 
            ORDER BY CreatedDate ASC, Id ASC ], AccessLevel.SYSTEM_MODE);
    }

    public void execute(Database.BatchableContext bc, sObject[] scope) {
        // Across all message-items in this chunk, regroup by common {parentGroupId}:
        Map<Id, String[]> itemsByParentGroupId = new Map<Id, String[]>();
        for (rkcore__AsyncLoop_Message__c msg : (rkcore__AsyncLoop_Message__c[]) scope) {
            if (String.isBlank(msg.rkcore__Scope__c)) {
                continue;
            }
            for (String item : msg.rkcore__Scope__c.split(',')) {
                item = item?.trim();
                if (String.isBlank(item) || item.length() < 18) {
                    continue;
                }
                Id parentGroupId;
                try {
                    parentGroupId = (Id) item.substring(0, 18);
                } catch (System.Exception invalidId) {
                    // Ignore invalid IDs (should not happen anyways):
                    continue;
                }
                String[] siblingItems = itemsByParentGroupId.get(parentGroupId);
                if (siblingItems == null) {
                    itemsByParentGroupId.put(parentGroupId, siblingItems = new String[0]);
                }
                siblingItems.add(item);
            }
        }
        // Repack the regrouped items into new Messages each targeting the appropriate process "threads":
        rkcore__AsyncLoop_Message__c[] newMessages = new rkcore__AsyncLoop_Message__c[0];
        for (Id parentGroupId : itemsByParentGroupId.keySet()) {
            // Deterministically maps {parentGroupId} to an integer in range: [ 1 - {NUM_THRADS} ] according to the 
            // well-known hashCode() and equals() contract of class String:
            Integer targetThread = pythonMod(String.valueOf(parentGroupId).hashCode(), NUM_THREADS) + 1;
            final String targetProcess = HIERSHARE_PROCESS_KEY + '-' + targetThread;
            String[] originalItems = itemsByParentGroupId.get(parentGroupId);
            String[] repackedItems = new String[0];
            while (originalItems.size() > 0) {
                do {
                    repackedItems.add(originalItems.remove(0));
                    if (originalItems.isEmpty() || repackedItems.size() >= COALESCE) {
                        newMessages.add(new rkcore__AsyncLoop_Message__c(
                            rkcore__Process_Key__c = targetProcess,
                            rkcore__Scope__c = String.join(repackedItems, ','),
                            rkcore__Status__c = 'New',
                            rkcore__Worker_Strategy__c = 'ByMemberKeys'
                        ));
                        repackedItems.clear();
                        break;
                    }
                } while (true);
            }
        }
        insert newMessages;
    }

    public void finish(Database.BatchableContext bc) { } // no-op

    // Needed a USABLE Math modulus function; Apex's Math.mod sucks and does not do what I want: a guaranteed 
    // non-negative result to map a hashCode() result into range [1 to N]. Told AI to give me a basic Java impl 
    // of Python's modulus op. This does what I want:
    public static Integer pythonMod(Integer a, Integer b) {
        if (b == 0) {
            throw new IllegalArgumentException('integer division or modulo by zero');
        }
        // Cast to double before dividing so Math.floor rounds toward -infinity 
        // instead of truncating toward zero like Java's integer division
        Integer floorDiv = (Integer) Math.floor((Double) a / b);
        return a - (b * floorDiv);
    }
}
```

## Kickoff Batch:
```java
Database.executeBatch(new AsyncLoopMessageRepack(), 50);
```

## Step 3: Monitor
Observe the following count erode down to 0. This should hapeen MUCH faster than for HierShare's standard single-thread process (estimated ~ 20x faster):
```sql
select rkcore__Process_Key__c, rkcore__Status__c, rkcore__Worker_Strategy__c, rkcore__Scope__c from rkcore__AsyncLoop_Message__c where rkcore__Process_Key__c LIKE 'HierShareGroupMembers-%' AND rkcore__Status__c = 'New'
```
Also watch for Failures...

## Step 4: Disable Parallel Processing Threads; Re-Activate Standard Single Processing Thread

```java
for (Integer i = 1; i <= AsyncLoopMessageRepack.NUM_THREADS; i++) {
    // e.g. "HierShareGroupMembers-1", "HierShareGroupMembers-2", ...
    rkcore.AsyncLoop.Deactivate(HIERSHARE_PROCESS_KEY + '-' + i, configJSON);
}
rkcore.Activate(HIERSHARE_PROCESS_KEY);
```
