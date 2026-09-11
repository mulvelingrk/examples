public abstract class HierShareLooperPhaseBatch implements Database.Batchable<sObject> {
    public HierShareLooper.ProcessPhase phase;

    public HierShareLooperPhaseBatch(HierShareLooper.ProcessPhase phase) {
        this.phase = phase;
    }

    public abstract Database.QueryLocator start(Database.BatchableContext bc);

    public abstract void execute(Database.BatchableContext bc, List<SObject> scope);

    public virtual void finish(Database.BatchableContext bc) {
        this.phase.coordinator.finishPhase();
    }
}