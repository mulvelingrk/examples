/*
 * Mike Ulveling
 *
 * Builds directed graph of records (of homogenous Object type) based on a parent relationship. 
 * The parent relationship may be defined as either (a or b):
 *   a. A self-recursive lookup field on an Object. In this case, the lookup serves as {parentKey},
 *      and the standard Id field as {primaryKey}.
 *   b. A pair of external-ID text fields on an object: {primaryKey} and {parentKey}.
 *
 * Initialize a graph by providing a starting scope of records. The graph will be constructed by 
 * a bottom-up traversal from each scope member, going though the parent relationship. When parent 
 * relationships are defined via lookup field, the traversal can extend 5 links deep per SOQL-query. 
 * When defined via external IDs, the traversal must extend by only 1 link per query. 
 * 
 * When applied to a recursive tree structure (e.g. RK Hierarchy), this builder works in "Bottom-Up"
 * fashion, as opposed to the more common "Top-Down" tree strategies (e.g. Depth-First, Breadth-First 
 * searches). 
 * 
 * As much as possible, queries are bulkified, and paths are nicely merged to avoid re-queries on
 * the same data. The intention of this approach is to be very query-efficient (lowest # of SOQL 
 * queries) for the following scenarios:
 * 1. Full hierarchy recalulations that need full ancestor paths for the calculation
 * 2. Leaf-level partial recalculations of the same nature as 1.
 * 
 * In addition to query efficiency, this algorithm is extremely well bounded / behaved towards 
 * heap memory and CPU consumption. With appropriate chunking, it is possible to scale this strategy 
 * to process hierarchies of ANY size.
 * 
 * Re-parenting operations represent the worst-case scenario for this bottom-up processing strategy. 
 * In the end, it's easiest to defer to a "full" bottom-up recalculation for these cases. Top-down 
 * strategies have some advantage here, for isolated re-parents, because they have a natural ability 
 * to do "partial" subtree re-calculations. However, this top-down advantage has a very narrow window, 
 * because it cannot be efficiently bulkified! By cleverly regulating "full" bottom-up recalculations 
 * (e.g. Apex Async framework), the bottom-up approach works well for handling bulk re-parents, or 
 * even spikes of many singular re-parents.
 */
