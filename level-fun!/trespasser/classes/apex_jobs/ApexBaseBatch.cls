public without sharing abstract class ApexBaseBatch extends ApexThread.Chainable
    implements Database.Stateful {
    // , DynamicProperty.Accessible {
    public static final Integer DEFAULT_BATCH_SIZE = 100;
    
    public Promise internalNext;
    public Integer index = 0;
    //String vanillaSOQL;
    public Integer batchSize = DEFAULT_BATCH_SIZE;

    public BatchObject batchObject;
    public Code.AsyncGeneratorObject asyncIterator;
    public Promise startStep;

    public DynamicProperty.Receivable sizeProp;
    public DynamicProperty.Receivable priorityProp;

    public ApexBaseBatch(Runtime.Host executor) {
        super(executor, null);
        this.internalNext = initial;
        //this.vanillaSOQL = vanillaSOQL;

        // Mint the batchObject for JavaScript interface:
        //this.batchObject = new BatchObject(this);
        this.batchObject = this.mintBatchObject();
        // Compile (statically cached) the [async*] Code Unit we'll use for this batch's asyncIterator:
        Code.InjectedMethod asyncIterFn = new AsyncIteratorFn(executor.hostRealm);
        PObject asyncIteratorPrototype = asyncIterFn.mutablePrototype;
        // We've compiled (statically cached) the "injected" [async*] unit code to a Code.InjectedDispatchable. We can use 
        // that to directly mint a new closure object on demand, supplying any root-level bindings of our choice. {!this} is 
        // the only binding needed for now. We set {!this} to the BatchObject, which serves as apexBatch's JavaScript 
        // interface / API. If additional bindings (e.g. vars) are needed in the future, they can be passed via a Map<String, 
        // Object> to the 2nd parameter, instead of null:
        Code.ClosureObject asyncIteratorClosure = asyncIterFn.mintClosure(
            executor.hostRealm, batchObject, Types.EMPTY_ARGV);
        // Mint the asyncIterator itself - this is what's returned for BatchObject[Symbol.asyncIterator], which enables use 
        // in for await...of loops:
        this.asyncIterator = new Code.AsyncGeneratorObject(asyncIteratorPrototype, asyncIteratorClosure);
        // !! Now it's up to our native ApexThread.PushBatchFn.call() to take this newly minted ApexBaseBatch and dispatch
        // Generators.ApexBatchKickoff to ExprMachine. This EvalGenerator will:
        // - invoke the 1st asyncIterator.asyncNext() step (raises a callInterrupt with Generator for its Start-Execution)
        // - stash the 1st step promise in this.startStep
        // - yield this.batchObject as the final result to PushBatchFn's caller
        // If this constructor is called without a follow-up dispatch of Generators.ApexBatchKickoff, then (startStep) will
        // remain uninitialized (this makes us sad)...

        this.sizeProp = new DynamicProperty.Receivable('size')
            .default(DEFAULT_BATCH_SIZE, Serializer.TYPE_KEY_NUMBER)
            .intRange(1, 1000)
            .nillable(true);
        this.priorityProp = new DynamicProperty.Receivable('priority')
            .default(ApexThread.DEFAULT_CHAINING_PRIORITY, Serializer.TYPE_KEY_NUMBER)
            .nillable(true);
    }

    // Serializer.IntrinsicType implementation:
    public ApexBaseBatch() { }
    public virtual override System.Type getClass() {
        return ApexBaseBatch.class;
    }
    public virtual override void serFill(Serializer.SerialOut elmtOut) {
        super.serFill(elmtOut);
        elmtOut.ref(internalNext);
        elmtOut.int(index);
        elmtOut.int(batchSize);
        elmtOut.ref(batchObject);
        elmtOut.ref(asyncIterator);
        elmtOut.ref(startStep);
        elmtOut.ref(sizeProp);
        elmtOut.ref(priorityProp);
    }
    public virtual override void deserFill(Serializer.SerialIn elmtIn) {
        super.deserFill(elmtIn);
        internalNext = (Promise) elmtIn.ref();
        index = elmtIn.int();
        batchSize = elmtIn.int();
        batchObject = (BatchObject) elmtIn.ref();
        asyncIterator = (Code.AsyncGeneratorObject) elmtIn.ref();
        startStep = (Promise) elmtIn.ref();
        sizeProp = (DynamicProperty.Receivable) elmtIn.ref();
        priorityProp = (DynamicProperty.Receivable) elmtIn.ref();
    }

    public virtual BatchObject mintBatchObject() {
        return new BatchObject(this);
    }

    // Here's something new - an <injected> code unit for an [async*] (asynchronous generator function)!
    public class AsyncIteratorFn extends Code.InjectedMethod {
        public AsyncIteratorFn(Realm hostRealm) {
            super(hostRealm, 'ApexBatch', 'Symbol.asyncIterator', 
            null,
            new String[]{
                // - Each following await resolves to "step" that is a plain object of form: { type, index, jobId, scope }
                // - Type "start" is always first.
                // - Type "execute" steps (0 or more) are the only ones to include property: (scope). These steps are each yielded in 
                // sequence, and this iterator is NOT done.
                // - Final type "finish" indicates this batch is exhausted. This step is returned (not yielded), which marks the 
                // iterator as done (i.e. for await...of loops consuming this [async*] will terminate on this step)
                'do {',
                '    let next = await this.internalNext;',
                '    switch (next?.type) {',
                '        case "start":',
                '        case "execute":',
                '            yield next;',
                '            break;',
                '        case "finish":',
                '            return next;',
                '        default:',
                '            break;',
                '    }',
                '} while (true);' // this must be the 1,000th do-while-true loop I've written in this project
            });
            compileFlags()
                .isAsync(true)
                .isGenerator(true);
            mutablePrototype.proto = hostRealm.AsyncGeneratorObjectPrototype;
            mutablePrototype.className = 'AsyncGenerator';
        }

        // Serializer.IntrinsicType implementation:
        public AsyncIteratorFn() { }
        public override System.Type getClass() {
            return AsyncIteratorFn.class;
        }
    }

    public class BatchObjectPrototype extends PObject {
        public BatchObjectPrototype(Realm realm) {
            // Prototype extends from plain ObjectPrototype and is named "BatchJobPrototype":
            super(realm.ObjectPrototype, 'BatchJobPrototype');
            // These methods of PObject will install a property of the given name with [[get]] and/or [[set]] accessor 
            // functions. These accessor functions use Types.CallContext.thisArg, and Assert that this value is an 
            // implementor of DynamicProperty.Accessible or reject the call with TypeError! This is what allows the 
            // accessors installed in this BatchObjectPrototype to dynamically "bind" to the actual BatchObject subclass 
            // instance where the Apex instance variables they need to access are defined:
            dynaGet(realm, 'internalNext');
            dynaGet(realm, 'start');
            dynaGetSet(realm, 'size');
            dynaGetSet(realm, 'priority');
            // Set batchObject[Symbol.asyncIterator] to a method that returns (this.asyncIterator) - the [async*] iterator we 
            // just injection-minted. Note how we mint a "getter" method and assign it as a normal data property (locked) to 
            // make a 0-arg "normal" method:
            dynaAsyncIterator(realm);
        }

        // Serializer.IntrinsicType implementation:
        public BatchObjectPrototype() { }
        public override System.Type getClass() {
            return BatchObjectPrototype.class;
        }
    }

    static BatchObjectPrototype BatchObjectProto;
    static BatchObjectPrototype getBatchObjectPrototype(Realm realm) {
        if (BatchObjectProto == null) {
            BatchObjectProto = new BatchObjectPrototype(realm);
        }
        return BatchObjectProto;
    }

    // Wraps an ApexQueryBatch and serves as its JavaScript interface:
    //public class BatchObject extends BatchObjectPrototype implements DynamicProperty.Accessible {
    public class BatchObject extends PObject implements DynamicProperty.Accessible {
        ApexBaseBatch apexBatch;

        public BatchObject(ApexBaseBatch apexBatch) {
            // Prototype is the singleton instance of BatchObjectPrototype:
            super(getBatchObjectPrototype(apexBatch.executor.hostRealm), 'BatchJob');
            this.apexBatch = apexBatch;
        }

        // Serializer.IntrinsicType implementation:
        public BatchObject() { }
        public override System.Type getClass() {
            return BatchObject.class;
        }
        public override void serFill(Serializer.SerialOut elmtOut) {
            super.serFill(elmtOut);
            elmtOut.ref(apexBatch);
        }
        public override void deserFill(Serializer.SerialIn elmtIn) {
            super.deserFill(elmtIn);
            apexBatch = (ApexBaseBatch) elmtIn.ref();
        }
        
        // DynamicProperty.Accessible implementation:
        // Properties defined here are meant to be accessible in JavaScript code through BatchObject. But we also have to define
        // the corresponding Getter / Setter properties in BatchObject.<init> - each as an instance of PropertyFn:
        public virtual Object prop(ExprMachine.EvalState evalState, DynamicProperty.AccessOperation op, String name, Object arg0) {
            switch on name {
                // Getter only
                when 'internalNext' {
                    switch on op {
                        when PropGet {
                            return apexBatch.internalNext;
                        }
                    }
                }
                // Getter only
                when 'start' {
                    return apexBatch.startStep;
                }
                // Getter + Setter
                when 'size' {
                    switch on op {
                        when PropGet {
                            return apexBatch.batchSize;
                        }
                        when PropSet {
                            apexBatch.batchSize = apexBatch.sizeProp.truncateInt(evalState, arg0);
                            return apexBatch.batchSize;
                        }
                    }
                }
                // Getter only
                when 'Symbol(Symbol.asyncIterator)' {
                    return apexBatch.asyncIterator;
                }
                // Getter + Setter
                when 'priority' {
                    switch on op {
                        when PropGet {
                            return apexBatch.priority;
                        }
                        when PropSet {
                            apexBatch.priority = apexBatch.priorityProp.truncateInt(evalState, arg0);
                            return apexBatch.priority;
                        }
                    }
                }
            }
            DynamicProperty.reject(evalState, op, name);
            return null;
        }
    }

    public class ChunkObject extends PObject implements DynamicProperty.Accessible {
        //ApexBaseBatch apexBatch;
        String type;
        Object jobId;
        Integer index;
        Object[] scope;

        public ChunkObject(Runtime.Host executor, String type, Object jobId, Integer index, Object[] scope) {
            // Prototype extends from plain ObjectPrototype and is named "BatchChunk":
            super(executor.hostRealm.ObjectPrototype, 'BatchChunk');
            this.type = type;
            this.jobId = jobId;
            this.index = index;
            this.scope = scope;
            final Realm hostRealm = executor.hostRealm;
            dynaGet(hostRealm, 'type');
            dynaGet(hostRealm, 'jobId');
            dynaGet(hostRealm, 'index');
            dynaGet(hostRealm, 'scope');
            dynaIterator(hostRealm);
        }

        // Serializer.IntrinsicType implementation:
        public ChunkObject() { }
        public override System.Type getClass() {
            return ChunkObject.class;
        }
        public override void serFill(Serializer.SerialOut elmtOut) {
            super.serFill(elmtOut);
            elmtOut.strRef(type);
            elmtOut.ref(jobId, new Object[]{ Serializer.TYPE_KEY_STRING, Serializer.TYPE_KEY_INTEGER });
            elmtOut.int(index);
            elmtOut.ref(scope, Object[].class);
        }
        public override void deserFill(Serializer.SerialIn elmtIn) {
            super.deserFill(elmtIn);
            type = elmtIn.strRef();
            jobId = elmtIn.ref();
            index = elmtIn.int();
            scope = (Object[]) elmtIn.ref();
        }

        // DynamicProperty.Accessible implementation:
        // Properties defined here are meant to be accessible in JavaScript code through BatchObject. But we also have to define
        // the corresponding Getter / Setter properties in BatchObject.<init> - each as an instance of PropertyFn:
        public virtual Object prop(ExprMachine.EvalState evalState, DynamicProperty.AccessOperation op, String name, Object arg0) {
            switch on name {
                when 'type' {
                    return type;
                }
                when 'jobId' {
                    return jobId;
                }
                when 'index' {
                    return index;
                }
                when 'scope' {
                    return scope;
                }
                when 'Symbol(Symbol.iterator)' {
                    return scope == null ? null : new ArrayIterator(evalState.hostRealm, 
                        new PArray(evalState.hostRealm, scope), 0);
                }
            }
            DynamicProperty.reject(evalState, op, name);
            return null;
        }
    }
}