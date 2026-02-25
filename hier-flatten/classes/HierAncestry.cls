/* Mike Ulveling
 *
 * # Algorithm
 * Efficent graph path-finding algorithm for common forms of hierarchy-like and unweighted DAG 
 * (directed acyclic graph) structures. Takes "any" starting set of node ids or keys as input, 
 * and outputs either fully resolved node-parent chains (complete hierarchy ancestry) or 
 * flattened inheritance (DAGs like GroupMembers).
 * 
 * # Advantages and Efficiency:
 * - Can (and should) be strapped into batch processing by chunks
 * - Does NOT require the entire data structure to be stored in memory "at" once (see above)
 * - Does NOT require any particular node-ordering across chunks, nor within each chunk!
 * - Memory usage O(LOG(N)) * C per chunk, where C is chunk size and N is hierarchy size
 * - CPU usage O(LOG(N)) * C per chunk, where C is chunk size and N is hierarchy size
 * - SOQL Query usage O(LOG(N)) per chunk; further divide query usage by 5 for hierarchies 
 *   using a parent lookup field (versus parent key field). 
 */
global class HierAncestry {
    
    // Strategies:
    // - Node self-lookup (hier_type, parent_lookup)
    // - Node key-fields (hier_type, node_key, parent_key)
    // - Edges (edge_type, tail, head)

    static final Integer RECURSIVE_PARENT_DEPTH = 5;

    global static RecursiveNode FromRecursiveNode(Schema.SObjectType nodeType, String selfLookup) {
        if (nodeType == null) {
            illegalArg('Argument "nodeType" cannot be null');
        }
        if (String.isBlank(selfLookup)) {
            illegalArg('Argument "selfLookup" cannot be blank');
        }
        RecursiveNode builder = new RecursiveNode();
        builder.nodeType = nodeType;
        builder.parentLookup = nodeType.getDescribe().fields.getMap().get(selfLookup);
        Schema.DescribeFieldResult lookupDesc = builder.parentLookup?.getDescribe();
        String contextMsg = 'Self-Loopkup field ' + nodeType + '.' + selfLookup + ' ';
        if (lookupDesc == null) {
            illegalArg(contextMsg + 'does not exist');
        } else if (lookupDesc.getType() != Schema.DisplayType.REFERENCE) {
            illegalArg(contextMsg + 'must be a Lookup-type field; got ' + lookupDesc.getType().name());
        }
        Schema.SObjectType[] refTos = lookupDesc.getReferenceTo();
        if (refTos.size() != 1 || refTos[0] != nodeType) {
            illegalArg(contextMsg + 'must be a Lookup to ' + nodeType + '; got ' 
                + (refTos.size() > 1 ? '<polymorphic>' : refTos.size() == 1 ? '' + refTos[0] : '<unknown>'));
        }
        builder.parentRelName = lookupDesc.getRelationshipName();
        String[] deepSelectElmts = new String[0];
        for (Integer i = 0; i < RECURSIVE_PARENT_DEPTH; i++) {
            deepSelectElmts.add(builder.parentRelName);
        }
        deepSelectElmts.add('' + builder.parentLookup);
        builder.deepSelect = String.join(deepSelectElmts, '.');
        //builder.addSelect(String.join(deepSelect, '.'));
        return builder;
    }

    public abstract class AbstractBuilder  {
        Schema.SObjectType nodeType;
        // SELECT elements keyed by their lower-cased forms:
        Map<String, String> selects = new Map<String, String>();

        Integer degrees;
        Boolean loggingOn = true;
        Integer cyclesCount;

        public AbstractBuilder addSelect(String elmt) {
            selects.put(elmt?.toLowerCase(), elmt);
            return this;
        }

        public Boolean hasSelects() {
            selects.remove(null);
            return selects.keySet().size() > 0;
        }

        public String selects() {
            selects.remove(null);
            return String.join(selects.values(), ',');
        }
    
        public AbstractBuilder setLoggingOff() {
            this.loggingOn = false;
            return this;
        }

        public AbstractBuilder setLoggingOn() {
            this.loggingOn = true;
            return this;
        }

        public virtual Boolean statusSuccess() {
            return cyclesCount == 0;
        }
    }

    global class RecursiveNode extends AbstractBuilder {
        Schema.SObjectType nodeType;
        Schema.SObjectField parentLookup; // self-lookup
        String parentRelName;
        String deepSelect;

        Boolean loggingOn = true;
        Integer cyclesCount;

        private RecursiveNode() { }

        global RecursiveNode logginOff() {
            return (RecursiveNode) setLoggingOff();
        }

        global RecursiveNode logginOn() {
            return (RecursiveNode) setLoggingOn();
        }

        // SELECT R.R.R.R.R.parentId -- depth=5
        // SELECT R.parentId -- depth=1
        // SELECT parentId -- depth=0
        private Map<Id, Edge> mintEdges(SObject nodeData, Integer parentDepth) {
            Map<Id, Edge> edges = new Map<Id, Edge>();
            do {
                Edge newEdge = new Edge(nodeData.Id, (Id) nodeData.get(parentLookup));
                newEdge.nodeData = nodeData;
                newEdge.nodeDataDepth = parentDepth;
                edges.put(nodeData.Id, newEdge);
                if (--parentDepth < 0) {
                    break;
                }
                nodeData = nodeData.getSObject(parentRelName);
            } while (true);
            return edges;
        }

        global Map<Id, Node> fetch(Set<Id> startNodeIds) {
            this.degrees = 0;
            this.cyclesCount = 0;
            Logger.setScenario('Fetching Hierarchy Ancestry by Recursive Node');
            // Pass 1: Explore all known edges connected to a starting set of node ids:
            Map<Id, Edge> knownEdges = new Map<Id, Edge>();
            Set<Id> exploreNext = startNodeIds;
            do {
                // [ SELECT parentR.parentR.parentR.parentR.parentR.parentId FROM HierType WHERE Id IN :exploreNext ]
                SObject[] queryResults = Database.query(
                    'SELECT ' + deepSelect + //selects() + 
                    ' FROM ' + nodeType + 
                    ' WHERE Id IN :exploreNext');
                // Reset the explores for next "round":
                exploreNext = new Set<Id>();
                // Compile newly acquired edges local to this "round":
                Map<Id, Edge> newEdges = new Map<Id, Edge>();
                for (SObject rawNode : queryResults) {
                    newEdges.putAll(mintEdges(rawNode, RECURSIVE_PARENT_DEPTH));
                }
                // Add newly acquired edges to the complete known set:
                knownEdges.putAll(newEdges);
                // From the newly acquired edges, determine any not-previously-seen (unknown) parent ids;
                // these require query-exploration in the next "round":
                for (Edge newEdge : newEdges.values()) {
                    if (!knownEdges.containsKey(newEdge.parentId)) {
                        exploreNext.add(newEdge.parentId);
                    }
                }
                // We didn't put null-guards in the above logic so we have to filter it out here:
                exploreNext.remove(null);
                this.degrees++;
            } while (exploreNext.size() > 0); // do more "rounds" until we've nothing left to explore

            this.degrees--;
            // Pass 2: Build a DAG (graph) of nodes from the set of known edges:
            Map<Id, Node> knownNodes = new Map<Id, Node>();
            // For the 1st sub-pass we mint nodes with just their data, without parent references:
            for (Edge edge : knownEdges.values()) {
                Node node = new Node();
                node.data = edge.nodeData;
                knownNodes.put(edge.nodeId, node);
            }
            // Resolve node-parent references via a secondary sub-pass:
            for (Id nodeId : knownNodes.keySet()) {
                Node node = knownNodes.get(nodeId);
                Edge edge = knownEdges.get(nodeId);
                node.parent = knownNodes.get(edge?.parentId);
            }
            // If any supplemental selects were added to this builder, then we need a final bulk 
            // query to fetch these fields for all explored nodes:
            if (hasSelects()) {
                // Temporarily add the {parentLookup} into our set of optional selects:
                Map<String, String> savedSelects = this.selects.clone();
                addSelect('' + parentLookup);
                Set<Id> knownNodeIds = knownNodes.keySet();
                for (SObject enhancedNodeData : Database.query(
                    'SELECT ' + selects() + 
                    ' FROM ' + nodeType + 
                    ' WHERE Id IN :knownNodeIds')) {
                    Node node = knownNodes.get(enhancedNodeData.Id);
                    // Replace the node's original data with this wider "enhanced" data
                    // !! Note we'll lose the "deep" parent-references data from this, but it 
                    // shouldn't matter as parent Node relationships have been resolved:
                    node.data = enhancedNodeData;
                }
                // Restore the original supplemental selects (sans {parentLookup}):
                this.selects = savedSelects;
            }

            // Pass 3: Spit out a map of our starting point nodes; these now provide full ancestry 
            // via their resolved node-parent references:
            Map<Id, Node> marshalled = new Map<Id, Node>();
            for (Id startNodeId : startNodeIds) {
                Node startNode = knownNodes.get(startNodeId);
                startNode.flatten();
                if (startNode.isCyclical) {
                    Logger.error('Node with Id=' + startNode.nodeId 
                        + ' is part of a Cycle-Loop');
                    this.cyclesCount++;
                }
                marshalled.put(startNodeId, startNode);
            }
            
            if (loggingOn) {
                if (!statusSuccess()) {
                    Logger.saveLog();
                }
            }
            return marshalled;
        }
    }
    
    global static KeyedNode FromKeyedNode(Schema.SObjectType nodeType, String nodeKeyField, String parentKeyField) {
        if (nodeType == null) {
            illegalArg('Argument "nodeType" cannot be null');
        }
        if (String.isBlank(nodeKeyField)) {
            illegalArg('Argument "nodeKeyField" cannot be blank');
        }
        if (String.isBlank(parentKeyField)) {
            illegalArg('Argument "parentKeyField" cannot be blank');
        }
        KeyedNode builder = new KeyedNode();
        builder.nodeType = nodeType;

        builder.nodeKeyField = nodeType.getDescribe().fields.getMap().get(nodeKeyField);
        Schema.DescribeFieldResult nodeKeyDesc = builder.nodeKeyField?.getDescribe();
        String contextMsg = 'Node Key field ' + nodeType + '.' + nodeKeyField + ' ';
        if (nodeKeyDesc == null) {
            illegalArg(contextMsg + 'does not exist');
        } else if (nodeKeyDesc.getSOAPType() != Schema.SOAPType.STRING) {
            illegalArg(contextMsg + 'must be a String-type field; got ' + nodeKeyDesc.getType().name());
        }

        builder.parentKeyField = nodeType.getDescribe().fields.getMap().get(parentKeyField);
        Schema.DescribeFieldResult parentKeyDesc = builder.parentKeyField?.getDescribe();
        contextMsg = 'Parent Key field ' + nodeType + '.' + parentKeyField + ' ';
        if (parentKeyDesc == null) {
            illegalArg(contextMsg + 'does not exist');
        } else if (parentKeyDesc.getSOAPType() != Schema.SOAPType.STRING) {
            illegalArg(contextMsg + 'must be a String-type field; got ' + parentKeyDesc.getType().name());
        }

        if (builder.nodeKeyField == builder.parentKeyField) {
            illegalArg('Arguments "nodeKeyField" and "parentKeyField" cannot be the same field [' 
                + builder.nodeKeyField + ']');
        }
        builder
            .addSelect('' + builder.nodeKeyField)
            .addSelect('' + builder.parentKeyField);
        return builder;
    }

    // !! Node keys are currently case-sensitive
    // TODO: Need an option for case-insensitive keys...
    global class KeyedNode extends AbstractBuilder {
        Schema.SObjectField nodeKeyField;
        Schema.SObjectField parentKeyField;
        Boolean caseInsensitive = false;

        Integer clashingNodePairsCount = 0;
        Integer unresolvedNodeKeysCount = 0;
        Integer unresolvedParentKeysCount = 0;

        private KeyedNode() { }

        global KeyedNode logginOff() {
            return (KeyedNode) setLoggingOff();
        }

        global KeyedNode logginOn() {
            return (KeyedNode) setLoggingOn();
        }

        global KeyedNode caseSensitive() {
            this.caseInsensitive = false;
            return this;
        }

        global KeyedNode caseInsensitive() {
            this.caseInsensitive = true;
            return this;
        }

        // When {caseInsensitive} is engaged, this method normalizes keys on their lower-case form:
        private String normKey(String key) {
            return caseInsensitive ? key?.toLowerCase() : key;
        }

        private Edge mintEdge(SObject nodeData) {
            String nodeKey = (String) nodeData.get(nodeKeyField);
            //System.debug('Minting Edge { ' + nodeKey + ', ' + (String) nodeData.get(parentKeyField) 
            //    + ' } Degree=' + degrees);
            Edge newEdge = new Edge(nodeData.Id, nodeKey, (String) nodeData.get(parentKeyField));
            newEdge.nodeData = nodeData;
            return newEdge;
        }

        global override Boolean statusSuccess() {
            return cyclesCount + clashingNodePairsCount + unresolvedNodeKeysCount + unresolvedParentKeysCount == 0;
        }

        global Map<Id, Node> fetchToIds(Set<String> startNodeKeys) {
            Map<String, Node> pathsByKey = fetch(startNodeKeys);
            Map<Id, Node> pathsById = new Map<Id, Node>();
            for (Node startNode : pathsByKey.values()) {
                pathsById.put(startNode.data.Id, startNode);
            }
            return pathsById;
        }

        global Map<String, Node> fetch(Set<String> startNodeKeys) {
            this.degrees = 0;
            this.cyclesCount = 0;
            this.clashingNodePairsCount = 0;
            Logger.setScenario('Fetching Hierarchy Ancestry by Keyed Node');
            // Pass 1: Explore all known edges connected to a starting set of node ids:
            Map<String, Edge> knownEdges = new Map<String, Edge>();
            Set<String> exploreNextKeys = startNodeKeys;
            do {
                // [ SELECT parentR.parentR.parentR.parentR.parentR.parentId FROM HierType WHERE Id IN :exploreNext ]
                SObject[] queryResults = Database.query(
                    'SELECT ' + selects() + 
                    ' FROM ' + nodeType + 
                    ' WHERE ' + nodeKeyField + ' IN :exploreNextKeys');
                // Reset the explore keys for next "round":
                exploreNextKeys = new Set<String>();
                // Compile newly acquired edges local to this "round":
                Map<String, Edge> newEdges = new Map<String, Edge>();
                for (SObject rawNode : queryResults) {
                    Edge newEdge = mintEdge(rawNode);
                    Edge clashingEdge = newEdges.put(
                        normKey(newEdge.nodeKey), newEdge);
                    // !! Since our hierarchy nodes are key'd by {nodeKeyField} instead of by Id, we run 
                    // the risk of encountering multiple distinct nodes sharing the same {nodeKeyField} 
                    // value. This kind of clash is a critical error that corrupts the ancestry calculation 
                    // for connected nodes!
                    if (clashingEdge != null && clashingEdge.nodeId != newEdge.nodeId) {
                        this.clashingNodePairsCount++;
                        if (loggingOn) {
                            Logger.error('Node with Id=' + newEdge.nodeId + ' clashes with Id=' 
                                + clashingEdge.nodeId + ' by sharing Node Key [' + newEdge.nodeKey 
                                + ']').addTag('HierAncestry');
                        }
                        // We'll stick to the original edge definition for this key value, to hopefully 
                        // reduce the fuckery resulting from this clash:
                        newEdges.put(
                            normKey(clashingEdge.nodeKey), clashingEdge);
                    }
                }
                // Add newly acquired edges to the complete known set:
                knownEdges.putAll(newEdges);
                // From the newly acquired edges, determine any not-previously-seen (unknown) parent-keys;
                // these require query-exploration in the next "round":
                for (Edge newEdge : newEdges.values()) {
                    if (!knownEdges.containsKey(normKey(newEdge.parentKey))) {
                        // We don't have to normKey() here since the {exploreNextKeys} set is only used 
                        // for a SOQL IN condition where duplicates by letter-case won't matter:
                        exploreNextKeys.add(newEdge.parentKey);
                    }
                }
                // We didn't put null-guards in the above logic so we have to filter it out here:
                exploreNextKeys.remove(null);
                this.degrees++;
            } while (exploreNextKeys.size() > 0); // do more "rounds" until we've nothing left to explore

            this.degrees--;
            // Pass 2: Build a DAG (graph) of nodes from the set of known edges:
            Map<String, Node> knownNodes = new Map<String, Node>();
            // For the 1st sub-pass we mint nodes with just their data, without parent references:
            for (Edge edge : knownEdges.values()) {
                Node node = new Node();
                node.data = edge.nodeData;
                knownNodes.put(normKey(edge.nodeKey), node);
            }
            // Resolve node-parent references via a secondary sub-pass:
            for (String nodeKey : knownNodes.keySet()) {
                // {nodeKey} is already normalized because all keys in {knownNodes} are normalized:
                Node node = knownNodes.get(nodeKey);
                Edge edge = knownEdges.get(nodeKey);
                node.parent = knownNodes.get(normKey(edge?.parentKey));
                if (node.parent == null && edge?.parentKey != null) {
                    node.unresolvedParentKey = true;
                    this.unresolvedParentKeysCount++;
                    Logger.error('Node Id=' + node.data.Id + ' Key [' + nodeKey 
                        + '] has unresolvable Parent Key [' + edge.parentKey + ']').addTag('HierAncestry');
                }
            }

            // Pass 3: Spit out a map of our starting point nodes; these now provide full ancestry 
            // via their resolved node-parent references:
            Map<String, Node> marshalled = new Map<String, Node>();
            for (String startNodeKey : startNodeKeys) {
                Node startNode = knownNodes.get(normKey(startNodeKey));
                if (startNode == null) {
                    this.unresolvedNodeKeysCount++;
                    //Assert.fail('Unresolved start node Key [' + startNodeKey + ']');
                    Logger.error('Node Key [' 
                        + startNodeKey + '] cannot be resolved to a Node');
                }
                startNode.flatten();
                if (startNode.isCyclical) {
                    Logger.error('Node with Id=' + startNode.nodeId + ' Key [' 
                        + startNodeKey + '] is part of a Cycle-Loop');
                    this.cyclesCount++;
                }
                // Note how this retains the proper-case of input keys in {startNodeKeys}, even if 
                // this instance has been flagged {caseInsensitive}:
                marshalled.put(startNodeKey, startNode);
            }

            if (loggingOn) {
                if (!statusSuccess()) {
                    Logger.saveLog();
                }
            }
            return marshalled;
        }
    }

    // ============================================================================================

    /*
    global static RecursiveNode FromDAGEdges(Schema.SObjectType edgeType, String tailLookup, String arrowLookup) {
        if (nodeType == null) {
            illegalArg('Argument "nodeType" cannot be null');
        }
        if (String.isBlank(selfLookup)) {
            illegalArg('Argument "selfLookup" cannot be blank');
        }
        RecursiveNode builder = new RecursiveNode();
        builder.nodeType = nodeType;
        builder.parentLookup = nodeType.getDescribe().fields.getMap().get(selfLookup);
        Schema.DescribeFieldResult lookupDesc = builder.selfLookup?.getDescribe();
        String contextMsg = 'Self-Loopkup field ' + nodeType + '.' + selfLookup + ' ';
        if (lookupDesc == null) {
            illegalArg(contextMsg + 'does not exist');
        } else if (lookupDesc.getType() != Scheam.DisplayType.REFERENCE) {
            illegalArg(contextMsg + 'must be a Lookup-type field; got ' + lookupDesc.getType().name());
        }
        Schema.SObjectType[] refTos = lookupDesc.getReferenceTo();
        if (refTos.size() != 1 || refTos[0] != nodeType) {
            illegalArg(contextMsg + 'must be a Lookup to ' + nodeType + '; got ' 
                + (refTos.size() > 1 ? '<polymorphic>' : refTos.size() == 1 ? refTos[0] : '<unknown>'));
        }
        builder.parentRelName = lookupDesc.getRelationshipName();
        String[] deepSelect = new String[0];
        for (Integer i = 0; i < RECURSIVE_PARENT_DEPTH; i++) {
            deepSelect.add(builder.parentRelName);
        }
        deepSelect.add('' + builder.parentLookup);
        builder.deepParentSelects = new String[]{ String.join(deepSelect, '.') };
        return builder;
    }
    */

    // ============================================================================================

    // Represents a single { childNode -> parentNode } relationship "edge" in a hierarchy-like DAG 
    // graph of single-parent nodes:
    class Edge {
        // Each edge instance should populate either { nodeId, parentId } or { nodeKey, parentKey }; 
        // never both (mutually exclusive):
        Id nodeId;
        Id parentId;

        String nodeKey;
        String parentKey;

        SObject nodeData;
        Integer nodeDataDepth = 0;

        // Complete ancestry (ordered parentage) will be recorded here only for the requested "start" 
        // nodes. Ordered from closest (direct parent) to furthest ancestor (root):
        //global Id[] ancestors;

        Edge(Id nodeId, Id parentId) {
            this.nodeId = nodeId;
            this.parentId = parentId;
        }

        Edge(Id nodeId, String nodeKey, String parentKey) {
            this.nodeId = nodeId;
            this.nodeKey = nodeKey;
            this.parentKey = parentKey;
        }

        public override String toString() {
            return '{ ' + String.join(new String[]{ 
                nodeKey ?? nodeId, 
                parentKey ?? parentId }, ' 🡒 ') + ' }';
        }
    }

    global class Node {
        global SObject data;
        global Node parent;

        // Flattened ancestry output goes here - see method flatten():
        global Node[] parents;
        global Boolean isCyclical = false;
        global Boolean unresolvedParentKey = false;

        global Id nodeId {get{
            return data.Id;
        }}

        global Id parentId {get{
            return parent?.data.Id;
        }}

        // Follows the "parent" reference linked-list to produce a flat array of all parents for this node, 
        // in order of closest (direct parent) to furthest ancestor (root). Returns 1 if this node is part
        // of a cycle:
        Integer flatten() {
            this.parents = new Node[0];
            Node next = parent;
            while (next != null) {
                parents.add(next);
                // Cycle detection:
                if (this.data.Id == next.data.Id) {
                    return 1;
                }
                next = next.parent;
            }
            return 0;
        }
    }

    static void illegalArg(String message) {
        Logger.error(message).addTag('Configuration');
        throw new IllegalArgumentException(message);
    }
}

    /*
    global Map<Id, Edge> calculateAncestry(Set<Id> startNodeIds) {
        // Pass 1: Explore all known edges connected to a starting set of edges OR a starting explore-node-id:
        Map<Id, Edge> knownEdges = new Map<Id, Edge>();
        Set<Id> exploreNext = startNodeIds;
        do {
            SObject[] queryResults = [ SELECT parent.parent.parent.parent.parent FROM HierType WHERE Id IN :exploreNext ];
            exploreNext = new Set<Id>();
            Map<Id, Edge> newEdges = new Map<Id, Edge>();
            for (SObject rawNode : queryResults) {
                newEdges.putAll(mintEdges(rawNode, 5));
            }
            knownEdges.putAll(newEdges);
            for (Edge newEdge : newEdges.values()) {
                if (!knownEdges.containsKey(newEdge.parentId)) {
                    exploreNext.add(newEdge.parentId);
                }
            }
            exploreNext.remove(null);
        } while (exploreNext.size() > 0);

        // Pass 2: Build full ancestry paths for each starting node/edge:
        Map<Id, Edge> marshalled = new Map<Id, Edge>();
        for (Id startNodeId : startNodeIds) {
            Edge startEdge = knownEdges.get(startNodeId);
            marshalled.put(startNodeId, startEdge);
            startEdge.ancestors = new Id[0];
            Id nextParent = startNodeId;
            do {
                startEdge.ancestors.add(nextParent);
                nextParent = knownEdges.get(nextParent)?.parentId;
            } while (nextParent != null 
                    // Cycle safety: a single-parent graph can only cycle via a closed loop; we can always detect
                    // this as a repeat of the start node:
                    && nextParent != startNodeId);
            // (Optional) Remove the start node from ancestors chain, leaving only its parents:
            startEdge.ancestors.remove(0);
        }
        return marshalled;
    }
    */
