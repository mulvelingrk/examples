/*
 * Mike Ulveling
 *
 * Allows an explicit and narrow application of USER_MODE or SYSTEM_MODE security (across CRUD, FLS, and RLS) for 
 * core database operations. This is particularly useful for classes that need to execute in mixed modes depending 
 * on the operation.
 */
public abstract inherited sharing class DatabaseExecutor {

    public static final DatabaseExecutor SystemMode = new SystemExecutor();
    public static final DatabaseExecutor UserMode = new UserExecutor();

    public abstract Integer countQuery(String query);

    public abstract Integer countQueryWithBinds(String query, Map<String, Object> binds);

    public abstract sObject[] query(String query);

    public abstract sObject queryOne(String query);

    public abstract sObject[] queryWithBinds(String query, Map<String, Object> binds);

    public abstract sObject queryOneWithBinds(String query, Map<String, Object> binds);

    public abstract Database.SaveResult doInsert(sObject record);

    public abstract Database.SaveResult[] doInsert(sObject[] records);

    public abstract Database.SaveResult[] doInsert(sObject[] records, Boolean allOrNone);

    public abstract Database.SaveResult doUpdate(sObject records);

    public abstract Database.SaveResult[] doUpdate(sObject[] records);

    public abstract Database.SaveResult[] doUpdate(sObject[] records, Boolean allOrNone);

    public abstract Database.DeleteResult doDelete(sObject record);

    public abstract Database.DeleteResult[] doDelete(sObject[] records);

    public abstract Database.DeleteResult[] doDelete(sObject[] records, Boolean allOrNone);

    public without sharing class SystemExecutor extends DatabaseExecutor {
        public override Integer countQuery(String query) {
            return Database.countQuery(query, AccessLevel.SYSTEM_MODE);
        }

        public override Integer countQueryWithBinds(String query, Map<String, Object> binds) {
            return Database.countQueryWithBinds(query, binds ?? new Map<String, Object>(), AccessLevel.SYSTEM_MODE);
        }

        public override sObject[] query(String query) {
            return Database.query(query, AccessLevel.SYSTEM_MODE);
        }

        public override sObject queryOne(String query) {
            return Database.query(query, AccessLevel.SYSTEM_MODE);
        }

        public override sObject[] queryWithBinds(String query, Map<String, Object> binds) {
            return Database.queryWithBinds(query, binds ?? new Map<String, Object>(), AccessLevel.SYSTEM_MODE);
        }

        public override sObject queryOneWithBinds(String query, Map<String, Object> binds) {
            return Database.queryWithBinds(query, binds ?? new Map<String, Object>(), AccessLevel.SYSTEM_MODE);
        }

        public override Database.SaveResult doInsert(sObject record) {
            return Database.insert(record, true, AccessLevel.SYSTEM_MODE);
        }

        public override Database.SaveResult[] doInsert(sObject[] records) {
            return Database.insert(records, true, AccessLevel.SYSTEM_MODE);
        }

        public override Database.SaveResult[] doInsert(sObject[] records, Boolean allOrNone) {
            return Database.insert(records, allOrNone == true, AccessLevel.SYSTEM_MODE);
        }

        public override Database.SaveResult doUpdate(sObject record) {
            return Database.update(record, true, AccessLevel.SYSTEM_MODE);
        }

        public override Database.SaveResult[] doUpdate(sObject[] records) {
            return Database.update(records, true, AccessLevel.SYSTEM_MODE);
        }

        public override Database.SaveResult[] doUpdate(sObject[] records, Boolean allOrNone) {
            return Database.update(records, allOrNone == true, AccessLevel.SYSTEM_MODE);
        }

        public override Database.DeleteResult doDelete(sObject record) {
            return Database.delete(record, true, AccessLevel.SYSTEM_MODE);
        }

        public override Database.DeleteResult[] doDelete(sObject[] records) {
            return Database.delete(records, true, AccessLevel.SYSTEM_MODE);
        }

        public override Database.DeleteResult[] doDelete(sObject[] records, Boolean allOrNone) {
            return Database.delete(records, allOrNone == true, AccessLevel.SYSTEM_MODE);
        }
    }

    public with sharing class UserExecutor extends DatabaseExecutor {
        public override Integer countQuery(String query) {
            return Database.countQuery(query, AccessLevel.USER_MODE);
        }

        public override Integer countQueryWithBinds(String query, Map<String, Object> binds) {
            return Database.countQueryWithBinds(query, binds ?? new Map<String, Object>(), AccessLevel.USER_MODE);
        }

        public override sObject[] query(String query) {
            return Database.query(query, AccessLevel.USER_MODE);
        }

        public override sObject queryOne(String query) {
            return Database.query(query, AccessLevel.USER_MODE);
        }

        public override sObject[] queryWithBinds(String query, Map<String, Object> binds) {
            return Database.queryWithBinds(query, binds ?? new Map<String, Object>(), AccessLevel.USER_MODE);
        }

        public override sObject queryOneWithBinds(String query, Map<String, Object> binds) {
            return Database.queryWithBinds(query, binds ?? new Map<String, Object>(), AccessLevel.USER_MODE);
        }

        public override Database.SaveResult doInsert(sObject record) {
            return Database.insert(record, true, AccessLevel.USER_MODE);
        }

        public override Database.SaveResult[] doInsert(sObject[] records) {
            return Database.insert(records, true, AccessLevel.USER_MODE);
        }

        public override Database.SaveResult[] doInsert(sObject[] records, Boolean allOrNone) {
            return Database.insert(records, allOrNone == true, AccessLevel.USER_MODE);
        }

        public override Database.SaveResult doUpdate(sObject record) {
            return Database.update(record, true, AccessLevel.USER_MODE);
        }

        public override Database.SaveResult[] doUpdate(sObject[] records) {
            return Database.update(records, true, AccessLevel.USER_MODE);
        }

        public override Database.SaveResult[] doUpdate(sObject[] records, Boolean allOrNone) {
            return Database.update(records, allOrNone == true, AccessLevel.USER_MODE);
        }

        public override Database.DeleteResult doDelete(sObject record) {
            return Database.delete(record, true, AccessLevel.USER_MODE);
        }

        public override Database.DeleteResult[] doDelete(sObject[] records) {
            return Database.delete(records, true, AccessLevel.USER_MODE);
        }

        public override Database.DeleteResult[] doDelete(sObject[] records, Boolean allOrNone) {
            return Database.delete(records, allOrNone == true, AccessLevel.USER_MODE);
        }
    }
}