public without sharing class DirectedGraph {

    public class Builder {
        public Schema.sObjectType objectType;
        public String primaryReferenceField;
        public String parentReferenceField;
        
        public Boolean isLookupBased;
        public Schema.SObjectField parentLookup; // only populated when isLookupBased == true
        public String parentRelationship; // only populated when isLookupBased == true
        
        public Integer queryDataDepth;
        public Set<String> additionalSelects;

        // Use this signature only for lookup-based parent relationships. The "Id" field is implied as primary key:
        public Builder(Schema.sObjectType objectType, String parentReferenceField) {
            this(objectTYpe, null, parentReferenceField);
        }
        
        // Use this signature for text-based parent relationships (External ID). In this case, the primary key
        // will typically be a String field other than Id: 
        public Builder(Schema.sObjectType objectType, String primaryReferenceField, String parentReferenceField) {
            this.objectType = objectType;
            this.primaryReferenceField = primaryReferenceField;
            this.parentReferenceField = parentReferenceField;
            this.additionalSelects = new Set<String>();

            if (objectType == null) {
                throw new IllegalArgumentException('Object Type cannot be null');
            }
            Map<String, Schema.sObjectField> fieldsMap = objectType.getDescribe().fields.getMap();
            Schema.DescribeFieldResult parentDesc = fieldsMap.get(parentReferenceField)?.getDescribe();
            if (parentDesc == null) {
                throw new IllegalArgumentException('Parent Reference {' + parentReferenceField 
                    + '} does not exist on {' + objectType + '}');
            } else {
                // Normalize the field name:
                this.parentReferenceField = parentDesc.getName();
            }

            // Parent reference field is a Lookup:
            if (parentDesc.getType() == Schema.DisplayType.REFERENCE) {
                this.isLookupBased = true;
                this.queryDataDepth = 5;
                this.parentLookup = parentDesc.getSObjectField();
                this.parentRelationship = parentDesc.getRelationshipName();

                // Verify parentReferenceField is a self-recursive lookup:
                sObjectType[] parentTypes = parentDesc.getReferenceTo();
                if (parentTypes.size() > 1) {
                    throw new IllegalArgumentException('Parent Lookup {' + objectType + '.' 
                        + parentReferenceField + '} cannot be polymorphic');
                } else if  (parentTypes[0] != objectType) {
                    throw new IllegalArgumentException('Parent Lookup {' + 
                        + parentReferenceField + '} must be a self-reference to {' + objectType 
                        + '}; got {' + parentTypes[0] + '}');
                }

                // Verify primaryReferenceField must be "Id" or null (implies "Id"):
                if (primaryReferenceField != null && primaryReferenceField != 'Id') {
                    throw new IllegalArgumentException('Primary Key for {' + 
                        + objectType + '} must be Id when Parent is a Lookup {' + parentReferenceField 
                        + '}; got {' + primaryReferenceField + '}');
                } else {
                    // Normalize the field name:
                    this.primaryReferenceField = primaryReferenceField = 'Id';
                }

            // Parent reference field is an External Id (text key):
            } else if (parentDesc.getSoapType() == Schema.SoapType.String) {
                this.isLookupBased = false;
                this.queryDataDepth = 1;

                if (primaryReferenceField == null) {
                    throw new IllegalArgumentException(
                        'Primary Reference field must be explicitly defined when Parent Reference field {' 
                            + parentReferenceField + '} is an External ID');
                }
                // Verify primaryReferenceField is a valid { String, Id, Reference } type field, and a different 
                // field than the parent reference:
                Schema.DescribeFieldResult primaryDesc = fieldsMap.get(primaryReferenceField)?.getDescribe();
                if (primaryDesc == null) {
                    throw new IllegalArgumentException('Primary Reference {' + primaryReferenceField 
                        + '} does not exist on {' + objectType + '}');
                } else if (primaryDesc.getSoapType() != Schema.SoapType.String 
                        && primaryDesc.getType() != Schema.DisplayType.REFERENCE 
                        && primaryDesc.getType() != Schema.DisplayType.ID) {
                    throw new IllegalArgumentException('Primary Reference {' + objectType + '.' + primaryReferenceField 
                        + '} must be a String, Id, or Lookup type; got {' + primaryDesc.getType().name() + '}');
                }
                this.primaryReferenceField = primaryDesc.getName();
                if (this.primaryReferenceField == this.parentReferenceField) {
                    throw new IllegalArgumentException('Primary Reference {' + objectType + '.' + primaryReferenceField 
                        + '} cannot be the same field as Parent Reference');
                }

            } else {
                throw new IllegalArgumentException('Parent Reference {' + objectType + '.' 
                    + parentReferenceField + '} must be either a self-Lookup or String type; got {' 
                    + parentDesc.getType().name() + '}');
            }
        }

        public Builder addSelects(String[] selects) {
            Map<String, Schema.sObjectField> fieldsMap = objectType.getDescribe().fields.getMap();
            // Validate the additional select fields:
            for (String sel : selects) {
                Schema.sObjectField field = fieldsMap.get(sel);
                if (field == null) {
                    throw new IllegalArgumentException('Additional select {' + sel + '} does not exist on {' 
                        + objectType + '}');
                } else {
                    this.additionalSelects.add('' + field);
                }
            }
            return this;
        }

        public DirectedGraph toGraph(sObject[] startScope, Integer startScopeDataDepth) {
            return this.toGraph(startScope, startScopeDataDepth, null);
        }

        public DirectedGraph toGraph(Set<Id> startScopeIds) {
            return this.toGraph(null, null, startScopeIds);
        }

        // temporary var for graph building:
        DirectedGraph graph;
        // temporary collection vars for graph building:
        Set<Id> unexploredNodeIds;
        Set<Id> exploreNextNodeIds;
        Set<String> exploreNextExternalIds;

        DirectedGraph toGraph(sObject[] startScope, Integer startScopeDataDepth, Set<Id> startScopeIds) {
            DirectedGraph graph = this.graph = new DirectedGraph();
            graph.objectType = this.objectType;
            graph.primaryReferenceField = this.primaryReferenceField;
            graph.parentReferenceField = this.parentReferenceField;
            graph.parentRelationship = this.parentRelationship;
            graph.isLookupBased = this.isLookupBased;
            
            // 1st pass: Any elements in startScopeIds must be queried at the greatest depth available.
            // Mint nodes from the query results:
            if (startScopeIds != null && startScopeIds.size() > 0) {
                graph.queryCount++;
                for (sObject nodeData : SOQLContext.newSystemMode()
                        .bind(startScopeIds)
                        .query(
                            'SELECT ' + this.getSelects() + 
                            ' FROM ' + this.objectType + 
                            ' WHERE Id IN ?')) {
                    // !! this.queryDataDepth must have been set on Builder construction...
                    graph.mintNode(nodeData, this.queryDataDepth);
                }
            }

            graph.startScopeIds = (startScopeIds ?? new Set<Id>()).clone();

            // 2nd pass: Any elements provided in startScope will skip an initial query; we mint their 
            // nodes at the specified data depth:
            if (startScope != null) {
                for (sObject nodeData : startScope) {
                    graph.startScopeIds.add(nodeData.Id);
                    // The mintNode() method only constructs a new node the 1st time for a given node id; 
                    // on subsequent requests it will attempt to extend() the previously minted node IFF
                    // sufficient data depth is provided:
                    graph.mintNode(nodeData, startScopeDataDepth ?? 1);
                }
            }

            // 2nd pass: Iteratively explore and resolve all nodes that have an unresolved next (parent) 
            // reference, until there are no more nodes in the graph's collection to explore - i.e. all 
            // possible connected nodes have been minted & resolved: 
            while (this.exploreNext() > 0) {}

            return graph;
        }

        // Returns the number of previously unresolved nodes that successfully explored their "next" 
        // links. When 0 is returned, it means there is no more exploring to do for the current Graph!
        private Integer exploreNext() {
            // reset temporary collections:
            this.resetExplore();
            for (Node node : this.graph.nodesById.values()) {
                if (!node.linkNext()) {
                    this.addUnexplored(node);
                }
            }
            KeySet exploreNextKeys = this.isLookupBased 
                ? new KeySet(this.exploreNextNodeIds) 
                : new KeySet(this.exploreNextExternalIds);
            //Set<Object> exploreNextKeys = this.isLookupBased 
            //    ? (Set<Object>) this.exploreNextNodeIds 
            //    : (Set<Object>) this.exploreNextExternalIds;
            if (exploreNextKeys.size() == 0) {
                return 0;
            }
            
            this.graph.queryCount++;
            sObject[] nextNodeDatas = SOQLContext.newSystemMode()
                .bind(exploreNextKeys.rawSet())
                .query(
                    'SELECT ' + this.getSelects() + 
                    ' FROM ' + this.objectType + 
                    ' WHERE ' + this.primaryReferenceField + ' IN ?');
            
            //Set<Object> brokenNextKeys = exploreNextKeys.clone();
            KeySet brokenNextKeys = exploreNextKeys.deepClone();
            for (sObject nextData : nextNodeDatas) {
                // If node was previously minted (i.e. in a prior iteration's extension), it will be 
                // automatically extended if we're supplying deeper data here:
                this.graph.mintNode(nextData, this.isLookupBased ? this.queryDataDepth : 1);
                Object nextDataKey;
                if (this.isLookupBased) {
                    nextDataKey = nextData.Id;
                } else {
                    nextDataKey = (String) nextData.get(this.primaryReferenceField);
                }
                brokenNextKeys.remove(nextDataKey);
            }

            // !! Handle case where our explore-next query did NOT return an expected nextData. This
            // can occur when a next-node was recently deleted (lookup-based), OR when an external-ID 
            // value is bogus (does not reference anything). These explore-nodes must be forcefully 
            // "terminated" as root, to prevent an infinite loop:
            Integer numExploredWithBrokenNext = 0;
            if (brokenNextKeys.size() > 0) {
                // Count the nodes we explored this round with broken "next" links:
                for (Id exploredId : this.unexploredNodeIds) {
                    Node exploredNode = this.graph.nodesById.get(exploredId);
                    Object exploredNextKey = this.isLookupBased 
                        ? (Object) exploredNode.getParentId() 
                        : (Object) exploredNode.getParentExternalId();
                    if (brokenNextKeys.contains(exploredNextKey)) {
                        // Next iteration's linkNext() will remove this node from "unexplored" since 
                        // it's now flagged as a terminating root:
                        exploredNode.isRoot = true;
                        exploredNode.brokenParentRef = true;
                        numExploredWithBrokenNext++;
                    }
                }
            }

            return this.unexploredNodeIds.size() - numExploredWithBrokenNext;
        }

        private void resetExplore() {
            this.unexploredNodeIds = new Set<Id>();
            this.exploreNextNodeIds = new Set<Id>();
            this.exploreNextExternalIds = new Set<String>();
        }

        private void addUnexplored(Node node) {
            // Filter out nodes that have been fully explored:
            if (node.isRoot == true || node.next != null) {
                return;
            }
            // "Amazing" Apex bug / quirk is exposed here if you remove the (Object) casts from this 
            // ternary's MHS and RHS operands. The Apex compiler sees the node.getParentId() return 
            // type "Id" (MHS) and then applies a hidden (Id) cast to the RHS argument, so that MHS 
            // and RHS are the same exact type (despite being assigned into a generic Object var 
            // "parentRef"). This causes an Id StringException to be thrown when the RHS evaluates 
            // and node.getParentExternalId()'s value is not in proper Id format (and it usually isn't).
            // Analysis: The Apex compiler is very strict but not very smart - just like most of my 
            // gradeschool teachers.
            Object parentRef = this.isLookupBased 
                ? (Object) node.getParentId() 
                : (Object) node.getParentExternalId();
            if (parentRef == null) {
                return;
            }
            this.unexploredNodeIds.add(node.getId());
            if (this.isLookupBased) {
                this.exploreNextNodeIds.add((Id) parentRef);
            } else {
                this.exploreNextExternalIds.add((String) parentRef);
            }
        }

        private String getSelects() {
            Set<String> selects = new Set<String>();
            String qualifier = '';
            // If this builder config is lookup-based, then all selected fields must be replicated from 1
            // to {queryDataDepth} through that number (i) of chained `${this.parentRelationship}.` qualifiers:
            for (Integer i=0; i < this.queryDataDepth; i++) {
                selects.add(qualifier + this.primaryReferenceField);
                selects.add(qualifier + this.parentReferenceField);
                for (String addl : this.additionalSelects) {
                    selects.add(qualifier + addl);
                }
                // Safeguard in case queryDataDepth was inexplicably set greater than 1 for a non-lookup 
                // parent relationship:
                if (!this.isLookupBased) {
                    break;
                }
                qualifier += this.parentRelationship + '.';
            }

            return String.join(new List<String>(selects), ',');
        }
    } // class Builder

    Schema.sObjectType objectType;
    String primaryReferenceField;
    String parentReferenceField;
    String parentRelationship;
    Boolean isLookupBased;
    Set<Id> startScopeIds;
    @TestVisible
    Integer queryCount = 0;

    // Nodes mapped by their Id values:
    Map<Id, Node> nodesById = new Map<Id, Node>();
    // Nodes mapped by their key values (e.g. Node_Code__c) - to be used in cases where 
    // NOT(this.isLookupBased):
    Map<String, Node> nodesByExternalId = new Map<String, Node>();

    public Map<Id, Path> getStartPaths() {        
        Map<Id, Path> paths = new Map<Id, Path>();
        for (Id startId : this.startScopeIds) {
            Node startNode = this.nodesById.get(startId);
            if (startNode == null) {
                continue;
            }
            Path path = new Path(this, startNode);
            paths.put(startId, path);

            Set<Id> visited = new Set<Id>();
            Node rootNode;
            Boolean cyclic = false;
            Integer acyclicLength = 0;
            Node cursor = startNode;
            while (cursor != null) {
                Id cursorId = cursor.getId();
                if (!visited.add(cursorId)) {
                    cyclic = true;
                    break;
                } 
                acyclicLength++;
                if (cursor.isRoot == true) {
                    rootNode = cursor;
                    break;
                }
                cursor = cursor.next;
            }

            path.root = rootNode;
            path.cyclic = cyclic;
            path.acyclicLength = acyclicLength;
        }
        return paths;
    }

    Node mintNode(sObject nodeData, Integer dataDepth) {
        // Check if this node was previously minted, and reuse that if so. Each distinct 
        // node in a DirectedGraph should only be constructed once:
        Node previouslyMinted = this.nodesById.get(nodeData.Id);
        if (previouslyMinted != null) {
            // Extend our previously minted node IFF we have sufficient depth with the 
            // newly provided data:
            if (dataDepth > previouslyMinted.dataDepth) {
                this.extendNode(previouslyMinted, nodeData, dataDepth);
            }
            return previouslyMinted;
        }

        Node newNode = new Node(this, nodeData, dataDepth);
        this.nodesById.put(nodeData.Id, newNode);
        if (!this.isLookupBased) {
            this.nodesByExternalId.put(newNode.getExternalId(), newNode);
        }

        // Mint the next node if we have sufficient data depth to do so:
        if (this.isLookupBased && dataDepth > 1) {
            sObject nextData = newNode.getParentSObject();
            // If the next node's data is null, then this node is the top-most terminating 
            // root node, and we're done exploring this path:
            if (nextData == null) {
                newNode.isRoot = true;
            } else {
                // Mints the next node with available data depth, or just retrieves it if 
                // previously constructed. If retrieved, then attempts to extend it with
                // available data depth:
                this.mintNode(nextData, dataDepth - 1);
            }
        }

        // Attempts to link (pointer) the next-node, which will only succeed when:
        //   1. This new node is not a "root", and therefore references "something" as next
        //   2. The next-node has been previously minted
        // If not, then linkNext() must be called again, after the referenced next-node has 
        // been properly minted:
        newNode.linkNext();
        return newNode;
    }

    void extendNode(Node node, sObject newNodeData, Integer newDataDepth) {
        if (this.isLookupBased && newDataDepth > node.dataDepth && node.isRoot != true) {
            node.data = newNodeData;
            node.dataDepth = newDataDepth;
            Node prevNode = node;
            Node nextNode = node.next;
            // Iterate through the chain of next nodes, as long as we have them (i.e. they 
            // were previously minted). Whenever we have more data depth available here than 
            // on its existing data, then "upgrade" it to the new data depth:
            Integer nextDataDepth = newDataDepth - 1;
            while (nextNode != null && nextNode.isRoot != true) {
                sObject nextData = prevNode.getParentSObject();
                // If we have more data depth available here than on the next node's existing 
                // data, then "updgrade" it:
                if (nextNode.dataDepth < nextDataDepth) {
                    nextNode.data = nextData;
                    nextNode.dataDepth = nextDataDepth;
                // Else if we have more data depth available on the next node's existing data 
                // than here, then upgrade nextDataDepth to reflect & preserve that:
                } else if (nextDataDepth < nextNode.dataDepth) {
                    nextDataDepth = nextNode.dataDepth;
                }
                prevNode = nextNode;
                nextNode = nextNode.next;
                nextDataDepth--;
            }
            if (nextNode == null && nextDataDepth > 0) {
                if (prevNode.getParentId() == null) {
                    prevNode.isRoot = true;
                } else {
                    nextNode = this.mintNode(prevNode.getParentSObject(), nextDataDepth);
                    // Link the prior to next because why not (it is guaranteed to succeed):
                    prevNode.linkNext();
                }
            }
        }
    }

    public class Path {
        public DirectedGraph host;
        public Node start;
        public Boolean cyclic;
        public Integer acyclicLength;
        public Node root;

        Path(DirectedGraph host, Node start) {
            this.host = host;
            this.start = start;
        }

        // Shows the path "chain", used for testing:
        public String ser(String sep) {
            Integer i=0;
            Node curs = this.start;
            String[] parts = new String[]{};
            while (curs != null && i <= this.acyclicLength) {
                parts.add(curs.getExternalId());
                curs = curs.next;
                i++;
            }
            if (this.cyclic == true) {
                parts.add('{cyclic}');
            }
            return String.join(parts, sep);
        }
    }

    public class Node {
        DirectedGraph host;
        public sObject data;
        public Integer dataDepth;
        public Node next;
        public Boolean isRoot;
        public Boolean brokenParentRef;

        Node(DirectedGraph host, sObject data, Integer dataDepth) {
            this.host = host;
            this.data = data;
            this.dataDepth = dataDepth ?? 1;
            this.isRoot = false;
            this.brokenParentRef = false;
        }

        public String getId() {
            return this.data.Id;
        }

        public String getExternalId() {
            return (String) this.data.get(this.host.primaryReferenceField);
        }

        public String getParentExternalId() {
            return (String) this.data.get(this.host.parentReferenceField);
        }

        public Id getParentId() {
            return (Id) this.data.get(this.host.parentReferenceField);
        }

        public sObject getParentSObject() {
            if (this.dataDepth < 2) {
                throw new GraphException('Node {' + data.Id 
                    + '} does not hold sufficient data depth to return parent data');
            }
            return this.data.getSObject(this.host.parentRelationship);
        }

        // All attempts to assign a "next" pointer must use this method. If the node has 
        // previously been "resolved" (linked to next or flagged as a root), then this 
        // method immediately returns true. In all other cases, this method attempts to 
        // resolve the node's "next" (parent) pointer, OR flag this node as root (when 
        // parent/next reference is null). If the node's data depth is not sufficient to 
        // resolve its "next" pointer, then the node remains "unexplored", and false is 
        // returned to indicate this status.
        Boolean linkNext() {
            Boolean resolved = false;
            // Node was previously resolved if it's flagged as root (terminating node), 
            // or the next-pointer is already populated:
            if (this.isRoot == true || this.next != null) {
                resolved = true;
            } else {
                // A newly resolved next-pointer will be populated here:
                Node nextPointer;
                if (this.host.isLookupBased) {
                    Id parentId = this.getParentId();
                    if (parentId == null) {
                        this.isRoot = true;
                    } else {
                        nextPointer = this.host.nodesById.get(parentId);
                    }
                } else {
                    String parentExtId = this.getParentExternalId();
                    if (parentExtId == null) {
                        this.isRoot = true;
                    } else {
                        nextPointer = this.host.nodesByExternalId.get(parentExtId);
                    }
                }

                if (nextPointer != null) {
                    this.next = nextPointer;
                    resolved = true;
                }
            }

            return resolved;
        }
    }

    public class KeySet {
        Set<Id> idKeys;
        Set<String> strKeys;

        public KeySet(Set<Id> ids) {
            this.idKeys = ids.clone();
        }

        public KeySet(Set<String> strs) {
            this.strKeys = strs.clone();
        }

        public Boolean remove(Object rawKey) {
            if (this.strKeys != null) {
                return this.strKeys.remove((String) rawKey);
            } else if (this.idKeys != null && (rawKey == null || rawKey instanceof Id)) {
                return this.idKeys.remove((Id) rawKey);
            }
            return false;
        }

        public Boolean contains(Object rawKey) {
            if (this.strKeys != null) {
                return this.strKeys.contains((String) rawKey);
            } else if (this.idKeys != null && (rawKey == null || rawKey instanceof Id)) {
                return this.idKeys.contains((Id) rawKey);
            }
            return false;
        }

        public Integer size() {
            if (this.idKeys != null) {
                return this.idKeys.size();
            } else if (this.strKeys != null) {
                return this.strKeys.size();
            } else {
                return 0;
            }
        }

        public Object rawSet() {
            return (Object) this.idKeys ?? (Object) this.strKeys;
        }

        public KeySet deepClone() {
            return this.idKeys != null ? new KeySet(this.idKeys) : new KeySet(this.strKeys);
        }
    }

    public class GraphException extends Exception {}
}