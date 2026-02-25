/*
 * Mike Ulveling
 */
public without sharing class HierFlatten {

    public static HierFlatten TargetSelf(Schema.sObjectType hierType, String selfLookupField) {
        return init(new DirectedGraph.Builder(hierType, selfLookupField));
    }

    public static HierFlatten TargetSelf(Schema.sObjectType hierType, String primaryReferenceField, String parentReferenceField) {
        return init(new DirectedGraph.Builder(hierType, primaryReferenceField, parentReferenceField));
    }

    public static HierFlatten TargetChild(Schema.sObjectType childType, String childHierLookupField, 
            Schema.sObjectType hierType, String hierSelfLookupField) {
        HierFlatten flatten = init(new DirectedGraph.Builder(hierType, hierSelfLookupField));
        flatten.childType = childType;
        flatten.childHierLookupField = childHierLookupField;

        // Validate childType, childHierLookupField meta:
        if (childType == null) {
            throw new IllegalArgumentException('Target Child Type cannot be null');
        }
        Map<String, Schema.sObjectField> fieldsMap = childType.getDescribe().fields.getMap();
        Schema.DescribeFieldResult hierLkpDesc = fieldsMap.get(childHierLookupField)?.getDescribe();
        if (hierLkpDesc == null) {
            throw new IllegalArgumentException(
                'Hierarchy Lookup Field {' + childHierLookupField 
                    + '} does not exist on Target Child Type {' + childType + '}');
        } else {
            // Verify the hierarchy lookup:
            if (hierLkpDesc.getType() != Schema.DisplayType.REFERENCE) {
                throw new IllegalArgumentException(
                    'Hierarchy Lookup Field {' + childType + '.' + childHierLookupField 
                        + '} must be a Lookup; got {' + hierLkpDesc.getType().name() + '}');
            } else {
                Schema.sObjectType[] refTos = hierLkpDesc.getReferenceTo();
                Boolean gotMatch = false;
                for (Schema.sObjectType refTo : refTos) {
                    if (refTo == hierType) {
                        gotMatch = true;
                        break;
                    }
                }
                if (!gotMatch) {
                    throw new IllegalArgumentException(
                        'Hierarchy Lookup Field {' + childType + '.' + childHierLookupField 
                            + '} must be a Lookup to {' + hierType
                            + '}; got Lookup to {' + refTos[0] + '}');
                }
            }
            // Normalize the field name:
            flatten.childHierLookupField = hierLkpDesc.getName();
        }
        return flatten;
    }

    static HierFlatten init(DirectedGraph.Builder hierSpec) {
        HierFlatten flatten = new HierFlatten();
        flatten.hierSpec = hierSpec;
        return flatten;
    }

    public HierFlatten conditionalUpdates(Boolean flagVal) {
        this.conditionalUpdates = flagVal == true;
        return this;
    }

    public HierFlatten fillSelfLookup(String selfLookupField) {
        if (this.hierSpec.isLookupBased) {
            throw new IllegalArgumentException(
                'fillSelfLookup can only be used with hierarchies specifying a Parent Reference ' 
                    + 'Field that is an External ID; {' + this.hierSpec.parentReferenceField 
                    + '} is a Lookup');
        }
        
        // Validate selfLookupField meta:
        Map<String, Schema.sObjectField> fieldsMap = this.hierSpec.objectType.getDescribe().fields.getMap();
        Schema.DescribeFieldResult selfLkpDesc = fieldsMap.get(selfLookupField)?.getDescribe();
        if (selfLkpDesc == null) {
            throw new IllegalArgumentException('Self-Lookup Field {' + selfLookupField 
                + '} does not exist on {' + this.hierSpec.objectType + '}');
        } else {
            // Verify the self-lookup is actually a self-recursive lookup:
            if (selfLkpDesc.getType() != Schema.DisplayType.REFERENCE) {
                throw new IllegalArgumentException(
                    'Self-Lookup Field {' + this.hierSpec.objectType + '.' + selfLookupField 
                        + '} must be a Lookup; got {' + selfLkpDesc.getType().name() + '}');
            } else {
                Schema.sObjectType[] refTos = selfLkpDesc.getReferenceTo();
                Boolean gotMatch = false;
                for (Schema.sObjectType refTo : refTos) {
                    if (refTo == this.hierSpec.objectType) {
                        gotMatch = true;
                        break;
                    }
                }
                if (!gotMatch) {
                    throw new IllegalArgumentException(
                        'Self-Lookup Field {' + this.hierSpec.objectType + '.' + selfLookupField 
                            + '} must be a recursive Lookup to {' + this.hierSpec.objectType 
                            + '}; got Lookup to {' + refTos[0] + '}');
                }
            }
            // Normalize the field name:
            this.selfLookupField = selfLkpDesc.getName();
        }
        return this;
    }

    public HierFlatten fillLevelNumber(String levelField) {
        if (String.isBlank(levelField)) {
            throw new IllegalArgumentException(
                'Specified Level Number Field cannot be blank');
        }
        Schema.sObjectType hierType = this.hierSpec.objectType;
        Schema.sObjectType targetType = this.targetType;
        Map<String, Schema.sObjectField> fieldsMap = targetType.getDescribe().fields.getMap();
        Schema.DescribeFieldResult levelDesc = fieldsMap.get(levelField)?.getDescribe();
        if (levelDesc == null) {
            throw new IllegalArgumentException('Level Number Field {' + levelField 
                + '} does not exist on {' + targetType + '}');
        } else {
            this.levelNumFieldIsString = false;
            // Verify the target level number field is either a number or a plain string field:
            if (levelDesc.getType() == Schema.DisplayType.STRING) {
                if (levelDesc.getLength() < 2) {
                    throw new IllegalArgumentException(
                        'Level Number Field {' + targetType + '.' + levelField 
                            + '} must be a String of minimum length 2; got {' 
                            + levelDesc.getLength() + '}');
                }
                this.levelNumFieldIsString = true;
            } else if (levelDesc.getType() != Schema.DisplayType.INTEGER 
                    && levelDesc.getType() != Schema.DisplayType.DOUBLE) { 
                throw new IllegalArgumentException(
                    'Level Number Field {' + targetType + '.' + levelField 
                        + '} must be a String, Integer, or Double type; got {' 
                        + levelDesc.getType().name() + '}');
            }
            // Normalize the field name:
            this.levelNumField = levelDesc.getName();
        }
        return this;
    }

    public HierFlatten fillAncestorLookupsFrom(Integer fromLowestLevel, String ancestorFieldTemplate) {
        if (fromLowestLevel == null || fromLowestLevel < 1) {
            throw new IllegalArgumentException(
                'Specified Ancestor Level must be a positive integer; got ' 
                    + (fromLowestLevel == null ? 'NULL' : String.valueOf(fromLowestLevel)));
        }
        if (String.isBlank(ancestorFieldTemplate)) {
            throw new IllegalArgumentException(
                'Specified Ancestor Field Template cannot be blank');
        }
        // Validate each generated ancestorField:
        for (Integer lvl = fromLowestLevel; lvl >= 1; lvl--) {
            String ancestorField = String.format(ancestorFieldTemplate, new String[]{ String.valueOf(lvl) });
            this.fillAncestorLookup(lvl, ancestorField);
        }
        return this;
    }

    public HierFlatten fillAncestorLookup(Integer level, String ancestorField) {
        if (level == null || level < 1) {
            throw new IllegalArgumentException(
                'Specified Ancestor Level must be a positive integer; got ' + (level == null ? 'NULL' : String.valueOf(level)));
        }
        Schema.sObjectType hierType = this.hierSpec.objectType;
        Schema.sObjectType targetType = this.targetType;
        Map<String, Schema.sObjectField> fieldsMap = targetType.getDescribe().fields.getMap();
        Schema.DescribeFieldResult ancestorDesc = fieldsMap.get(ancestorField)?.getDescribe();
        if (ancestorDesc == null) {
            throw new IllegalArgumentException('Ancestor Level ' + level + ' Field {' + ancestorField 
                + '} does not exist on {' + targetType + '}');
        } else {
            // Verify the target ancestor field is either a hierarchy lookup or a plain string field:
            if (ancestorDesc.getType() == Schema.DisplayType.REFERENCE) {
                Schema.sObjectType[] refTos = ancestorDesc.getReferenceTo();
                Boolean gotMatch = false;
                for (Schema.sObjectType refTo : refTos) {
                    if (refTo == hierType) {
                        gotMatch = true;
                        break;
                    }
                }
                if (!gotMatch) {
                    throw new IllegalArgumentException(
                        'Ancestor Level ' + level + ' Field {' + targetType + '.' + ancestorField 
                            + '} must be a Lookup to {' + hierType 
                            + '}; got Lookup to {' + refTos[0] + '}');
                }
            } else if (ancestorDesc.getType() == Schema.DisplayType.STRING) { 
                if (ancestorDesc.getLength() < 18) {
                    throw new IllegalArgumentException(
                        'Ancestor Level ' + level + ' Field {' + targetType + '.' + ancestorField 
                            + '} must be a String of minimum length 18; got {' 
                            + ancestorDesc.getLength() + '}');
                }
            } else { 
                throw new IllegalArgumentException(
                    'Ancestor Level ' + level + ' Field {' + targetType + '.' + ancestorField 
                        + '} must be either a Lookup to {' + hierType 
                        + '} or a String; got {' + ancestorDesc.getType().name() + '}');
            }
            // Normalize the field name:
            this.ancestorLkpsByLevel.put(level, ancestorDesc.getName());
        }
        return this;
    }

    DirectedGraph.Builder hierSpec;
    Boolean conditionalUpdates = false;

    Map<Integer, String> ancestorLkpsByLevel = new Map<Integer, String>();
    String levelNumField;
    Boolean levelNumFieldIsString;

    // Only used when (targetsSelf == true) and fillSelfLookup() has been invoked:
    String selfLookupField;

    // Only used when (targetsSelf != true):
    Schema.sObjectType childType;
    String childHierLookupField;

    public Schema.sObjectType hierType {get{
        return this.hierSpec.objectType;
    }}

    public Boolean targetsSelf {get{
        return this.childType == null;
    }}

    public Schema.sObjectType targetType {get{
        return this.childType == null ? this.hierSpec.objectType : this.childType;
    }}

    // Performs the specified hierarchy "flattening" action upon the given scope of hiererachy 
    // nodes. NO structural relationship is necessary or implied for the given scope nodes - 
    // they can be from anywhere in the hierarchy, even totally at random! The hierarchy itself 
    // may be structured as multiple separate (unconnected) trees. Cyclical structures are 
    // tolerated, but will be ignored for "flattening" action. 
    public void go(sObject[] scope) {
        DirectedGraph graph;

        if (scope == null || scope.isEmpty()) {
            throw new IllegalArgumentException('Scope cannot be empty');
        }

        Schema.sObjectType scopeType = scope[0]?.getSObjectType();
        for (sObject elmt : scope) {
            Schema.sObjectType elmtType = elmt?.getSObjectType();
            if (scopeType != elmtType) {
                throw new IllegalArgumentException('Scope records must all be the same type; got ' 
                    + scopeType + ' and ' + (elmtType == null ? 'NULL' : String.valueOf(elmtType)));
            }
        }
        if (this.targetType != scopeType) {
            throw new IllegalArgumentException('Scope records must be of type ' 
                + this.targetType + '; got ' + (scopeType == null ? 'NULL' : String.valueOf(scopeType)));
        }

        Set<String> addSels = new Set<String>();
        addSels.add(this.selfLookupField);
        addSels.add(this.levelNumField);
        for (String ancestorField : this.ancestorLkpsByLevel.values()) {
            addSels.add(ancestorField);
        }
        addSels.remove(null);
        this.hierSpec.addSelects(new List<String>(addSels));

        if (this.targetsSelf) {
            // Note that we're assuming depth == 1. We'll throw an error if any referenced fields 
            // weren't queried on the scope records!
            graph = this.hierSpec.toGraph(scope, 1);
        } else {
            Set<Id> hierScope = new Set<Id>();
            for (sObject child : scope) {
                hierScope.add((Id) child.get(this.childHierLookupField));
            }
            hierScope.remove(null);
            graph = this.hierSpec.toGraph(hierScope);
        }

        Map<Id, Writeable> writeablesMap = new Map<Id, Writeable>();
        Map<Id, DirectedGraph.Path> pathsMap = graph.getStartPaths();
        for (sObject scopeElmt : scope) {
            Id hierId = this.targetsSelf ? scopeElmt.Id : (Id) scopeElmt.get(this.childHierLookupField);
            Map<Integer, Id> ancestorsByLevel = new Map<Integer, Id>();
            Integer levelNum;
            Id parentId;
            DirectedGraph.Path path = pathsMap.get(hierId);
            if (path != null) {
                DirectedGraph.Node node = path.start;
                parentId = node.next?.data.Id;
                if (!path.cyclic) {
                    levelNum = path.acyclicLength;
                    for (Integer nodeLevel = levelNum; nodeLevel > 0; nodeLevel--) {
                        ancestorsByLevel.put(nodeLevel, node.data.Id);
                        node = node.next;
                    }
                }
            }

            // Update a writable copy of scopeElmt:
            Writeable writer = writeablesMap.get(scopeElmt.Id);
            if (writer == null) {
                writeablesMap.put(scopeElmt.Id, writer = new Writeable(this, scopeElmt));
            }
            // TODO: rename this to parentLookupField?
            if (this.selfLookupField != null) {
                writer.put(this.selfLookupField, parentId);
            }
            if (this.levelNumField != null) {
                Object levelVal = this.levelNumFieldIsString == true 
                    ? (Object) (levelNum == null ? null : String.valueOf(levelNum)) 
                    : (Object) levelNum;
                writer.put(this.levelNumField, levelVal);
            }
            for (Integer lvl : this.ancestorLkpsByLevel.keySet()) {
                // !! We have to skip the "self" (identity) level writing (lvl == lvlNum), since 
                // it would create a CIRCULAR_DEPENDENCY DML error. The 1st ancestor we can actually 
                // write is the direct parent:
                // TODO: allow self-level writing if the target field is a STRING:
                // TODO: allow self-level writing if the target object is a child type:
                if (lvl < levelNum) {
                    String ancestorField = this.ancestorLkpsByLevel.get(lvl);
                    Id ancestorId = ancestorsByLevel.get(lvl);
                    writer.put(ancestorField, ancestorId);
                }
            }
        }

        sObject[] doUpdates = new sObject[]{};
        for (Writeable writer : writeablesMap.values()) {
            if (writer.output != null) {
                doUpdates.add(writer.output);
            }
        }
        if (doUpdates.size() > 0) {
            update doUpdates;
        }
    }

    // ================================================================================================
    // Performs the specified hierarchy "flattening" action upon the given scope of hiererachy 
    // nodes. NO structural relationship is necessary or implied for the given scope nodes - 
    // they can be from anywhere in the hierarchy, even totally at random! The hierarchy itself 
    // may be structured as multiple separate (unconnected) trees. Cyclical structures are 
    // tolerated, but will be ignored for "flattening" action. 
    public void go2(sObject[] scope) {
        //DirectedGraph graph;

        if (scope == null || scope.isEmpty()) {
            throw new IllegalArgumentException('Scope cannot be empty');
        }

        Schema.sObjectType scopeType = scope[0]?.getSObjectType();
        for (sObject elmt : scope) {
            Schema.sObjectType elmtType = elmt?.getSObjectType();
            if (scopeType != elmtType) {
                throw new IllegalArgumentException('Scope records must all be the same type; got ' 
                    + scopeType + ' and ' + (elmtType == null ? 'NULL' : String.valueOf(elmtType)));
            }
        }
        if (this.targetType != scopeType) {
            throw new IllegalArgumentException('Scope records must be of type ' 
                + this.targetType + '; got ' + (scopeType == null ? 'NULL' : String.valueOf(scopeType)));
        }

        Set<String> addSels = new Set<String>();
        addSels.add(this.selfLookupField);
        addSels.add(this.levelNumField);
        for (String ancestorField : this.ancestorLkpsByLevel.values()) {
            addSels.add(ancestorField);
        }
        addSels.remove(null);
        this.hierSpec.addSelects(new List<String>(addSels));

        Map<Id, HierAncestry.Node> ancestryPaths;
        if (hierSpec.isLookupBased) {
            Set<Id> startNodeIds = new Set<Id>();
            if (this.targetsSelf) {
                for (SObject startNode : scope) {
                    startNodeIds.add(startNode.Id);
                }
            } else {
                for (SObject startChild : scope) {
                    startNodeIds.add((Id) startChild.get(this.childHierLookupField));
                }
                startNodeIds.remove(null);
            }
            ancestryPaths = 
                HierAncestry.FromRecursiveNode(hierSpec.objectType, '' + hierSpec.parentLookup)
                    .fetch(startNodeIds);
            
        } else {
            if (this.targetsSelf) {
                Set<String> startNodeKeys = new Set<String>();
                for (SObject node : scope) {
                    startNodeKeys.add((String) node.get(hierSpec.primaryReferenceField));
                }
                startNodeKeys.remove(null);
                ancestryPaths = 
                    HierAncestry.FromKeyedNode(hierSpec.objectType, hierSpec.primaryReferenceField, hierSpec.parentReferenceField)
                        // !! TODO: make this a mutable setting in HierFlatten:
                        .caseInsensitive()
                        .fetchToIds(startNodeKeys);
            } else {
                Assert.fail('Cannot process key-based hierarchy from a child relationship target');
            }
        }

        Map<Id, Writeable> writeablesMap = new Map<Id, Writeable>();
        for (sObject scopeElmt : scope) {
            Id hierId = this.targetsSelf ? scopeElmt.Id : (Id) scopeElmt.get(this.childHierLookupField);
            Map<Integer, Id> ancestorsByLevel = new Map<Integer, Id>();
            Integer levelNum;
            Id parentId;
            HierAncestry.Node node = ancestryPaths.get(hierId);
            if (node != null) {
                parentId = node.parentId;
                if (!node.isCyclical) {
                    levelNum = node.parents.size() + 1;
                    for (Integer nodeLevel = levelNum; nodeLevel > 0; nodeLevel--) {
                        ancestorsByLevel.put(nodeLevel, node.nodeId);
                        node = node.parent;
                    }
                }
            }

            // Update a writable copy of scopeElmt:
            Writeable writer = writeablesMap.get(scopeElmt.Id);
            if (writer == null) {
                writeablesMap.put(scopeElmt.Id, writer = new Writeable(this, scopeElmt));
            }
            // TODO: rename this to parentLookupField?
            if (this.selfLookupField != null) {
                writer.put(this.selfLookupField, parentId);
            }
            if (this.levelNumField != null) {
                Object levelVal = this.levelNumFieldIsString == true 
                    ? (Object) (levelNum == null ? null : String.valueOf(levelNum)) 
                    : (Object) levelNum;
                writer.put(this.levelNumField, levelVal);
            }
            for (Integer lvl : this.ancestorLkpsByLevel.keySet()) {
                // !! We have to skip the "self" (identity) level writing (lvl == lvlNum), since 
                // it would create a CIRCULAR_DEPENDENCY DML error. The 1st ancestor we can actually 
                // write is the direct parent:
                // TODO: allow self-level writing if the target field is a STRING:
                // TODO: allow self-level writing if the target object is a child type:
                if (lvl < levelNum) {
                    String ancestorField = this.ancestorLkpsByLevel.get(lvl);
                    Id ancestorId = ancestorsByLevel.get(lvl);
                    writer.put(ancestorField, ancestorId);
                }
            }
        }

        sObject[] doUpdates = new sObject[]{};
        for (Writeable writer : writeablesMap.values()) {
            if (writer.output != null) {
                doUpdates.add(writer.output);
            }
        }
        if (doUpdates.size() > 0) {
            update doUpdates;
        }
    }
    // ================================================================================================

    class Writeable {
        HierFlatten context;
        sObject input;
        sObject output;

        Writeable(HierFlatten context, sObject input) {
            this.context = context;
            this.input = input;
        }

        public Boolean put(String field, Object value) {
            if (context.conditionalUpdates && this.input.get(field) == value) {
                return false;
            }
            if (this.output == null) {
                this.output = input.getSObjectType().newSObject(this.input.Id);
            }
            this.output.put(field, value);
            return true;
        }
    }
}