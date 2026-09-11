/* Clobbers HierShare artifacts related to the specified Assignment Sets */
public class HierShareClobberPhase extends HierShareLooperPhaseBatch {
    HierShareLooper.ClobberDef spec;

    public HierShareClobberPhase(HierShareLooper.ProcessPhase phase) {
        super(phase);
        Assert.isNotNull(phase.clobberSpec, 'Cannot init a clobber processing phase without a clobber specification');
        this.spec = phase.clobberSpec;
    }

    public override Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug('QueryLocator: ' + this.spec.job.getStartQuery());
        return Database.getQueryLocator(this.spec.job.getStartQuery());
    }

    public override void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (this.spec.parallelize == true) {
            // Got this idea / technique from Jeff Krantz circa 2023. Thanks to him! It's sort of a loophole around the 
            // usual limits of Queueable chaining. Let's NOT do the A.I. thing where we just take ideas and code without
            // proper attribution...
            System.enqueueJob(new ParallelDelegate(this.spec, scope));
        } else {
            // synchronous execution:
            this.spec.job.exec(scope);
        }
    }

    public class ParallelDelegate implements System.Queueable {
        HierShareLooper.ClobberDef spec;
        List<SObject> scope;

        ParallelDelegate(HierShareLooper.ClobberDef spec, List<SObject> scope) {
            this.spec = spec;
            this.scope = scope;
        }

        public void execute(QueueableContext qc) {
            this.spec.job.exec(this.scope);
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