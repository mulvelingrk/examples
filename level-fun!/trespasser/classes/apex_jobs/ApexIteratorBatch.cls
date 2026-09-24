/*
 * Mike Ulvleing
 *
 * Trying something new here...
 */
public without sharing class ApexIteratorBatch extends ApexBaseBatch
implements Database.Batchable<Object> {
    InternalIterator iter;
    transient Object[] marshalledOut;

    public ApexIteratorBatch(Runtime.Host executor, InternalIterator iter) {
        super(executor);
        this.iter = iter;
    }

    // Serializer.IntrinsicType implementation:
    public ApexIteratorBatch() { }
    public override System.Type getClass() {
        return ApexIteratorBatch.class;
    }
    public override void serFill(Serializer.SerialOut elmtOut) {
        super.serFill(elmtOut);
        elmtOut.ref(iter);
    }
    public override void deserFill(Serializer.SerialIn elmtIn) {
        super.deserFill(elmtIn);
        iter = (InternalIterator) elmtIn.ref();
    }

    public override void cueUp() {
        if (ApexThread.TestRootMaster != null) {
            this.testDeferredId = ApexThread.MockFlexQueueEnqueue(this);
            return;
        }
        // !! Note we fix chunk size at 1 since we're doing our own BatchStep.scope aggregation:
        this.jobId = Database.executeBatch(this, batchSize ?? 100);
    }

    public class SpreadIteratorFn extends Code.InjectedMethod {
        public SpreadIteratorFn(Realm hostRealm) {
            super(hostRealm, 'ApexIteratorBatch.prototype', 'spreadIterator', 
            new String[]{
                'iter', 'marshalled'
            },
            new String[]{
                //'var iter, marshalled;',
                //'console.debug(`Starting ApexIteratorBatch.spreadIterator`);',
                'do {',
                '    let step = iter.next();',
                '    if (step.done) {',
                '        break;',
                '    }',
                '    marshalled.push(step.value);',
                '} while (true);'
            });
        }

        // Serializer.IntrinsicType implementation:
        public SpreadIteratorFn() { }
        public override System.Type getClass() {
            return SpreadIteratorFn.class;
        }

        public override void mapArgs(Types.CallContext ctxt) {
            ApexIteratorBatch batch = (ApexIteratorBatch) ctxt.argv[0];
            // args: (iter, marshalled)
            ctxt.argv = new Object[]{ batch.iter, batch.marshalledOut };
        }
    }

    public Iterable<Object> start(Database.BatchableContext bc) {
        master.deferChaining = true;
        Object jobId = (Object) bc?.getJobId() ?? (Object) jobId ?? (Object) testDeferredId;
        master.onStartAsyncTransaction(ApexThread.ExecutorEvent.BatchStart, executor, jobId);
        // Resolve the initial process for this job:
        this.initial.settleFulfilled(new ApexBaseBatch.ChunkObject(this.executor,
            'start',
            jobId,
            this.index++,
            null
        ));
        this.internalNext = new Promise(executor);
        executor.onStartExec(ApexThread.ExecutorEvent.BatchStart);
        executor.resumeEventProcessing();
        if (iter == null) {
            // If no iterator was passed, this is an error. Reject the Promise and return an empty array. There will be no
            // execute() phase to this Batch process, and finish() will just echo the error:
            this.marshalledOut = new Object[0];
            internalNext.settleRejected(
                Types.mintTypeError(executor.vm, 'ApexIteratorBatch.start', 'No iterator has been specified'));
        } else {
            // Fully traverse the iterator, "spreading" it out to a new array. We use a new Promise.chainNext() to dispatch 
            // our injecting method <SpreadIteratorFn>:
            this.marshalledOut = new Object[0];
            Promise spreadKickoff = new Promise(executor);
            spreadKickoff.chainThen(new SpreadIteratorFn(executor.hostRealm));
            spreadKickoff.resolve(this);
            executor.resumeEventProcessing();
        }
        //executor.onAfterExec(ApexThread.ExecutorEvent.BatchStart);

        // This alternative implementation uses an internal MUnit to "spread" the iterator, instead of the Promise.chainNext
        // approach used above:
        /*
        Object[] iterMarshalled = new Object[0]; // input & output var "marshalled"
        // MUnit: "internal:BatchIterate"
        MUnit unitSpec = MUnit.fromInternal('BatchIterate', new String[]{
                //'var iter, marshalled',
                //'throw "Foo!";',
                //'console.log("Starting iterator next()");',
                'do {',
                '    let step = iter.next();',
                '    if (step.done) {',
                //'        console.log("stepping done")',
                '        break;',
                '    }',
                //'    console.log("step:", step);',
                '    marshalled.push(step.value);',
                '} while (true);'
            })
            .realm(executor.hostRealm)
            .setEvent(ApexThread.ExecutorEvent.BatchIterate)
            .declare(new Map<String, Object>{
                'iter' => iter,
                'marshalled' => iterMarshalled
            });
        Runtime.CompletionRecord result = unitSpec.exec();
        return iterMarshalled;
        */

        master.finalizeTransaction();
        return this.marshalledOut;
    }

    public void execute(Database.BatchableContext bc, Object[] scope) {
        // If a Master terminates unnaturally it will flag {done = true}. Unfortunately, Batch processes will continue to
        // fire their execute() methods - and a final finished() - until done. Therefore, we check here for {done == true} 
        // and return immediately in that case:
        if (master.done == true) {
            // TODO: Review this bypass. Should we log a transaction-level warning?
            return;
        }
        // !! If the next step has nothing in it, then the iterator is exhausted and we have nothing to do in this or any 
        // other execute()'s. In that case, the outstanding (internalNext) Promise will be fulfilled in finish():
        if (scope != null && !scope.isEmpty()) {
            Object jobId = (Object) bc?.getJobId() ?? (Object) jobId ?? (Object) testDeferredId;
            master.onStartAsyncTransaction(ApexThread.ExecutorEvent.BatchExecute, executor, jobId);
            final Integer batchIndex = index - 1;
            internalNext.settleFulfilled(new ApexBaseBatch.ChunkObject(this.executor,
                'execute',
                jobId,
                this.index++,
                scope
            ));
            // Mint next promise for next execute, or finish if no more:
            this.internalNext = new Promise(executor);
            executor.onStartExec(ApexThread.ExecutorEvent.BatchExecute);
            executor.resumeEventProcessing();
            //executor.onAfterExec(ApexThread.ExecutorEvent.BatchExecute);
            master.finalizeTransaction();
        }
    }

    public void finish(Database.BatchableContext bc) {
        master.deferChaining = false;
        // If a Master terminates unnaturally it will flag {done = true}. Unfortunately, Batch processes will continue to
        // fire their execute() methods - and a final finished() - until done. Therefore, we check here for {done == true} 
        // and return immediately in that case:
        if (master.done == true) {
            // TODO: Review this bypass. Should we log a transaction-level warning?
            return;
        }
        Object jobId = (Object) bc?.getJobId() ?? (Object) jobId ?? (Object) testDeferredId;
        master.onStartAsyncTransaction(ApexThread.ExecutorEvent.BatchFinish, executor, jobId);
        internalNext.settleFulfilled(new ApexBaseBatch.ChunkObject(this.executor,
            'finish',
            jobId,
            this.index++,
            null
        ));
        // No more next-promises:
        this.internalNext = null;
        executor.onStartExec(ApexThread.ExecutorEvent.BatchFinish);
        executor.resumeEventProcessing();
        //executor.onAfterExec(ApexThread.ExecutorEvent.BatchFinish);
        master.finalizeTransaction();
        //System.debug('END FINISH: ' + executor.completionResult.renderOutput());
    }

    public override void exec(Object jobId) {
        Types.raiseInternal('ApexIteratorBatch.exec() should not be used');
    }
}